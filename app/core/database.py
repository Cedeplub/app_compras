"""A UNICA porta para o Oracle. Nenhum outro arquivo do app abre conexao.

Schema COMPRAS, e so ele: o app nunca consulta o CEDEP, por nenhum caminho
(CONTEXTO.md §2). Se um dado que a tela precisa nao existe em COMPRAS_*, a
correcao e um model dbt novo — nao um SELECT direto daqui para o CEDEP.

Modo thick e obrigatorio neste servidor (verificador de senha legado 0x939).
ORA_PYTHON_DRIVER_TYPE nao vale fora do dbt-oracle: e preciso chamar
`oracledb.init_oracle_client` explicitamente, uma vez, antes da primeira
conexao (CONTEXTO.md §3). Sem isso, DPY-3015.
"""
from __future__ import annotations

import contextlib
import logging
import threading

import oracledb

from app import config

log = logging.getLogger("app_compras.database")

_pool: oracledb.ConnectionPool | None = None
_lock = threading.Lock()
_thick_iniciado = False
_semaforo = threading.Semaphore(config.MAX_EXECUCOES_SIMULTANEAS)


def _iniciar_thick() -> None:
    global _thick_iniciado
    if _thick_iniciado:
        return
    try:
        oracledb.init_oracle_client(lib_dir=config.ORA_CLIENT_DIR or None)
    except Exception as exc:  # noqa: BLE001
        # DPI-1072 = ja inicializado neste processo (ex.: reload do uvicorn) - ok.
        if "DPI-1072" not in str(exc) and "already" not in str(exc).lower():
            raise RuntimeError(
                "Nao foi possivel carregar o Oracle Client (modo thick). "
                f"Confira ORA_CLIENT_DIR no .env. Detalhe: {exc}"
            ) from exc
    _thick_iniciado = True


def iniciar_pool() -> oracledb.ConnectionPool:
    global _pool
    with _lock:
        if _pool is not None:
            return _pool
        faltando = config.validar()
        if faltando:
            raise RuntimeError(faltando)
        _iniciar_thick()
        _pool = oracledb.create_pool(
            user=config.ORA_USER,
            password=config.ORA_PASSWORD,
            dsn=config.ORA_DSN,
            min=1,
            max=config.ORA_POOL_MAX,
            increment=1,
        )
        log.info("pool Oracle aberto (max=%d, schema=%s)", config.ORA_POOL_MAX, config.ORA_SCHEMA)
        return _pool


def fechar_pool() -> None:
    global _pool
    with _lock:
        if _pool is not None:
            _pool.close(force=True)
            _pool = None


class ConsultaEstourouTempo(RuntimeError):
    """Consulta/gravacao passou do teto de tempo (config.TIMEOUT_SEGUNDOS)."""


class _Conexao:
    """Context manager que limita execucoes simultaneas e aplica timeout.

    Adquire do pool, aponta a sessao para CURRENT_SCHEMA=COMPRAS (defensivo -
    o usuario ja conecta como COMPRAS, mas deixa explicito qual e a fronteira)
    e devolve ao pool ao sair (nunca fecha a conexao de fato).
    """

    def __init__(self, timeout: int | None = None):
        self.timeout = timeout if timeout is not None else config.TIMEOUT_SEGUNDOS
        self._adquiriu_semaforo = False

    def __enter__(self):
        if not _semaforo.acquire(timeout=self.timeout):
            raise ConsultaEstourouTempo(
                "Todas as conexoes do dashboard estao ocupadas. Tente novamente em instantes."
            )
        self._adquiriu_semaforo = True
        self.conn = iniciar_pool().acquire()
        if self.timeout:
            self.conn.call_timeout = self.timeout * 1000
        cur = self.conn.cursor()
        cur.execute(f"ALTER SESSION SET CURRENT_SCHEMA = {config.ORA_SCHEMA}")
        cur.close()
        return self.conn

    def __exit__(self, exc_type, exc, tb):
        try:
            self.conn.call_timeout = 0
            self.conn.close()  # devolve ao pool
        finally:
            if self._adquiriu_semaforo:
                _semaforo.release()
        return False


def conexao(timeout: int | None = None) -> _Conexao:
    return _Conexao(timeout)


def _linha_para_dict(nomes: list[str], linha) -> dict:
    return dict(zip(nomes, linha))


def consultar(sql: str, binds: dict | None = None, timeout: int | None = None) -> list[dict]:
    """Roda um SELECT e devolve lista de dicts (chave em minusculas)."""
    try:
        with conexao(timeout) as conn:
            cur = conn.cursor()
            cur.arraysize = 2000
            cur.execute(sql, binds or {})
            nomes = [d[0].lower() for d in cur.description]
            linhas = cur.fetchall()
            cur.close()
    except oracledb.Error as exc:
        if "DPY-4011" in str(exc) or "DPY-3015" in str(exc):
            raise
        log.warning("consulta falhou: %s", exc)
        raise
    return [_linha_para_dict(nomes, linha) for linha in linhas]


def consultar_um(sql: str, binds: dict | None = None, timeout: int | None = None) -> dict | None:
    linhas = consultar(sql, binds, timeout)
    return linhas[0] if linhas else None


@contextlib.contextmanager
def transacao(timeout: int | None = None):
    """Uma conexao com commit no sucesso e rollback na excecao.

    Usada quando mais de um INSERT/UPDATE precisa acontecer atomicamente -
    ex.: gravar APP_DECISAO_PRECO + APP_DECISAO_PRECO_HIST + APP_AUDITORIA na
    mesma transacao (regra 2 da Etapa 6a: ou tudo, ou nada).
    """
    with conexao(timeout) as conn:
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise


def testar() -> dict:
    """Diagnostico simples (ex.: para uma rota de status, se existir)."""
    try:
        with conexao() as conn:
            cur = conn.cursor()
            cur.execute("SELECT banner FROM v$version WHERE ROWNUM = 1")
            banner = cur.fetchone()[0]
            cur.close()
        return {
            "ok": True,
            "servidor": banner,
            "client": ".".join(str(p) for p in oracledb.clientversion()),
            "schema": config.ORA_SCHEMA,
        }
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "erro": str(exc)}
