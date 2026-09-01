"""API JSON do v2, montada em `/api`.

O que muda em relação à Etapa 6: as rotas devolvem JSON em vez de HTML. O que
NÃO muda: sessão, perfil, auditoria e a fronteira de acesso ao banco continuam
sendo os mesmos módulos, sem uma segunda implementação. Autenticação que já
funciona e já foi revisada não se reescreve porque o front mudou de tecnologia.

Convenções desta camada:
  * 401 quando não há sessão — o cliente redireciona para o login.
  * 404, nunca 403, quando o usuário não tem perfil para o recurso: 403
    confirma que o recurso existe (CONTEXTO.md §4).
  * o corpo de erro é sempre `{"detail": "..."}`, igual ao do FastAPI.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.exceptions import HTTPException
from pydantic import BaseModel

from app import config
from app.api import contrato
from app.core import auditoria, auth, database
from app.servicos import produto

log = logging.getLogger("app_compras.api")

router = APIRouter(prefix="/api")

# Teto de página. Sem isto, `?porPagina=100000` transforma uma tela de consulta
# numa varredura de 8.772 linhas com os alertas de todas elas — o cliente nem
# precisa ser malicioso, basta um erro de digitação.
MAX_POR_PAGINA = 200


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


# ------------------------------------------------------------------ sessão ---

@router.get("/sessao")
def sessao(usuario=Depends(auth.exigir_login)):
    return {"usuario": contrato.usuario(usuario)}


class Credenciais(BaseModel):
    login: str
    senha: str


@router.post("/login")
def login(request: Request, response: Response, dados: Credenciais):
    u = auth.autenticar(dados.login, dados.senha)
    if u is None:
        # Mensagem única para login inexistente e senha errada: dizer qual dos
        # dois falhou entrega metade da credencial a quem está tentando.
        raise HTTPException(status_code=401, detail="Login ou senha inválidos.")
    token = auth.abrir_sessao(u, _ip(request))
    auditoria.registrar_isolado(u.id, "LOGIN", ip=_ip(request))
    response.set_cookie(
        config.COOKIE_NOME, token,
        httponly=True, samesite="lax", secure=config.COOKIE_SECURE,
        max_age=config.SESSAO_HORAS * 3600,
    )
    return {"usuario": contrato.usuario(u)}


@router.post("/logout")
def logout(request: Request, response: Response,
           usuario=Depends(auth.usuario_atual)):
    auth.fechar_sessao(request.cookies.get(config.COOKIE_NOME))
    if usuario:
        auditoria.registrar_isolado(usuario.id, "LOGOUT", ip=_ip(request))
    response.delete_cookie(config.COOKIE_NOME)
    return {"ok": True}


# ------------------------------------------------------------------ dados ---

@router.get("/parametros")
def parametros(usuario=Depends(auth.exigir_login)):
    """Os parâmetros do modelo que a tela precisa para recalcular ao vivo.

    Existe para que FATOR_PRAZO, COMISSAO e o limiar de cobertura crítica NÃO
    sejam constantes escritas no JavaScript. No protótipo eles são (§4.6), e o
    risco é a tela calcular margem com um número e o banco com outro — dois
    resultados plausíveis, nenhum aviso.
    """
    linha = database.consultar_um("select * from compras_parametro")
    if linha is None:
        raise HTTPException(status_code=503, detail="Parâmetros ainda não materializados.")
    return {k: (float(v) if v is not None and not isinstance(v, str) else v)
            for k, v in linha.items()}


@router.get("/opcoes")
def opcoes(usuario=Depends(auth.exigir_login)):
    return produto.opcoes()


@router.get("/produtos")
def listar_produtos(
    usuario=Depends(auth.exigir_login),
    departamento: str | None = None,
    comprador: str | None = None,
    classe: str | None = None,
    status: str | None = None,
    busca: str | None = None,
    tipoAlerta: list[str] | None = Query(default=None),
    soComAlerta: bool = False,
    ordenacao: str = "codigo",
    pagina: int = 1,
    porPagina: int = 50,
):
    porPagina = max(1, min(porPagina, MAX_POR_PAGINA))
    filtros = {
        "departamento": departamento,
        "comprador": comprador,
        "classe": classe,
        "status": status,
        "busca": busca,
        "tipos_alerta": tipoAlerta,
        "so_com_alerta": soComAlerta,
    }
    linhas, total = produto.listar(filtros, pagina, porPagina, ordenacao)
    return contrato.pagina(linhas, total, pagina, porPagina)


@router.get("/produtos/{codigo}")
def obter_produto(codigo: int, usuario=Depends(auth.exigir_login)):
    linha = produto.obter(codigo)
    if linha is None:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    return contrato.produto(linha)
