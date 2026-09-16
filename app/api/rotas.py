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

import datetime as dt
import logging

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.exceptions import HTTPException
from pydantic import BaseModel, model_validator

from app import config
from app.api import alertas, contrato
from app.core import auditoria, auth, database
from app.servicos import atualizacao, lote_preco, monitoramento, pedido, preco, produto

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
    # Data vira texto ISO; o resto vira float. Sem o ramo de data, o `float()`
    # estouraria num datetime e a rota inteira cairia em 500 — e ela é chamada
    # por TODA tela que recalcula margem.
    def _valor(v):
        if v is None or isinstance(v, str):
            return v
        if isinstance(v, (dt.datetime, dt.date)):
            return v.strftime("%Y-%m-%d")
        return float(v)

    return {k: _valor(v) for k, v in linha.items()}


@router.get("/atualizacao")
def obter_atualizacao(usuario=Depends(auth.exigir_login)):
    """Carimbo de frescor da carga: última execução do dbt + data de referência.

    Qualquer usuário logado enxerga — não é decisão de negócio, é a data que já
    aparece no cabeçalho. Memoizar isto no cliente esconderia justamente o
    carimbo que motivou a rota (§ Etapa 12); por isso ela é sempre chamada de
    novo, ao contrário de `/api/parametros`.
    """
    return atualizacao.estado()


@router.post("/atualizacao", status_code=202)
def disparar_atualizacao(request: Request, usuario=Depends(auth.exigir_login)):
    """Dispara `dbt/atualizar.py` em background e devolve o estado atual.

    Aberta a qualquer usuário logado: atualizar não altera nenhuma decisão, só
    recarrega o Winthor. A recusa (já em andamento / recém-concluída) vira
    HTTPException com mensagem em português — ela aparece direto na tela.
    """
    try:
        resultado = atualizacao.disparar(usuario.login)
    except atualizacao.AtualizacaoEmAndamento as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except atualizacao.AtualizacaoRecente as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    auditoria.registrar_isolado(usuario.id, "ATUALIZAR_DADOS", ip=_ip(request))
    return resultado


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
    # Intervalo de última entrada (COMPRAS_PEDIDO.DT_ULT_ENT). Independentes:
    # cada lado filtra sozinho se o outro não vier.
    dtUltEntDe: str | None = None,
    dtUltEntAte: str | None = None,
    # "com"/"sem" estoque, whitelist estrita — vira `where` no servidor
    # (produto._condicoes), mesma regra que já vale para `ordenar`.
    estoque: str | None = None,
    # `ordenar` é entrada de usuário virando `order by` — o whitelist de
    # `produto.ORDENACOES_VALIDAS` é a única defesa (§8.2/1-2). `dir` alterna
    # crescente/decrescente a partir do clique no cabeçalho (§3.2/§3.4);
    # ausente, cada coluna usa a direção padrão do primeiro clique.
    ordenar: str = "codigo",
    dir: str | None = None,
    # Qual das três margens ordenar quando ordenar=margem|mkp|custo. A tela de
    # Precificação troca isso junto com o seletor de cenário.
    cenarioMargem: str | None = None,
    pagina: int = 1,
    porPagina: int = 50,
):
    if ordenar not in produto.ORDENACOES_VALIDAS:
        raise HTTPException(
            status_code=422, detail=f"ordenar inválido: {ordenar!r}.")
    if dir is not None and dir not in ("asc", "desc"):
        raise HTTPException(
            status_code=422, detail=f"dir inválido: {dir!r} (use 'asc' ou 'desc').")
    if estoque not in (None, "com", "sem"):
        raise HTTPException(
            status_code=422,
            detail=f"estoque inválido: {estoque!r} (use 'com' ou 'sem').")
    porPagina = max(1, min(porPagina, MAX_POR_PAGINA))
    # Nunca string crua para bind de data (ORA-01861 já aconteceu neste
    # projeto — ver app/servicos/monitoramento.py:_data). 422 com mensagem em
    # português se vier malformada, em vez de estourar no Oracle.
    def _data(rotulo: str, iso: str | None):
        if not iso:
            return None
        try:
            return dt.date.fromisoformat(iso)
        except ValueError:
            raise HTTPException(
                status_code=422,
                detail=f"{rotulo} inválida: {iso!r} (esperado AAAA-MM-DD).",
            )

    filtros = {
        "departamento": departamento,
        "comprador": comprador,
        "classe": classe,
        "status": status,
        "busca": busca,
        "tipos_alerta": tipoAlerta,
        "so_com_alerta": soComAlerta,
        "categoria": categoria,
        "dt_ult_ent_de": _data("dtUltEntDe", dtUltEntDe),
        "dt_ult_ent_ate": _data("dtUltEntAte", dtUltEntAte),
        "cenario_margem": cenarioMargem,
        "estoque": estoque,
    }
    linhas, total = produto.listar(filtros, pagina, porPagina, ordenar, dir)
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


class ItemDecisaoPreco(DecisaoPreco):
    """Um item do lote: mesmo corpo do unitário + o código do produto."""

    codigo: int


class LotePrecoPayload(BaseModel):
    itens: list[ItemDecisaoPreco]

    @model_validator(mode="after")
    def _validar(self) -> "LotePrecoPayload":
        if not self.itens:
            raise ValueError("Envie ao menos um item no lote.")
        if len(self.itens) > preco.LIMITE_LOTE_PRECO:
            raise ValueError(
                f"Lote com {len(self.itens)} itens excede o limite de "
                f"{preco.LIMITE_LOTE_PRECO}. Grave em lotes menores."
            )
        return self


@router.post("/produtos/preco")
def gravar_preco_lote(
    dados: LotePrecoPayload,
    request: Request,
    # Mesmo rigor do unitário: preço é a decisão restrita do modelo
    # (CONTEXTO.md §6 regra 10). 404, nunca 403.
    usuario=Depends(auth.exigir_diretoria),
):
    itens = [
        {
            "codigo": it.codigo,
            "margem_alvo": it.margemAlvo,
            "margem_alvo_varejo": it.margemAlvoVarejo,
            "alt_pv_at_av": it.precoAtacadoAV,
            "alt_pv_var_av": it.precoVarejoAV,
        }
        for it in dados.itens
    ]
    try:
        codigos = preco.gravar_decisao_preco_lote(
            itens, usuario.login, usuario.id, _ip(request)
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except database.oracledb.IntegrityError as exc:  # type: ignore[attr-defined]
        raise HTTPException(
            status_code=422, detail=f"Valor recusado pelo banco: {exc}"
        )
    return {"gravados": len(codigos), "codigos": codigos}


# ------------------------------------------------------------------ pedido ---
# Etapa 9: carrinho -> APP_PEDIDO(_ITEM), lista, edição, máquina de estados,
# exportações (app/servicos/pedido.py). Só exige login — diferente de gravar
# preço, nenhuma operação de pedido é restrita a diretoria.

class ItemCarrinho(BaseModel):
    codigo: int
    quantidade: float
    precoUnitario: float | None = None


class CarrinhoPayload(BaseModel):
    itens: list[ItemCarrinho]

    @model_validator(mode="after")
    def _validar(self) -> "CarrinhoPayload":
        if not self.itens:
            raise ValueError("Envie ao menos um item no carrinho.")
        return self


class ItemPedidoPayload(BaseModel):
    quantidade: float
    precoUnitario: float | None = None


def _erro_pedido(exc: Exception):
    if isinstance(exc, pedido.PedidoNaoEncontrado):
        return HTTPException(status_code=404, detail="Pedido não encontrado.")
    if isinstance(exc, pedido.TransicaoInvalida):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, pedido.EdicaoNaoPermitida):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, pedido.ProdutoInvalido):
        return HTTPException(status_code=422, detail=str(exc))
    raise exc


@router.post("/pedidos", status_code=201)
def salvar_carrinho(dados: CarrinhoPayload, request: Request, usuario=Depends(auth.exigir_login)):
    itens = [
        {"codigo": it.codigo, "quantidade": it.quantidade, "preco_unitario": it.precoUnitario}
        for it in dados.itens
    ]
    try:
        pedidos = pedido.salvar_carrinho(itens, usuario.login, usuario.id, _ip(request))
    except pedido.ProdutoInvalido as exc:
        raise _erro_pedido(exc)
    return {"pedidos": [contrato.pedido(p) for p in pedidos]}


@router.get("/pedidos")
def listar_pedidos(
    usuario=Depends(auth.exigir_login),
    status: list[str] | None = Query(default=None),
    fornecedor: str | None = None,
    busca: str | None = None,
    ordenar: str = "criadoEm",
    dir: str | None = None,
    pagina: int = 1,
    porPagina: int = 50,
):
    if ordenar not in pedido.ORDENACOES_VALIDAS:
        raise HTTPException(
            status_code=422, detail=f"ordenar inválido: {ordenar!r}.")
    if dir is not None and dir not in ("asc", "desc"):
        raise HTTPException(
            status_code=422, detail=f"dir inválido: {dir!r} (use 'asc' ou 'desc').")
    porPagina = max(1, min(porPagina, MAX_POR_PAGINA))
    filtros = {"status": status, "fornecedor": fornecedor, "busca": busca}
    linhas, total = pedido.listar_pedidos(filtros, pagina, porPagina, ordenar, dir)
    return contrato.pagina_pedidos(linhas, total, pagina, porPagina)


@router.get("/pedidos/{id_pedido}")
def obter_pedido(id_pedido: int, usuario=Depends(auth.exigir_login)):
    detalhe = pedido.obter_detalhe(id_pedido)
    if detalhe is None:
        raise HTTPException(status_code=404, detail="Pedido não encontrado.")
    return contrato.pedido_detalhe(detalhe)


@router.put("/pedidos/{id_pedido}/itens/{codigo}")
def gravar_item_pedido(
    id_pedido: int, codigo: int, dados: ItemPedidoPayload, request: Request,
    usuario=Depends(auth.exigir_login),
):
    try:
        detalhe = pedido.upsert_item(
            id_pedido, codigo, dados.quantidade, dados.precoUnitario,
            usuario.login, usuario.id, _ip(request),
        )
    except (pedido.PedidoNaoEncontrado, pedido.EdicaoNaoPermitida, pedido.ProdutoInvalido) as exc:
        raise _erro_pedido(exc)
    return contrato.pedido_detalhe(detalhe)


@router.delete("/pedidos/{id_pedido}/itens/{codigo}")
def remover_item_pedido(id_pedido: int, codigo: int, request: Request, usuario=Depends(auth.exigir_login)):
    try:
        detalhe = pedido.remover_item(id_pedido, codigo, usuario.login, usuario.id, _ip(request))
    except (pedido.PedidoNaoEncontrado, pedido.EdicaoNaoPermitida) as exc:
        raise _erro_pedido(exc)
    return contrato.pedido_detalhe(detalhe)


@router.post("/pedidos/{id_pedido}/avancar")
def avancar_pedido(id_pedido: int, request: Request, usuario=Depends(auth.exigir_login)):
    try:
        detalhe = pedido.avancar_status(id_pedido, usuario.login, usuario.id, _ip(request))
    except (pedido.PedidoNaoEncontrado, pedido.TransicaoInvalida) as exc:
        raise _erro_pedido(exc)
    return contrato.pedido_detalhe(detalhe)


@router.post("/pedidos/{id_pedido}/voltar")
def voltar_pedido(id_pedido: int, request: Request, usuario=Depends(auth.exigir_login)):
    try:
        detalhe = pedido.voltar_status(id_pedido, usuario.login, usuario.id, _ip(request))
    except (pedido.PedidoNaoEncontrado, pedido.TransicaoInvalida) as exc:
        raise _erro_pedido(exc)
    return contrato.pedido_detalhe(detalhe)


@router.delete("/pedidos/{id_pedido}")
def excluir_pedido(id_pedido: int, request: Request, usuario=Depends(auth.exigir_login)):
    try:
        pedido.excluir_pedido(id_pedido, usuario.login, usuario.id, _ip(request))
    except pedido.PedidoNaoEncontrado as exc:
        raise _erro_pedido(exc)
    return {"ok": True}


@router.get("/pedidos/{id_pedido}/exportar/excel")
def exportar_pedido_excel(id_pedido: int, usuario=Depends(auth.exigir_login)):
    resultado = pedido.gerar_excel_pedido(id_pedido)
    if resultado is None:
        raise HTTPException(status_code=404, detail="Pedido não encontrado.")
    conteudo, nome = resultado
    return Response(
        content=conteudo,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nome}"'},
    )


@router.get("/pedidos/{id_pedido}/exportar/winthor")
def exportar_pedido_winthor(id_pedido: int, request: Request, usuario=Depends(auth.exigir_login)):
    try:
        conteudo, nome = pedido.exportar_winthor(id_pedido, usuario.login, usuario.id, _ip(request))
    except (pedido.PedidoNaoEncontrado, pedido.TransicaoInvalida) as exc:
        raise _erro_pedido(exc)
    return Response(
        content=conteudo,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nome}"'},
    )


# ------------------------------------------------------------ lote de preço --
# Etapa 12: o lote de preços como documento (app/servicos/lote_preco.py).
# Gravar (criar/editar/remover/avançar/excluir) exige diretoria — mesma regra
# de /produtos/preco, decidir preço é o único ponto de decisão humana do
# modelo (CONTEXTO.md §6 regra 10). Ler/exportar exige só login: baixar o
# arquivo para importação no Winthor não é decidir preço.

class ItemLotePreco(DecisaoPreco):
    """Item de um lote: mesmo corpo do `DecisaoPreco` unitário + o código do
    produto, com a exigência ADICIONAL de que ao menos um PREÇO (não só
    margem) tenha sido informado — é o preço que vira `pv_*_novo` em
    APP_LOTE_PRECO_ITEM (CHECK ck_app_lote_item_um do banco). Margem sozinha
    grava a decisão em APP_DECISAO_PRECO pelo endpoint unitário/lote de
    `/produtos/preco`, mas não produz uma linha de lote de preços."""

    codigo: int

    @model_validator(mode="after")
    def _validar_preco(self) -> "ItemLotePreco":
        if self.precoAtacadoAV is None and self.precoVarejoAV is None:
            raise ValueError(
                f"Item {self.codigo}: informe ao menos um preço (precoAtacadoAV"
                " ou precoVarejoAV) — margem sozinha não produz item de lote."
            )
        return self


class LotePrecoCriarPayload(BaseModel):
    """Corpo de POST /lotes-preco. `idLote` ausente cria um lote novo em
    Rascunho; presente, acrescenta os itens a um Rascunho existente (§4.3) —
    é assim que o front divide uma gravação de mais de
    `preco.LIMITE_LOTE_PRECO` itens em vários pedidos HTTP para o MESMO
    documento, em vez de criar um lote por pedaço."""

    itens: list[ItemLotePreco]
    observacao: str | None = None
    idLote: int | None = None

    @model_validator(mode="after")
    def _validar(self) -> "LotePrecoCriarPayload":
        if not self.itens:
            raise ValueError("Envie ao menos um item no lote.")
        if len(self.itens) > preco.LIMITE_LOTE_PRECO:
            raise ValueError(
                f"Lote com {len(self.itens)} itens excede o limite de "
                f"{preco.LIMITE_LOTE_PRECO}. Divida em requisições menores, todas"
                " para o MESMO idLote — o primeiro cria, os seguintes acrescentam."
            )
        return self


def _erro_lote(exc: Exception):
    if isinstance(exc, lote_preco.LoteNaoEncontrado):
        return HTTPException(status_code=404, detail="Lote não encontrado.")
    if isinstance(exc, lote_preco.TransicaoInvalida):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, lote_preco.RascunhoConflitante):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, lote_preco.EdicaoNaoPermitida):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, lote_preco.ProdutoInvalido):
        return HTTPException(status_code=422, detail=str(exc))
    raise exc


@router.post("/lotes-preco", status_code=201)
def criar_ou_acrescentar_lote_preco(
    dados: LotePrecoCriarPayload, request: Request, usuario=Depends(auth.exigir_diretoria),
):
    itens = [
        {
            "codigo": it.codigo,
            "margem_alvo": it.margemAlvo,
            "margem_alvo_varejo": it.margemAlvoVarejo,
            "alt_pv_at_av": it.precoAtacadoAV,
            "alt_pv_var_av": it.precoVarejoAV,
        }
        for it in dados.itens
    ]
    try:
        if dados.idLote is None:
            detalhe = lote_preco.criar_lote(itens, dados.observacao, usuario.login, usuario.id, _ip(request))
        else:
            detalhe = lote_preco.acrescentar_itens(dados.idLote, itens, usuario.login, usuario.id, _ip(request))
    except (lote_preco.LoteNaoEncontrado, lote_preco.EdicaoNaoPermitida, lote_preco.ProdutoInvalido) as exc:
        raise _erro_lote(exc)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    return contrato.lote_preco_detalhe(detalhe)


@router.get("/lotes-preco")
def listar_lotes_preco(
    usuario=Depends(auth.exigir_login),
    status: list[str] | None = Query(default=None),
    ordenar: str = "criadoEm",
    dir: str | None = None,
    pagina: int = 1,
    porPagina: int = 50,
):
    if ordenar not in lote_preco.ORDENACOES_VALIDAS:
        raise HTTPException(
            status_code=422, detail=f"ordenar inválido: {ordenar!r}.")
    if dir is not None and dir not in ("asc", "desc"):
        raise HTTPException(
            status_code=422, detail=f"dir inválido: {dir!r} (use 'asc' ou 'desc').")
    porPagina = max(1, min(porPagina, MAX_POR_PAGINA))
    filtros = {"status": status}
    linhas, total = lote_preco.listar_lotes(filtros, pagina, porPagina, ordenar, dir)
    corpo = contrato.pagina_lotes_preco(linhas, total, pagina, porPagina)
    # Carimbo de frescor da conferência (§4.5): "12 de 15 aplicados" tem a
    # idade do último `dbt run` — sem isto, a tela não pode dizer com que
    # dados a conferência foi feita.
    corpo["atualizacao"] = atualizacao.estado()
    return corpo


@router.get("/lotes-preco/{id_lote}")
def obter_lote_preco(id_lote: int, usuario=Depends(auth.exigir_login)):
    detalhe = lote_preco.obter_detalhe(id_lote)
    if detalhe is None:
        raise HTTPException(status_code=404, detail="Lote não encontrado.")
    corpo = contrato.lote_preco_detalhe(detalhe)
    corpo["atualizacao"] = atualizacao.estado()
    return corpo


@router.put("/lotes-preco/{id_lote}/itens/{codigo}")
def gravar_item_lote_preco(
    id_lote: int, codigo: int, dados: DecisaoPreco, request: Request,
    usuario=Depends(auth.exigir_diretoria),
):
    try:
        detalhe = lote_preco.upsert_item(
            id_lote, codigo, dados.margemAlvo, dados.margemAlvoVarejo,
            dados.precoAtacadoAV, dados.precoVarejoAV,
            usuario.login, usuario.id, _ip(request),
        )
    except (lote_preco.LoteNaoEncontrado, lote_preco.EdicaoNaoPermitida, lote_preco.ProdutoInvalido) as exc:
        raise _erro_lote(exc)
    return contrato.lote_preco_detalhe(detalhe)


@router.delete("/lotes-preco/{id_lote}/itens/{codigo}")
def remover_item_lote_preco(id_lote: int, codigo: int, request: Request, usuario=Depends(auth.exigir_diretoria)):
    try:
        detalhe = lote_preco.remover_item(id_lote, codigo, usuario.login, usuario.id, _ip(request))
    except (lote_preco.LoteNaoEncontrado, lote_preco.EdicaoNaoPermitida) as exc:
        raise _erro_lote(exc)
    return contrato.lote_preco_detalhe(detalhe)


@router.post("/lotes-preco/{id_lote}/avancar")
def avancar_lote_preco(id_lote: int, request: Request, usuario=Depends(auth.exigir_diretoria)):
    try:
        detalhe = lote_preco.avancar_status(id_lote, usuario.login, usuario.id, _ip(request))
    except (lote_preco.LoteNaoEncontrado, lote_preco.TransicaoInvalida) as exc:
        raise _erro_lote(exc)
    return contrato.lote_preco_detalhe(detalhe)


@router.post("/lotes-preco/{id_lote}/voltar")
def voltar_lote_preco(id_lote: int, request: Request, usuario=Depends(auth.exigir_diretoria)):
    try:
        detalhe = lote_preco.voltar_status(id_lote, usuario.login, usuario.id, _ip(request))
    except (
        lote_preco.LoteNaoEncontrado,
        lote_preco.TransicaoInvalida,
        lote_preco.RascunhoConflitante,
    ) as exc:
        raise _erro_lote(exc)
    return contrato.lote_preco_detalhe(detalhe)


@router.delete("/lotes-preco/{id_lote}")
def excluir_lote_preco(id_lote: int, request: Request, usuario=Depends(auth.exigir_diretoria)):
    try:
        lote_preco.excluir_lote(id_lote, usuario.login, usuario.id, _ip(request))
    except lote_preco.LoteNaoEncontrado as exc:
        raise _erro_lote(exc)
    return {"ok": True}


@router.get("/lotes-preco/{id_lote}/exportar/excel")
def exportar_lote_preco_excel(id_lote: int, usuario=Depends(auth.exigir_login)):
    resultado = lote_preco.gerar_excel_conferencia(id_lote)
    if resultado is None:
        raise HTTPException(status_code=404, detail="Lote não encontrado.")
    conteudo, nome = resultado
    return Response(
        content=conteudo,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nome}"'},
    )


@router.get("/lotes-preco/{id_lote}/exportar/201")
def exportar_lote_preco_201(
    id_lote: int, request: Request, canal: str, usuario=Depends(auth.exigir_login),
):
    if canal not in ("atacado", "varejo"):
        raise HTTPException(status_code=422, detail="canal deve ser 'atacado' ou 'varejo'.")
    resultado = lote_preco.gerar_xlsx_201(id_lote, canal, usuario.login, usuario.id, _ip(request))
    if resultado is None:
        raise HTTPException(status_code=404, detail="Lote não encontrado.")
    conteudo, nome, _excluidos = resultado
    return Response(
        content=conteudo,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nome}"'},
    )


# ─────────────────────────────────────────────── monitoramento e entradas ---

@router.get("/monitoramento/opcoes")
def opcoes_monitoramento(usuario=Depends(auth.exigir_login)):
    return monitoramento.opcoes_monitoramento()


@router.get("/monitoramento")
def ver_monitoramento(
    usuario=Depends(auth.exigir_login),
    de: str = Query(...), ate: str = Query(...),
    deAnterior: str = Query(...), ateAnterior: str = Query(...),
    metrica: str = "faturamento",
    departamento: str | None = None,
    comprador: str | None = None,
    secao: str | None = None,
    status: str | None = None,
    busca: str | None = None,
    porProduto: bool = False,
):
    """Total do período, comparativo com o ano anterior, e a quebra.

    Os quatro intervalos vêm da TELA, e não são calculados aqui, porque quem
    sabe o que "essa semana" significa é o seletor de período — inclusive o
    recorte parcial que faz a comparação ser honesta (ver `web/src/periodo.js`).
    O servidor recebe datas e soma; não reinterpreta calendário.
    """
    if metrica not in monitoramento.METRICAS:
        raise HTTPException(status_code=422,
                            detail=f"Métrica inválida. Use uma de: {', '.join(monitoramento.METRICAS)}.")
    filtros = {"departamento": departamento, "comprador": comprador,
               "secao": secao, "status": status, "busca": busca}
    corpo = {
        "resumo": monitoramento.resumo(filtros, de, ate, deAnterior, ateAnterior, metrica),
        "metrica": metrica,
    }
    if porProduto:
        corpo["produtos"] = monitoramento.por_produto(filtros, de, ate, deAnterior, ateAnterior, metrica)
        corpo["dimensao"] = None
    else:
        dim = monitoramento.proxima_dimensao(filtros)
        corpo["dimensao"] = dim
        corpo["grupos"] = (monitoramento.por_dimensao(filtros, de, ate, deAnterior,
                                                      ateAnterior, metrica, dim)
                           if dim else [])
    return corpo


@router.get("/entradas")
def ver_entradas(
    usuario=Depends(auth.exigir_login),
    de: str = Query(...), ate: str = Query(...),
    departamento: str | None = None,
    comprador: str | None = None,
    secao: str | None = None,
    status: str | None = None,
    busca: str | None = None,
):
    return monitoramento.entradas(
        {"departamento": departamento, "comprador": comprador,
         "secao": secao, "status": status, "busca": busca},
        de, ate,
    )
