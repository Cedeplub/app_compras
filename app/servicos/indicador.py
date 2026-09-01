"""Tela 3 — indicadores. Le COMPRAS_IND_FORNECEDOR (1 linha por fornecedor,
CONTEXTO §6 regra 7: FORNECEDOR = texto do departamento) e a evolucao mensal
de COMPRAS_VENDA_MENSAL. Somente leitura, nada gravado aqui.
"""
from __future__ import annotations

from app.core import database


def listar_fornecedores() -> list[dict]:
    return database.consultar(
        "select * from compras_ind_fornecedor order by fornecedor"
    )


def evolucao_mensal(fornecedor: str | None = None, limite_meses: int = 24) -> list[dict]:
    condicao = ""
    binds: dict = {"limite": limite_meses}
    if fornecedor:
        # DEPARTAMENTO em COMPRAS_VENDA_MENSAL e o mesmo texto de FORNECEDOR
        # em COMPRAS_PEDIDO/COMPRAS_IND_FORNECEDOR (CONTEXTO §6 regra 7).
        condicao = "where upper(departamento) = upper(:fornecedor)"
        binds["fornecedor"] = fornecedor

    return database.consultar(
        f"""
        select mes, sum(valor_liquido) as valor_liquido, sum(quantidade_liquida) as quantidade_liquida,
               sum(valor_devolucao) as valor_devolucao
          from compras_venda_mensal
          {condicao}
         group by mes
         order by mes desc
        fetch first :limite rows only
        """,
        binds,
    )
