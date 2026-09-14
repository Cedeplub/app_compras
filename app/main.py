"""FastAPI: montagem da API. Dashboard de compras (v2 — Etapa 14).

So enxerga o schema COMPRAS (app.core.database e a unica porta para o
Oracle). Le COMPRAS_*, escreve so em APP_* (CONTEXTO.md §2).

O v1 (Jinja2 + HTMX) nao existe mais neste repositorio: a unica tela que
escrevia em APP_DECISAO_PEDIDO era ele, e essa tabela foi extinta na Etapa 14
(historico/PROMPT_ETAPA_14_MIGRACAO_REPOSITORIO.md §5.3, §7.2). O front e o
`web/` em React — Vite na porta 5173 em desenvolvimento, build estatico
servido pelo nginx em producao (mesmo prompt, §8.3). Este modulo so serve
JSON, em `/api`.
"""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException
from fastapi.responses import JSONResponse, RedirectResponse

from app import config
from app.api import rotas as api_rotas
from app.core import auth, database
from app.servicos import lote_preco

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("app_compras")

app = FastAPI(title="Dashboard de Compras CEDEP")

# ─────────────────────────────────────────────────────────────────────────────
# API JSON do v2. Nao ha mais rota HTML nem StaticFiles montado aqui: em
# producao o nginx serve app/static/v2 direto do disco e proxia so /api/ para
# este processo; em desenvolvimento quem serve o front e' o Vite, na 5173. O
# uvicorn desta porta (8020) nunca precisa entregar HTML nem asset estatico.
# ─────────────────────────────────────────────────────────────────────────────
app.include_router(api_rotas.router)


@app.on_event("startup")
def _startup() -> None:
    faltando = config.validar()
    if faltando:
        raise RuntimeError(faltando)
    database.iniciar_pool()
    auth.garantir_admin_inicial()
    # Aquece o cache de `lote_preco._nome_indice_unico_rascunho` (revisor,
    # 3ª passada, item 1) AQUI — fora de qualquer transação, com o servidor
    # ainda servindo sozinho — para que, quando o primeiro `except` de
    # `_transicionar` acontecer sob concorrência real, a consulta ao
    # dicionário de dados já esteja resolvida e cacheada, em vez de disputar
    # o semáforo de conexões com as transações já abertas. Falha aqui (ex.:
    # índice ainda não existe, ou ambíguo) não impede o app de subir — o
    # tratamento normal (sem cache) continua valendo, só sem o aquecimento.
    try:
        lote_preco._nome_indice_unico_rascunho()
    except Exception as exc:  # noqa: BLE001
        log.warning("nao foi possivel aquecer cache do indice de rascunho: %s", exc)


@app.on_event("shutdown")
def _shutdown() -> None:
    database.fechar_pool()


@app.exception_handler(HTTPException)
async def _tratar_http_exception(request: Request, exc: HTTPException):
    # A API responde SEMPRE em JSON, com o status de verdade. Redirecionar um
    # cliente JSON para a pagina de login manda 303 + HTML para quem esta
    # esperando um objeto: o fetch nao percebe que a sessao caiu, tenta ler
    # JSON de uma pagina de login e falha com um erro que nao diz nada sobre
    # sessao. O 401 explicito e' o que faz o front (React) saber redirecionar
    # sozinho, no cliente.
    if request.url.path.startswith("/api/"):
        return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})
    # Fora de /api (praticamente so alguem acessando a porta 8020 direto, sem
    # passar pelo Vite ou pelo nginx): manda para /login, rota que o React
    # Router resolve no cliente quando o SPA carrega.
    if exc.status_code == 401:
        return RedirectResponse("/login", status_code=303)
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
    return JSONResponse(status_code=503, content={"detail": str(exc)})


# ------------------------------------------------------------------- raiz ---

@app.get("/")
def raiz():
    # A 8020 nao serve mais tela nenhuma (v1 morreu). Em producao o nginx
    # nunca encaminha "/" para ca — so /api/* chega neste processo (§8.3 do
    # prompt da Etapa 14). Em desenvolvimento, quem responde por "/" pro
    # usuario e' o Vite, na 5173; esta rota so e' vista por quem aponta o
    # navegador direto pra 8020 (o que o teste.bat faz ao abrir o navegador
    # sozinho). Por isso a resposta e' so um aviso minimo, em JSON — servir o
    # index.html de app/static/v2 seria devolver um build que pode estar
    # desatualizado (§4.2 do mesmo prompt), e redirecionar para a 5173
    # chumbaria uma porta de desenvolvimento dentro do processo de producao.
    return {
        "servico": "app_compras",
        "info": "API do dashboard de Compras. A tela roda em outro processo "
                "(Vite em :5173 no desenvolvimento; nginx em producao).",
        "docs": "/docs",
    }
