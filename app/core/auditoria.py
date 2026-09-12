"""Registro de acoes em APP_AUDITORIA.

Cobre autenticacao (LOGIN, LOGOUT, TROCA_SENHA) e gravacao de negocio
(GRAVAR_DECISAO_PRECO, GRAVAR_DECISAO_PEDIDO) - CONTEXTO §4 / sql/02_tabelas_app.sql.
"""
from __future__ import annotations

import datetime as dt
import json
import logging

import oracledb

from app.core import database

log = logging.getLogger("app_compras.auditoria")


def registrar(
    conn,
    id_usuario: int | None,
    acao: str,
    tabela_referencia: str | None = None,
    chave_referencia: str | None = None,
    detalhe: dict | None = None,
    ip: str | None = None,
) -> None:
    """Grava uma linha de auditoria usando a CONEXAO/transacao ja aberta pelo
    chamador, quando a acao faz parte de uma gravacao de negocio (preco,
    pedido) - assim ela entra na MESMA transacao (regra 2: ou tudo, ou nada).
    """
    cur = conn.cursor()
    detalhe_clob = cur.var(oracledb.DB_TYPE_CLOB)
    detalhe_clob.setvalue(0, json.dumps(detalhe, ensure_ascii=False, default=str) if detalhe else "")
    cur.execute(
        """
        insert into app_auditoria
            (id_usuario, acao, tabela_referencia, chave_referencia, detalhe, ip)
        values
            (:id_usuario, :acao, :tabela_referencia, :chave_referencia, :detalhe, :ip)
        """,
        {
            "id_usuario": id_usuario,
            "acao": acao,
            "tabela_referencia": tabela_referencia,
            "chave_referencia": chave_referencia,
            "detalhe": detalhe_clob,
            "ip": ip,
        },
    )
    cur.close()


def registrar_isolado(
    id_usuario: int | None,
    acao: str,
    tabela_referencia: str | None = None,
    chave_referencia: str | None = None,
    detalhe: dict | None = None,
    ip: str | None = None,
) -> None:
    """Para acoes que nao fazem parte de uma transacao de negocio (LOGIN,
    LOGOUT). Nunca derruba a requisicao: falha de auditoria vira log.
    """
    try:
        with database.transacao() as conn:
            registrar(conn, id_usuario, acao, tabela_referencia, chave_referencia, detalhe, ip)
    except Exception as exc:  # noqa: BLE001
        log.warning("nao foi possivel gravar a auditoria: %s", exc)
