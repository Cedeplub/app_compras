"""Identidade e permissao. Espelha app_relatorios/core/auth.py, adaptado para
Oracle (schema COMPRAS) e para as colunas de APP_USUARIO/APP_SESSAO.

`autenticar()` e a UNICA porta por onde uma credencial entra no sistema.

Sessao e um token opaco (secrets.token_urlsafe) gravado em APP_SESSAO, nao um
JWT/cookie assinado: assim desativar um usuario (ATIVO=0) derruba a sessao
dele na hora - um cookie auto-contido so conseguiria esperando expirar.
"""
from __future__ import annotations

import datetime as dt
import logging
import secrets
from dataclasses import dataclass

import bcrypt
from fastapi import Cookie, Depends, HTTPException, Request

from app import config
from app.core import auditoria, database

log = logging.getLogger("app_compras.auth")

TAMANHO_TOKEN = 32


@dataclass
class Usuario:
    id: int
    login: str
    nome: str
    email: str | None
    ativo: bool
    eh_admin: bool
    eh_diretoria: bool
    senha_provisoria: bool
    origem: str


def _montar(linha: dict) -> Usuario:
    return Usuario(
        id=linha["id_usuario"],
        login=linha["login"],
        nome=linha["nome"],
        email=linha.get("email"),
        ativo=bool(linha["ativo"]),
        eh_admin=bool(linha["eh_admin"]),
        eh_diretoria=bool(linha["eh_diretoria"]),
        senha_provisoria=bool(linha["senha_provisoria"]),
        origem=linha["origem"],
    )


# ------------------------------------------------------------------ senha ---

def gerar_hash(senha: str) -> str:
    return bcrypt.hashpw(senha.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def conferir_senha(senha: str, senha_hash: str | None) -> bool:
    if not senha_hash:
        return False
    try:
        return bcrypt.checkpw(senha.encode("utf-8"), senha_hash.encode("ascii"))
    except ValueError:
        return False


def validar_forca(senha: str) -> str:
    """Devolve o motivo da recusa, ou string vazia se a senha serve."""
    if len(senha) < 8:
        return "A senha precisa ter ao menos 8 caracteres."
    if senha.isdigit() or senha.isalpha():
        return "A senha precisa misturar letras e números."
    return ""


# ----------------------------------------------------------- autenticacao ---

def autenticar(login: str, senha: str) -> Usuario | None:
    """None = credencial invalida ou usuario inativo. Nao distingue "login
    inexistente" de "senha errada": a tela nao deve confirmar quais logins
    existem.
    """
    linha = database.consultar_um(
        "select * from app_usuario where login = :login and ativo = 1",
        {"login": login.strip()},
    )
    if linha is None:
        # Gasta o tempo do hash mesmo sem usuario, para a resposta nao
        # denunciar pelo relogio quais logins existem.
        bcrypt.checkpw(b"x", bcrypt.hashpw(b"x", bcrypt.gensalt()))
        return None
    if linha["origem"] != "local":
        return None  # ponto de entrada do AD, quando existir
    if not conferir_senha(senha, linha["senha_hash"]):
        return None
    return _montar(linha)


def buscar_por_login(login: str) -> Usuario | None:
    linha = database.consultar_um(
        "select * from app_usuario where login = :login", {"login": login.strip()}
    )
    return _montar(linha) if linha else None


# --------------------------------------------------------------- sessoes ---

def abrir_sessao(usuario: Usuario, ip: str | None = None) -> str:
    token = secrets.token_urlsafe(TAMANHO_TOKEN)
    agora = dt.datetime.now()
    expira = agora + dt.timedelta(hours=config.SESSAO_HORAS)
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute(
            "insert into app_sessao (token, id_usuario, criado_em, expira_em, ip)"
            " values (:token, :id_usuario, :criado_em, :expira_em, :ip)",
            {
                "token": token,
                "id_usuario": usuario.id,
                "criado_em": agora,
                "expira_em": expira,
                "ip": ip,
            },
        )
        cur.execute(
            "update app_usuario set ultimo_acesso = :agora where id_usuario = :id",
            {"agora": agora, "id": usuario.id},
        )
        cur.close()
    return token


def usuario_da_sessao(token: str | None) -> Usuario | None:
    if not token:
        return None
    # EXPIRA_EM conferido a cada requisicao, mesmo antes de qualquer limpeza.
    linha = database.consultar_um(
        "select u.* from app_sessao s join app_usuario u on u.id_usuario = s.id_usuario"
        " where s.token = :token and s.expira_em > :agora and u.ativo = 1",
        {"token": token, "agora": dt.datetime.now()},
    )
    return _montar(linha) if linha else None


def fechar_sessao(token: str | None) -> None:
    if not token:
        return
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute("delete from app_sessao where token = :token", {"token": token})
        cur.close()


def fechar_sessoes_do_usuario(id_usuario: int) -> None:
    """Usada ao desativar usuario ou trocar senha: derruba tudo que estava aberto."""
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute("delete from app_sessao where id_usuario = :id", {"id": id_usuario})
        cur.close()


# ------------------------------------------------------------- usuarios ---

def criar_usuario(
    login: str,
    nome: str,
    senha: str,
    *,
    email: str | None = None,
    eh_admin: bool = False,
    eh_diretoria: bool = False,
    senha_provisoria: bool = True,
) -> int:
    with database.transacao() as conn:
        cur = conn.cursor()
        id_var = cur.var(int)
        cur.execute(
            """
            insert into app_usuario
                (login, nome, email, senha_hash, senha_provisoria, eh_admin, eh_diretoria)
            values
                (:login, :nome, :email, :senha_hash, :senha_provisoria, :eh_admin, :eh_diretoria)
            returning id_usuario into :id
            """,
            {
                "login": login,
                "nome": nome,
                "email": email,
                "senha_hash": gerar_hash(senha),
                "senha_provisoria": 1 if senha_provisoria else 0,
                "eh_admin": 1 if eh_admin else 0,
                "eh_diretoria": 1 if eh_diretoria else 0,
                "id": id_var,
            },
        )
        cur.close()
    return int(id_var.getvalue()[0])


def trocar_senha(id_usuario: int, nova_senha: str) -> None:
    with database.transacao() as conn:
        cur = conn.cursor()
        cur.execute(
            "update app_usuario set senha_hash = :hash, senha_provisoria = 0 where id_usuario = :id",
            {"hash": gerar_hash(nova_senha), "id": id_usuario},
        )
        cur.close()
    # Troca de senha invalida qualquer sessao antiga que ainda estivesse aberta
    # com a senha velha - menos a que acabou de ser aberta pelo proprio fluxo,
    # que a rota reabre em seguida.
    fechar_sessoes_do_usuario(id_usuario)


def garantir_admin_inicial() -> None:
    """Primeiro acesso: se APP_USUARIO estiver vazia, cria `admin` com senha
    aleatoria e mostra no log, uma unica vez, com SENHA_PROVISORIA=1."""
    total = database.consultar_um("select count(*) as n from app_usuario")
    if total and total["n"] > 0:
        return
    senha = secrets.token_urlsafe(9)
    criar_usuario(
        "admin", "Administrador", senha,
        eh_admin=True, eh_diretoria=True, senha_provisoria=True,
    )
    log.warning("=" * 70)
    log.warning("Usuario inicial criado: login=admin  senha=%s", senha)
    log.warning("Troca de senha obrigatoria no primeiro acesso.")
    log.warning("=" * 70)


# ---------------------------------------------------- dependencias FastAPI ---

def _sem_permissao_404():
    # Pedir recurso sem permissao devolve 404, nao 403 - nao revela que existe.
    return HTTPException(status_code=404, detail="Não encontrado.")


def usuario_atual(
    request: Request,
    token: str | None = Cookie(default=None, alias=config.COOKIE_NOME),
) -> Usuario | None:
    return usuario_da_sessao(token)


def exigir_login(usuario: Usuario | None = Depends(usuario_atual)) -> Usuario:
    if usuario is None:
        raise HTTPException(status_code=401, detail="Sessão expirada ou inexistente.")
    return usuario


def exigir_diretoria(usuario: Usuario = Depends(exigir_login)) -> Usuario:
    # A tela pode esconder o botao; quem recusa e a API. 404, nunca 403
    # (CONTEXTO §4 / regra de gravacao 4 da Etapa 6a).
    if not usuario.eh_diretoria:
        raise _sem_permissao_404()
    return usuario


def exigir_admin(usuario: Usuario = Depends(exigir_login)) -> Usuario:
    if not usuario.eh_admin:
        raise _sem_permissao_404()
    return usuario
