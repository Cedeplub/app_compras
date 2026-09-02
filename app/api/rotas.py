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
from pydantic import BaseModel, model_validator

from app import config
from app.api import alertas, contrato
from app.core import auditoria, auth, database
from app.servicos import preco, produto

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
    """Listas dos filtros + os metadados de cada tipo de alerta.

    Os metadados (rótulo, peso, severidade) saem daqui, e não de uma tabela no
    JavaScript, porque o MESMO peso ordena a lista no SQL. Duas cópias e a tela
    legenda uma ordem que o banco não usou.
    """
    return {**produto.opcoes(), "alertas": alertas.metadados()}


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
    # 'DECISAO' na tela de Alertas, 'CADASTRO' na de Pendências. Sem valor, os
    # dois universos entram — que é o que a busca por produto quer.
    categoria: str | None = None,
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
        "categoria": categoria,
    }
    linhas, total = produto.listar(filtros, pagina, porPagina, ordenacao)
    corpo = contrato.pagina(linhas, total, pagina, porPagina)
    # Agregados do FILTRO inteiro, não da página. Vão junto da listagem em vez
    # de numa rota separada porque a tela precisa dos dois ao mesmo tempo: duas
    # chamadas independentes podem responder fora de ordem e mostrar KPI de um
    # filtro sobre a lista de outro.
    corpo["resumo"] = produto.resumo(filtros)
    corpo["contagemAlertas"] = produto.contagem_por_tipo(filtros)
    return corpo


@router.get("/produtos/{codigo}")
def obter_produto(codigo: int, usuario=Depends(auth.exigir_login)):
    linha = produto.obter(codigo)
    if linha is None:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    return contrato.produto(linha)


# --------------------------------------------------------- decisão de preço ---

class DecisaoPreco(BaseModel):
    """Corpo de POST /produtos/{codigo}/preco.

    Nomes em camelCase (convenção da API, ver `contrato.py`); a tradução para
    as colunas de APP_DECISAO_PRECO (margem_alvo, margem_alvo_varejo,
    alt_pv_at_av, alt_pv_var_av) acontece só aqui — `app/servicos/preco.py`
    continua falando o vocabulário do banco.

    `precoAtacadoAP`/`precoVarejoAP` existem só para produzir um erro 422
    explícito: o preço a prazo é DERIVADO do preço à vista pelo fator de
    prazo, nunca gravado — guardar os dois criaria duas verdades.
    """

    margemAlvo: float | None = None
    margemAlvoVarejo: float | None = None
    precoAtacadoAV: float | None = None
    precoVarejoAV: float | None = None
    precoAtacadoAP: float | None = None
    precoVarejoAP: float | None = None

    @model_validator(mode="after")
    def _validar(self) -> "DecisaoPreco":
        if self.precoAtacadoAP is not None or self.precoVarejoAP is not None:
            raise ValueError(
                "Preço a prazo não é gravado diretamente: ele é derivado do "
                "preço à vista pelo fator de prazo. Envie precoAtacadoAV "
                "e/ou precoVarejoAV."
            )
        campos = (self.margemAlvo, self.margemAlvoVarejo,
                  self.precoAtacadoAV, self.precoVarejoAV)
        if all(c is None for c in campos):
            raise ValueError(
                "Informe ao menos um campo: margemAlvo, margemAlvoVarejo, "
                "precoAtacadoAV ou precoVarejoAV."
            )
        # Mesmos limites das constraints de APP_DECISAO_PRECO
        # (sql/02_tabelas_app.sql: ck_app_decisao_preco_ma/_mav/_pv/_pvv),
        # verificados aqui para devolver 422 com mensagem em português em vez
        # de deixar o banco estourar um erro genérico.
        for nome, valor in (("margemAlvo", self.margemAlvo),
                             ("margemAlvoVarejo", self.margemAlvoVarejo)):
            if valor is not None and not (-1 <= valor <= 1):
                raise ValueError(
                    f"{nome} deve estar entre -1 e 1 (fração; ex. 0.20 = 20%)."
                )
        for nome, valor in (("precoAtacadoAV", self.precoAtacadoAV),
                             ("precoVarejoAV", self.precoVarejoAV)):
            if valor is not None and valor <= 0:
                raise ValueError(f"{nome} deve ser maior que zero.")
        return self


@router.post("/produtos/{codigo}/preco")
def gravar_preco(
    codigo: int,
    dados: DecisaoPreco,
    request: Request,
    # Gravar preço é a decisão humana do modelo (CONTEXTO.md §6 regra 10); a
    # tela pode esconder o botão, quem recusa é a API. 404, nunca 403 — quem
    # não é diretoria não deve nem saber que a rota existe.
    usuario=Depends(auth.exigir_diretoria),
):
    if produto.obter(codigo) is None:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    try:
        preco.gravar_decisao_preco(
            codigo,
            dados.margemAlvo,
            dados.margemAlvoVarejo,
            dados.precoAtacadoAV,
            dados.precoVarejoAV,
            usuario.login,
            usuario.id,
            _ip(request),
        )
    except database.oracledb.IntegrityError as exc:  # type: ignore[attr-defined]
        # Rede de segurança: qualquer constraint que a validação acima não
        # cobriu (ex. corrida entre duas gravações concorrentes na mesma
        # linha) vira 422 explicado, não um 500.
        raise HTTPException(
            status_code=422, detail=f"Valor recusado pelo banco: {exc}"
        )

    # Produto ATUALIZADO, no mesmo formato de GET /produtos/{codigo} — inclui
    # a sobreposição ao vivo de ALT_PV_AT_AV/ALT_PV_VAR_AV feita em
    # produto._sobrepor_preco_decidido, senão a tela mostraria o preço velho
    # logo após gravar (COMPRAS_PEDIDO só atualiza no próximo `dbt run`).
    linha = produto.obter(codigo)
    return contrato.produto(linha)
