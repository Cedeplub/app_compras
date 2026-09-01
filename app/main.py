"""FastAPI: rotas e montagem. Dashboard de compras (Etapa 6a).

So enxerga o schema COMPRAS (app.core.database e a unica porta para o
Oracle). Le COMPRAS_*, escreve so em APP_* (CONTEXTO.md §2).
"""
from __future__ import annotations

import datetime as dt
import logging

from fastapi import Depends, FastAPI, Form, Request
from fastapi.exceptions import HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app import config
from app.api import rotas as api_rotas
from app.core import auditoria, auth, database
from app.servicos import compra, exportacao, indicador, preco

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("app_compras")

app = FastAPI(title="Dashboard de Compras CEDEP")
templates = Jinja2Templates(directory=str(config.BASE_DIR / "app" / "templates"))

# CSS e JS servidos pela PROPRIA aplicacao, nunca de CDN. O dispositivo alvo e o
# celular do Diretor, dentro da rede interna e atras do Fortigate: uma dependencia
# externa aqui faria a tela abrir sem estilo nenhum no dia em que a saida fosse
# bloqueada. Por isso o htmx tambem esta vendorizado em static/js/, e nao ha
# nenhuma URL externa em template ou CSS (ha um teste disso no relatorio da 6b).
app.mount(
    "/static",
    StaticFiles(directory=str(config.BASE_DIR / "app" / "static")),
    name="static",
)

# ─────────────────────────────────────────────────────────────────────────────
# API JSON do v2 (Etapa 7). Convive com as rotas HTML da Etapa 6 em vez de
# substitui-las: enquanto as telas novas nao cobrem tudo que as antigas cobrem,
# derrubar as antigas deixaria o comprador sem ferramenta no meio do caminho.
# As duas leem o MESMO servico e a MESMA sessao - nao ha um segundo caminho de
# calculo nem um segundo login para divergir.
# ─────────────────────────────────────────────────────────────────────────────
app.include_router(api_rotas.router)


@app.on_event("startup")
def _startup() -> None:
    faltando = config.validar()
    if faltando:
        raise RuntimeError(faltando)
    database.iniciar_pool()
    auth.garantir_admin_inicial()


@app.on_event("shutdown")
def _shutdown() -> None:
    database.fechar_pool()


@app.exception_handler(HTTPException)
async def _tratar_http_exception(request: Request, exc: HTTPException):
    # A API responde SEMPRE em JSON, com o status de verdade. Redirecionar um
    # cliente JSON para a pagina de login manda 303 + HTML para quem esta
    # esperando um objeto: o fetch nao percebe que a sessao caiu, tenta ler
    # JSON de uma pagina de login e falha com um erro que nao diz nada sobre
    # sessao. O 401 explicito e o que faz o front saber redirecionar sozinho.
    if request.url.path.startswith("/api/"):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
    if exc.status_code == 401:
        if request.headers.get("HX-Request") == "true":
            resp = Response(status_code=200)
            resp.headers["HX-Redirect"] = "/login"
            return resp
        return RedirectResponse("/login", status_code=303)
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(database.ConsultaEstourouTempo)
async def _tratar_timeout(request: Request, exc: database.ConsultaEstourouTempo):
    """Sem este handler, a mensagem escrita em database.ConsultaEstourouTempo era
    codigo morto: a excecao subia ate o 500 padrao do Starlette e o usuario via
    "Internal Server Error" numa situacao que NAO e' erro do sistema - e' carga
    momentanea, e a acao certa e' tentar de novo em instantes. Dizer isso e' a
    diferenca entre o comprador esperar 10 segundos e abrir um chamado.
    503, e nao 500: o servico esta indisponivel AGORA, nao quebrado.
    """
    log.warning("consulta estourou o tempo em %s: %s", request.url.path, exc)
    if request.headers.get("HX-Request") == "true":
        return HTMLResponse(
            f'<div class="erro">{exc}</div>', status_code=503
        )
    return templates.TemplateResponse(
        request, "erro.html", {"mensagem": str(exc), "usuario": None}, status_code=503
    )


def _ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _float_ou_none(valor: str | None) -> float | None:
    if valor is None:
        return None
    valor = valor.strip().replace(",", ".")
    return float(valor) if valor else None


# ------------------------------------------------------------------- raiz ---

@app.get("/")
def raiz():
    return RedirectResponse("/compra", status_code=303)


# ---------------------------------------------------------- autenticacao ---

@app.get("/login", response_class=HTMLResponse)
def login_form(request: Request, usuario: auth.Usuario | None = Depends(auth.usuario_atual)):
    if usuario:
        return RedirectResponse("/compra", status_code=303)
    return templates.TemplateResponse(request, "login.html", {"erro": None})


@app.post("/login")
def login_submit(
    request: Request,
    login: str = Form(...),
    senha: str = Form(...),
):
    usuario = auth.autenticar(login, senha)
    if usuario is None:
        return templates.TemplateResponse(
            request, "login.html", {"erro": "Login ou senha inválidos."}, status_code=401
        )
    token = auth.abrir_sessao(usuario, _ip(request))
    auditoria.registrar_isolado(usuario.id, "LOGIN", ip=_ip(request))
    destino = "/trocar-senha" if usuario.senha_provisoria else "/compra"
    resp = RedirectResponse(destino, status_code=303)
    resp.set_cookie(
        config.COOKIE_NOME, token, httponly=True, secure=config.COOKIE_SECURE,
        samesite="lax", max_age=config.SESSAO_HORAS * 3600,
    )
    return resp


@app.post("/logout")
def logout(request: Request, usuario: auth.Usuario | None = Depends(auth.usuario_atual)):
    token = request.cookies.get(config.COOKIE_NOME)
    auth.fechar_sessao(token)
    if usuario:
        auditoria.registrar_isolado(usuario.id, "LOGOUT", ip=_ip(request))
    resp = RedirectResponse("/login", status_code=303)
    resp.delete_cookie(config.COOKIE_NOME)
    return resp


@app.get("/trocar-senha", response_class=HTMLResponse)
def trocar_senha_form(request: Request, usuario: auth.Usuario = Depends(auth.exigir_login)):
    return templates.TemplateResponse(request, "trocar_senha.html", {"erro": None})


@app.post("/trocar-senha")
def trocar_senha_submit(
    request: Request,
    senha_atual: str = Form(...),
    nova_senha: str = Form(...),
    confirmar: str = Form(...),
    usuario: auth.Usuario = Depends(auth.exigir_login),
):
    linha = database.consultar_um(
        "select senha_hash from app_usuario where id_usuario = :id", {"id": usuario.id}
    )
    if not auth.conferir_senha(senha_atual, linha["senha_hash"] if linha else None):
        return templates.TemplateResponse(
            request, "trocar_senha.html", {"erro": "Senha atual incorreta."}, status_code=400
        )
    if nova_senha != confirmar:
        return templates.TemplateResponse(
            request, "trocar_senha.html", {"erro": "Confirmação não confere."}, status_code=400
        )
    motivo = auth.validar_forca(nova_senha)
    if motivo:
        return templates.TemplateResponse(request, "trocar_senha.html", {"erro": motivo}, status_code=400)

    auth.trocar_senha(usuario.id, nova_senha)  # derruba as sessoes antigas, inclusive esta
    auditoria.registrar_isolado(usuario.id, "TROCA_SENHA", ip=_ip(request))

    novo_token = auth.abrir_sessao(usuario, _ip(request))
    resp = RedirectResponse("/compra", status_code=303)
    resp.set_cookie(
        config.COOKIE_NOME, novo_token, httponly=True, secure=config.COOKIE_SECURE,
        samesite="lax", max_age=config.SESSAO_HORAS * 3600,
    )
    return resp


# ------------------------------------------------------- tela 1: compra ---

@app.get("/compra", response_class=HTMLResponse)
def tela_compra(
    request: Request,
    tipo_alerta: str = "",
    fornecedor: str = "",
    comprador: str = "",
    classe: str = "",
    busca: str = "",
    pagina: int = 1,
    usuario: auth.Usuario = Depends(auth.exigir_login),
):
    filtros = {
        "tipo_alerta": tipo_alerta or None,
        "fornecedor": fornecedor or None,
        "comprador": comprador or None,
        "classe": classe or None,
        "busca": busca or None,
    }
    linhas, total = compra.listar_pedidos(filtros, pagina, config.ITENS_POR_PAGINA)
    total_paginas = max(1, -(-total // config.ITENS_POR_PAGINA))
    return templates.TemplateResponse(
        request, "compra_lista.html",
        {
            "usuario": usuario, "linhas": linhas, "total": total, "pagina": pagina,
            "total_paginas": total_paginas, "filtros": filtros,
            "opcoes": compra.opcoes_filtro(),
        },
    )


@app.post("/compra/{codigo}/pedido", response_class=HTMLResponse)
def gravar_pedido(
    request: Request,
    codigo: int,
    pedido: str = Form(...),
    usuario: auth.Usuario = Depends(auth.exigir_login),
):
    try:
        valor = float(pedido.strip().replace(",", "."))
    except ValueError:
        raise HTTPException(status_code=400, detail="Pedido inválido.")
    try:
        linha = compra.gravar_pedido(codigo, valor, usuario.login, usuario.id, _ip(request))
    except ValueError:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    except database.oracledb.IntegrityError:
        # Dois compradores gravando o MESMO SKU pela primeira vez ao mesmo tempo:
        # nao ha' linha para o `for update` travar, entao os dois chegam no MERGE e
        # um perde na PK. Raro, mas sem este catch virava 500 - e um 500 na hora de
        # gravar faz o comprador achar que perdeu a decisao. Refazer resolve, porque
        # aI a linha ja existe e o MERGE cai no caminho de UPDATE. O mesmo catch ja
        # existia em /preco; faltava aqui.
        raise HTTPException(
            status_code=409,
            detail="Outra pessoa gravou este produto agora mesmo. Confira o valor e grave de novo.",
        )
    return templates.TemplateResponse(request, "compra_linha.html", {"linha": linha})


# ------------------------------------------------------- tela 2: preco ---

@app.get("/preco", response_class=HTMLResponse)
def tela_preco_busca(
    request: Request, q: str = "", usuario: auth.Usuario = Depends(auth.exigir_login)
):
    resultados = preco.buscar(q) if q else []
    return templates.TemplateResponse(
        request, "preco_busca.html", {"q": q, "resultados": resultados, "usuario": usuario}
    )


@app.get("/preco/{codigo}", response_class=HTMLResponse)
def tela_preco_cenarios(
    request: Request, codigo: int, usuario: auth.Usuario = Depends(auth.exigir_login)
):
    dados = preco.obter_cenarios(codigo)
    if dados is None:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    return templates.TemplateResponse(
        request, "preco_cenarios.html", {"p": dados, "usuario": usuario, "erro": None}
    )


@app.post("/preco/{codigo}", response_class=HTMLResponse)
def gravar_preco(
    request: Request,
    codigo: int,
    margem_alvo: str = Form(""),
    margem_alvo_varejo: str = Form(""),
    alt_pv_at_av: str = Form(""),
    alt_pv_var_av: str = Form(""),
    # 404, nao 403: quem nao e diretoria nao deve nem saber que a rota existe.
    usuario: auth.Usuario = Depends(auth.exigir_diretoria),
):
    dados = preco.obter_cenarios(codigo)
    if dados is None:
        raise HTTPException(status_code=404, detail="Produto não encontrado.")
    try:
        preco.gravar_decisao_preco(
            codigo,
            _float_ou_none(margem_alvo),
            _float_ou_none(margem_alvo_varejo),
            _float_ou_none(alt_pv_at_av),
            _float_ou_none(alt_pv_var_av),
            usuario.login,
            usuario.id,
            _ip(request),
        )
    except database.oracledb.IntegrityError as exc:  # type: ignore[attr-defined]
        dados = preco.obter_cenarios(codigo)
        return templates.TemplateResponse(
            request, "preco_cenarios.html",
            {"p": dados, "usuario": usuario, "erro": f"Valor recusado pelo banco: {exc}"},
            status_code=400,
        )
    return RedirectResponse(f"/preco/{codigo}", status_code=303)


# --------------------------------------------------- tela 3: indicadores ---

@app.get("/indicadores", response_class=HTMLResponse)
def tela_indicadores(
    request: Request, fornecedor: str = "", usuario: auth.Usuario = Depends(auth.exigir_login)
):
    fornecedores = indicador.listar_fornecedores()
    mensal = indicador.evolucao_mensal(fornecedor or None)
    return templates.TemplateResponse(
        request, "indicadores.html",
        {"fornecedores": fornecedores, "mensal": mensal, "fornecedor": fornecedor, "usuario": usuario},
    )


# ------------------------------------------------ tela 4: pedidos (Etapa 6) ---
# Exportar em Excel a lista de pedidos por fornecedor, pronta para o comprador
# enviar. Exige so login: quem compra e quem envia, o pedido ja foi decidido
# na tela 1 - nao exige EH_DIRETORIA (essa exigencia e so para GRAVAR preco).

def _data_ou_hoje(valor: str) -> dt.date:
    return dt.date.fromisoformat(valor) if valor else dt.date.today()


@app.get("/pedidos", response_class=HTMLResponse)
def tela_pedidos(
    request: Request,
    data_de: str = "",
    data_ate: str = "",
    usuario: auth.Usuario = Depends(auth.exigir_login),
):
    de = _data_ou_hoje(data_de)
    ate = _data_ou_hoje(data_ate)
    fornecedores = exportacao.fornecedores_com_pedido(de, ate)
    return templates.TemplateResponse(
        request, "pedidos.html",
        {"usuario": usuario, "fornecedores": fornecedores, "data_de": de, "data_ate": ate},
    )


@app.get("/pedidos/exportar")
def exportar_pedido(
    request: Request,
    fornecedor: str,
    data_de: str = "",
    data_ate: str = "",
    usuario: auth.Usuario = Depends(auth.exigir_login),
):
    de = _data_ou_hoje(data_de)
    ate = _data_ou_hoje(data_ate)
    itens = exportacao.itens_do_fornecedor(fornecedor, de, ate)
    if not itens:
        raise HTTPException(status_code=404, detail="Nenhum pedido encontrado para esse fornecedor no período.")

    compradores = sorted({i["comprador"] for i in itens if i.get("comprador")})
    total_unidades = sum((i["pedido"] or 0) * (i["fator_exibicao"] or 1) for i in itens)
    valor_total = sum(
        (i["pedido"] or 0) * (i["fator_exibicao"] or 1) * (i["vl_ent_unit"] or 0) for i in itens
    )
    cabecalho = {
        "comprador": ", ".join(compradores),
        "data_de": de, "data_ate": ate,
        "gerado_em": dt.datetime.now(), "gerado_por": usuario.nome,
        "qtd_sku": len(itens), "total_unidades": total_unidades, "valor_total": valor_total,
    }
    conteudo = exportacao.gerar_xlsx(fornecedor, itens, cabecalho)

    # Dado saindo da empresa - auditoria com ID_USUARIO preenchido, nunca None
    # (o mesmo cuidado de compra.py/preco.py: e o que responde "o que fulano
    # fez" via IX_APP_AUDITORIA_USUARIO).
    auditoria.registrar_isolado(
        usuario.id, "EXPORTAR_PEDIDO", "APP_DECISAO_PEDIDO", fornecedor,
        {"qtd_itens": len(itens), "data_de": str(de), "data_ate": str(ate)},
        _ip(request),
    )

    nome = exportacao.nome_arquivo(fornecedor)
    return Response(
        content=conteudo,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nome}"'},
    )
