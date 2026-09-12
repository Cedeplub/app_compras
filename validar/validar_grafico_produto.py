"""Valida o gráfico do produto (Etapa 13, §2 / §8.4 item 1 do
`v2/PROMPT_ETAPA_13_NAVEGACAO_E_TABELAS.md`): a fonte trocou de
`VD_MES_ATUAL`/`VD_M_1..3` (`COMPRAS_PEDIDO`) para agregação de
`COMPRAS_MONITORAMENTO` por mês.

NAO CONSERTA NADA. Mede e reporta. Só leitura — nenhuma gravação, nenhum
usuário criado, nenhuma limpeza necessária (ao contrário de
`validar_lote_preco.py`/`validar_ordenacao_paginada.py`, que gravam).

A armadilha (CONTEXTO.md regra 6, medida no banco): `COMPRAS_MONITORAMENTO`
está em unidade REAL; `VD_M_1`/`VD_M_2` (COMPRAS_PEDIDO) estão em unidade de
EXIBIÇÃO (caixa, quando o fornecedor é MASTER). Sem dividir por
FATOR_EXIBICAO, a quantidade fica 12x/24x maior em 324 SKUs ativos (230 de
8.841 no total, medido no mês fechado anterior).

AUTOTESTE (a lição do CONTEXTO.md/REGRAS.md: validador que nunca reprovou não
prova nada). Este script primeiro roda a comparação SEM dividir por
FATOR_EXIBICAO — o comportamento antigo, e o defeito mais fácil de
reintroduzir por acidente numa próxima etapa — e prova que ela ACUSA as 230
divergências com a maior diferença de 45.655,96 unidades. Só depois roda a
comparação real, COM a divisão, e prova que ela passa.

Uso:
    python validar/validar_grafico_produto.py
"""
from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from app.api import contrato  # noqa: E402
from app.core import database  # noqa: E402
from app.servicos import produto  # noqa: E402

TOLERANCIA = 0.01

# Referências medidas em 11/09/2026 (v2/PROMPT_ETAPA_13…md §2.2) — usadas só
# para o spot-check via código REAL (produto.obter + contrato.produto), não
# para a validação em massa (essa cobre os 8.841 SKUs, sem lista fixa).
SKUS_REFERENCIA = {
    7305: {"fator": 24, "vd_m_1": 1985.0417},
    7279: {"fator": 24, "vd_m_1": 1829.8333},
    3827: {"fator": 12, "vd_m_1": 1596.1667},
    6771: {"fator": 12, "vd_m_1": 1240.0833},
    7066: {"fator": 1,  "vd_m_1": 2534},
}


class Reporter:
    def __init__(self):
        self.itens: list[tuple[str, bool, str]] = []

    def registrar(self, nome: str, ok: bool, detalhe: str = "") -> None:
        self.itens.append((nome, ok, detalhe))
        marca = "PROVADO" if ok else "FALHOU "
        print(f"[{marca}] {nome}")
        if detalhe:
            for linha in detalhe.splitlines():
                print(f"          {linha}")

    def nao_testado(self, nome: str, motivo: str) -> None:
        self.itens.append((nome, None, motivo))
        print(f"[NAO TESTADO] {nome}\n          motivo: {motivo}")

    def resumo(self) -> int:
        provados = [n for n, ok, _ in self.itens if ok is True]
        falhas = [n for n, ok, _ in self.itens if ok is False]
        pendentes = [n for n, ok, _ in self.itens if ok is None]
        print("\n" + "=" * 78)
        print(f"{len(provados)} PROVADO(S), {len(falhas)} FALHOU(RAM), {len(pendentes)} NAO TESTADO(S)")
        if falhas:
            print("FALHARAM: " + "; ".join(falhas))
        if pendentes:
            print("NAO TESTADOS: " + "; ".join(pendentes))
        return 1 if falhas else 0


# ─────────────────────────────────────────────────────── bulk, 8.841 SKUs ──
# Uma consulta só para todo o catálogo: soma QUANTIDADE_LIQUIDA e
# VALOR_LIQUIDO de COMPRAS_MONITORAMENTO para os meses M-1 e M-2 (mesmo
# recorte que `produto._historico_monitoramento` usa: MES_REFERENCIA vem do
# DADO, via COMPRAS_PARAMETRO, nunca de sysdate).
_SQL_BULK = """
    select p.codigo, p.fator_exibicao, p.vd_m_1, p.vd_m_2,
           nvl(sum(case when m.dia >= add_months(trunc(par.mes_referencia,'MM'),-1)
                         and m.dia <  trunc(par.mes_referencia,'MM')
                        then m.quantidade_liquida end), 0) as mon_m1_qtd,
           nvl(sum(case when m.dia >= add_months(trunc(par.mes_referencia,'MM'),-2)
                         and m.dia <  add_months(trunc(par.mes_referencia,'MM'),-1)
                        then m.quantidade_liquida end), 0) as mon_m2_qtd,
           nvl(sum(case when m.dia >= add_months(trunc(par.mes_referencia,'MM'),-1)
                         and m.dia <  trunc(par.mes_referencia,'MM')
                        then m.valor_liquido end), 0) as mon_m1_valor
      from compras_pedido p
      cross join compras_parametro par
      left join compras_monitoramento m
        on m.codigo_produto = p.codigo
       and m.dia >= add_months(trunc(par.mes_referencia,'MM'), -2)
       and m.dia <  trunc(par.mes_referencia,'MM')
     group by p.codigo, p.fator_exibicao, p.vd_m_1, p.vd_m_2
"""


def _linhas_bulk() -> list[dict]:
    return database.consultar(_SQL_BULK)


def cenario_autoteste_sem_dividir(rep: Reporter, linhas: list[dict]) -> None:
    """Reproduz o DEFEITO INJETADO (comportamento anterior à Etapa 13):
    compara o monitoramento cru, SEM dividir por FATOR_EXIBICAO, contra
    VD_M_1. Números de referência (medidos em 11/09/2026): 230 divergentes
    de 8.841, maior diferença 45.655,96 unidades, monitoramento sempre MAIOR
    (nunca sucessão)."""
    divergentes = []
    for l in linhas:
        vd = float(l["vd_m_1"]) if l["vd_m_1"] is not None else 0.0
        mon = float(l["mon_m1_qtd"])
        diff = mon - vd
        if abs(diff) > TOLERANCIA:
            divergentes.append((int(l["codigo"]), vd, mon, diff))

    maior = max(divergentes, key=lambda t: abs(t[3])) if divergentes else None
    todos_maior = all(d[3] > 0 for d in divergentes)  # monitoramento sempre maior
    rep.registrar(
        f"AUTOTESTE — sem dividir por FATOR_EXIBICAO: {len(divergentes)} divergência(s) "
        "(esperado 230), monitoramento sempre MAIOR que VD_M_1",
        len(divergentes) == 230 and todos_maior and maior is not None and abs(abs(maior[3]) - 45655.96) < 1.0,
        f"total divergentes={len(divergentes)}; maior diferença={maior[3] if maior else None} "
        f"(SKU {maior[0] if maior else None}); todos com monitoramento maior={todos_maior}",
    )
    if divergentes:
        exemplos = sorted(divergentes, key=lambda t: -abs(t[3]))[:5]
        print("          maiores divergências (sem dividir):")
        for cod, vd, mon, diff in exemplos:
            print(f"            SKU {cod}: VD_M_1={vd:.4f}  monitoramento cru={mon:.2f}  diff={diff:.2f}")


def cenario_validacao_real(rep: Reporter, linhas: list[dict]) -> None:
    """A validação de verdade: quantidade = soma(QUANTIDADE_LIQUIDA)/FATOR_EXIBICAO,
    para TODOS os 8.841 SKUs, contra VD_M_1 e VD_M_2, tolerância 0,01."""
    divergentes_m1: list[tuple[int, float, float, float]] = []
    divergentes_m2: list[tuple[int, float, float, float]] = []
    for l in linhas:
        fator = float(l["fator_exibicao"]) if l["fator_exibicao"] else 1.0
        if fator == 0:
            fator = 1.0

        vd1 = float(l["vd_m_1"]) if l["vd_m_1"] is not None else 0.0
        mon1 = float(l["mon_m1_qtd"]) / fator
        if abs(mon1 - vd1) > TOLERANCIA:
            divergentes_m1.append((int(l["codigo"]), vd1, mon1, mon1 - vd1))

        vd2 = float(l["vd_m_2"]) if l["vd_m_2"] is not None else 0.0
        mon2 = float(l["mon_m2_qtd"]) / fator
        if abs(mon2 - vd2) > TOLERANCIA:
            divergentes_m2.append((int(l["codigo"]), vd2, mon2, mon2 - vd2))

    rep.registrar(
        f"quantidade do gráfico (M-1) = soma(QUANTIDADE_LIQUIDA)/FATOR_EXIBICAO bate com VD_M_1, "
        f"tolerância {TOLERANCIA}, nos {len(linhas)} SKUs",
        not divergentes_m1,
        f"{len(divergentes_m1)} divergência(s)"
        + ("" if not divergentes_m1 else ": " + str(divergentes_m1[:5])),
    )
    rep.registrar(
        f"quantidade do gráfico (M-2) = soma(QUANTIDADE_LIQUIDA)/FATOR_EXIBICAO bate com VD_M_2, "
        f"tolerância {TOLERANCIA}, nos {len(linhas)} SKUs",
        not divergentes_m2,
        f"{len(divergentes_m2)} divergência(s)"
        + ("" if not divergentes_m2 else ": " + str(divergentes_m2[:5])),
    )


def cenario_spot_check_codigo_real(rep: Reporter) -> None:
    """Chama o código de PRODUÇÃO de verdade (`produto.obter` +
    `contrato.produto`) para os 5 SKUs de referência do prompt — não uma
    reimplementação da fórmula em SQL solto, mas a função que a rota
    `/api/produtos/{codigo}` de fato chama."""
    falhas = []
    for codigo, ref in SKUS_REFERENCIA.items():
        linha = produto.obter(codigo)
        if linha is None:
            falhas.append(f"SKU {codigo}: não encontrado")
            continue
        corpo = contrato.produto(linha)
        qtd_m1 = corpo["vendaHistorico"]["quantidade"][1]  # [Atual, M-1, M-2, M-3]
        if qtd_m1 is None or abs(qtd_m1 - ref["vd_m_1"]) > TOLERANCIA:
            falhas.append(
                f"SKU {codigo}: vendaHistorico.quantidade[M-1]={qtd_m1}, esperado {ref['vd_m_1']}"
            )
    rep.registrar(
        "código de PRODUÇÃO (produto.obter + contrato.produto) devolve vendaHistorico.quantidade[M-1] "
        f"correto para os {len(SKUS_REFERENCIA)} SKUs de referência (fatores 24/24/12/12/1)",
        not falhas,
        "\n".join(falhas) or str({c: r["vd_m_1"] for c, r in SKUS_REFERENCIA.items()}),
    )


def cenario_faturamento_nao_dividido(rep: Reporter) -> None:
    """Prova que faturamento (R$) NÃO é dividido por FATOR_EXIBICAO — usa o
    SKU 7305 (fator 24) via o código de PRODUÇÃO, e compara com a soma CRUA
    de VALOR_LIQUIDO do monitoramento (mesma consulta que `_historico_
    monitoramento` roda, sem qualquer divisão)."""
    codigo = 7305
    linha_bruta = database.consultar_um(
        """
        select nvl(sum(case when m.dia >= add_months(trunc(par.mes_referencia,'MM'),-1)
                              and m.dia <  trunc(par.mes_referencia,'MM')
                             then m.valor_liquido end), 0) as valor_m1_cru
          from compras_parametro par
          left join compras_monitoramento m
            on m.codigo_produto = :codigo
           and m.dia >= add_months(trunc(par.mes_referencia,'MM'), -1)
           and m.dia <  trunc(par.mes_referencia,'MM')
        """,
        {"codigo": codigo},
    )
    valor_cru = float(linha_bruta["valor_m1_cru"])

    linha = produto.obter(codigo)
    corpo = contrato.produto(linha)
    faturamento_m1 = corpo["vendaHistorico"]["faturamento"][1]
    fator = corpo["fatorExibicao"]

    ok = (
        fator == 24
        and faturamento_m1 is not None
        and abs(faturamento_m1 - valor_cru) < TOLERANCIA
        and abs(faturamento_m1 - valor_cru / fator) > TOLERANCIA  # se tivesse dividido, seria bem diferente
    )
    rep.registrar(
        f"SKU {codigo} (fator {fator}): faturamento do gráfico (M-1) bate com a soma CRUA de "
        "VALOR_LIQUIDO do monitoramento — NÃO foi dividido por FATOR_EXIBICAO",
        ok,
        f"faturamento_grafico={faturamento_m1}, soma_crua_monitoramento={valor_cru}, "
        f"(soma_crua/fator seria {valor_cru / fator if fator else None} — bem diferente do que saiu)",
    )


def cenario_barra_ano_anterior(rep: Reporter) -> None:
    """§2.3: `venda_ano_passado` decide se a barra do ano anterior EXISTE.
    Zero (vivo, vendeu zero) desenha barra rente ao chão; nulo (sem
    evidência) não desenha barra nenhuma. Usa um SKU real de cada caso via
    o código de PRODUÇÃO (`contrato._ano_anterior`)."""
    cod_zero = database.consultar_um(
        "select codigo from compras_produto_contexto where venda_ano_passado = 0 and rownum = 1"
    )
    cod_nulo = database.consultar_um(
        "select codigo from compras_produto_contexto where venda_ano_passado is null and rownum = 1"
    )
    falhas = []
    if cod_zero:
        linha = produto.obter(int(cod_zero["codigo"]))
        corpo = contrato.produto(linha) if linha else None
        if not corpo or corpo["anoAnterior"]["quantidade"] != 0:
            falhas.append(
                f"SKU {cod_zero['codigo']} (venda_ano_passado=0): anoAnterior.quantidade="
                f"{corpo['anoAnterior']['quantidade'] if corpo else 'N/A'}, esperado 0 (barra rente ao chão)"
            )
    else:
        falhas.append("nenhum SKU com venda_ano_passado=0 encontrado")

    if cod_nulo:
        linha = produto.obter(int(cod_nulo["codigo"]))
        corpo = contrato.produto(linha) if linha else None
        if not corpo or corpo["anoAnterior"]["quantidade"] is not None:
            falhas.append(
                f"SKU {cod_nulo['codigo']} (venda_ano_passado=null): anoAnterior.quantidade="
                f"{corpo['anoAnterior']['quantidade'] if corpo else 'N/A'}, esperado None (sem barra)"
            )
    else:
        falhas.append("nenhum SKU com venda_ano_passado nulo encontrado")

    rep.registrar(
        f"barra do ano anterior: SKU {cod_zero['codigo'] if cod_zero else '?'} (venda=0) desenha "
        f"rente ao chão; SKU {cod_nulo['codigo'] if cod_nulo else '?'} (venda=null) não desenha barra",
        not falhas,
        "\n".join(falhas) or "ambos os casos corretos",
    )


def main() -> int:
    rep = Reporter()
    print("Consultando COMPRAS_MONITORAMENTO agregado para os 8.841 SKUs (uma consulta)…")
    linhas = _linhas_bulk()
    rep.registrar(
        f"consulta bulk devolveu {len(linhas)} SKU(s) (esperado 8.841, os mesmos de "
        "COMPRAS_PEDIDO — regra 9: todo SKU que apareceu em qualquer mês)",
        len(linhas) >= 8800,  # tolera pequena variação de carga entre execuções
        f"{len(linhas)} linhas",
    )
    print()

    cenario_autoteste_sem_dividir(rep, linhas)
    print()
    cenario_validacao_real(rep, linhas)
    print()
    cenario_spot_check_codigo_real(rep)
    print()
    cenario_faturamento_nao_dividido(rep)
    print()
    cenario_barra_ano_anterior(rep)

    return rep.resumo()


if __name__ == "__main__":
    sys.exit(main())
