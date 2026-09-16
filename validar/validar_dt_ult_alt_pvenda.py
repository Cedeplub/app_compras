"""Etapa 15, ponto 2 (CONTEXTO §... / prompts/PROMPT_ETAPA_15_ESTOQUE_APLICADO_E_ICONE.md §4.5,
§8.5, §10 itens 4 e 5).

Valida a fonte da data nova de COMPRAS_PRODUTO_CONTEXTO:

    COMPRAS_PRODUTO_CONTEXTO.DT_ULT_ALT_PV_ATACADO  x  CEDEP.PCTABPR.DTULTALTPVENDA (NUMREGIAO=2)
    COMPRAS_PRODUTO_CONTEXTO.DT_ULT_ALT_PV_VAREJO   x  CEDEP.PCTABPR.DTULTALTPVENDA (NUMREGIAO=1)

para os SKUs de COMPRAS_PEDIDO (8.841 na medicao de 16/09/2026 - reconte no dia: PCTABPR
muda a cada preco digitado na rotina 201).

ACEITE (execucao limpa, sem --injetar-defeito-regiao): zero divergencia nas duas colunas e
650 nulos dos dois lados (idem, reconte no dia).

⚠ Divergencias causadas por SKU alterado no WinThor DEPOIS do build do dbt sao defasagem
esperada, nao defeito de codigo - reporte-as separadamente (SKU + horario de alteracao),
nunca some no total de "divergencia de codigo". O agente de dbt ja mediu 7 SKUs assim em
16/09 (64, 65, 1849, 8128, 8161, 8581, 8582 - alterados as 10:48, durante o build iniciado
as 10:46): se o mesmo SKU reaparecer aqui, é o mesmo fenomeno, nao uma regressao.

EXECUCAO COM DEFEITO INJETADO (--injetar-defeito-regiao):

    Nao alteramos o banco (validar/ so LE - CONTEXTO §2). Em vez disso, simulamos o defeito
    dentro da propria consulta: comparamos o que a coluna de atacado CONTERIA se
    int_cadastro_estoque tivesse resolvido a regiao errada (CEDEP.PCTABPR com NUMREGIAO=1,
    a mesma fonte usada por engano para "varejo") contra a fonte CORRETA de atacado
    (NUMREGIAO=2 - o que COMPRAS_PRODUTO_CONTEXTO de fato contem hoje, confirmado pela
    execucao limpa). Isso prova que o validador enxerga uma REGIAO errada, nao so ausencia
    de dado.

    Duas granularidades sao relatadas, de proposito (§2.2 do prompt da etapa):
      - precisao completa (datetime com hora): mais pares divergem, porque duas alteracoes
        no mesmo dia em regioes diferentes tem horas diferentes;
      - truncado por dia (trunc): e' o numero de referencia do §2.2 - **79** SKUs, dos 8.191
        que tem data nas duas regioes hoje.

Uso:
    python validar/validar_dt_ult_alt_pvenda.py
    python validar/validar_dt_ult_alt_pvenda.py --injetar-defeito-regiao

Conexao: mesmo molde de validar/validar_pedido.py (_ler_credencial_compras / conectar,
thick obrigatorio via oracledb.init_oracle_client - CONTEXTO §3). validar/ e' a excecao
nominal que le os dois schemas (COMPRAS e CEDEP) - nunca escreve em nenhum dos dois.
"""
from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from validar_pedido import (  # noqa: E402  (molde de conexao - nao duplicar credencial)
    ORACLE_CLIENT_LIB_DIR,
    PROFILES_PATH,
    conectar,
)

SQL = """
select
    cp.codigo                                                                as codigo,
    ctx.dt_ult_alt_pv_atacado                                                as ctx_atacado,
    ctx.dt_ult_alt_pv_varejo                                                 as ctx_varejo,
    (select pt.dtultaltpvenda from cedep.pctabpr pt
      where pt.codprod = cp.codigo and pt.numregiao = 2)                     as cedep_regiao2,
    (select pt.dtultaltpvenda from cedep.pctabpr pt
      where pt.codprod = cp.codigo and pt.numregiao = 1)                     as cedep_regiao1
from compras.compras_pedido cp
join compras.compras_produto_contexto ctx on ctx.codigo = cp.codigo
order by cp.codigo
"""

# SKUs alterados no WinThor durante o build de 16/09 (10:46-10:48) - medido pelo agente de
# dbt. Reaparecerem aqui e' defasagem esperada, nao regressao (ver docstring).
SKUS_DEFASAGEM_CONHECIDA = {64, 65, 1849, 8128, 8161, 8581, 8582}


def _dia(dt: datetime.datetime | None) -> datetime.date | None:
    return dt.date() if dt is not None else None


def executar_limpo(linhas: list[dict]) -> bool:
    print("#" * 92)
    print("EXECUCAO LIMPA: COMPRAS_PRODUTO_CONTEXTO.DT_ULT_ALT_PV_* x CEDEP.PCTABPR.DTULTALTPVENDA")
    print("#" * 92)
    print(f"Universo: {len(linhas)} SKUs (compras.compras_pedido join compras_produto_contexto)")
    print()

    tudo_ok = True
    for rotulo, ctx_col, cedep_col in (
        ("ATACADO (NUMREGIAO=2)", "ctx_atacado", "cedep_regiao2"),
        ("VAREJO  (NUMREGIAO=1)", "ctx_varejo", "cedep_regiao1"),
    ):
        nulos_ctx = sum(1 for l in linhas if l[ctx_col] is None)
        nulos_cedep = sum(1 for l in linhas if l[cedep_col] is None)
        nulos_ambos = sum(1 for l in linhas if l[ctx_col] is None and l[cedep_col] is None)

        divergentes = []
        defasagem = []
        for l in linhas:
            a, b = l[ctx_col], l[cedep_col]
            if a == b:
                continue
            if a is None or b is None or a != b:
                if l["codigo"] in SKUS_DEFASAGEM_CONHECIDA:
                    defasagem.append((l["codigo"], a, b))
                else:
                    divergentes.append((l["codigo"], a, b))

        print(f"{rotulo}")
        print(f"  nulos ctx={nulos_ctx}  nulos cedep={nulos_cedep}  nulos nos dois lados={nulos_ambos}")
        print(f"  divergencias (datetime completo, exclui defasagem conhecida): {len(divergentes)}")
        for codigo, a, b in divergentes[:3]:
            print(f"    exemplo CODIGO={codigo}: ctx={a}  cedep={b}")
        if defasagem:
            print(f"  defasagem esperada (SKU alterado no WinThor durante o build - nao e' defeito): "
                  f"{len(defasagem)}")
            for codigo, a, b in defasagem:
                print(f"    CODIGO={codigo}: ctx={a}  cedep(ao vivo)={b}")
        ok = len(divergentes) == 0
        tudo_ok = tudo_ok and ok
        print(f"  RESULTADO: {'PASSOU' if ok else 'FALHOU'} (zero divergencia real exigido)")
        print()

    return tudo_ok


def executar_defeito_injetado(linhas: list[dict]) -> bool:
    print("#" * 92)
    print("EXECUCAO COM DEFEITO INJETADO: atacado lendo NUMREGIAO=1 em vez de NUMREGIAO=2")
    print("#" * 92)
    print("Comparando CEDEP.PCTABPR(NUMREGIAO=1) [simula dt_ult_alt_pv_atacado defeituoso]")
    print("   x CEDEP.PCTABPR(NUMREGIAO=2) [fonte correta - o que ctx de fato contem hoje]")
    print()

    pares_com_as_duas_datas = [l for l in linhas if l["cedep_regiao1"] is not None and l["cedep_regiao2"] is not None]
    print(f"SKUs com data nas duas regioes: {len(pares_com_as_duas_datas)}")

    div_completa = [l for l in pares_com_as_duas_datas if l["cedep_regiao1"] != l["cedep_regiao2"]]
    div_dia = [l for l in pares_com_as_duas_datas if _dia(l["cedep_regiao1"]) != _dia(l["cedep_regiao2"])]

    print(f"  precisao completa (datetime com hora): {len(div_completa)} pares divergentes")
    print(f"  truncado por dia (trunc)              : {len(div_dia)} pares divergentes  <- numero de referencia do §2.2")
    print()
    for l in div_dia[:3]:
        print(f"    exemplo CODIGO={l['codigo']}: regiao1={l['cedep_regiao1']}  regiao2={l['cedep_regiao2']}")

    esperado_dia = 79
    ok = len(div_dia) == esperado_dia and len(div_dia) > 0
    print()
    print(f"RESULTADO: {'REPROVOU conforme esperado' if ok else 'NAO BATEU com o esperado'} "
          f"(por dia: {len(div_dia)}, esperado {esperado_dia}; por hora: {len(div_completa)})")
    # A "reprovacao" aqui E o sucesso do teste: o validador tem de acusar a diferenca.
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--injetar-defeito-regiao", action="store_true",
                     help="roda a comparacao simulando atacado lendo NUMREGIAO=1 (tem de reprovar em 79 SKUs)")
    ap.add_argument("--lib-dir", default=ORACLE_CLIENT_LIB_DIR)
    ap.add_argument("--profiles-path", default=PROFILES_PATH)
    args = ap.parse_args()

    conn = conectar(args.lib_dir, args.profiles_path)
    print(f"Conectado como COMPRAS em {datetime.datetime.now():%Y-%m-%d %H:%M:%S}.")
    cur = conn.cursor()
    cur.arraysize = 5000
    cur.prefetchrows = 5000
    cur.execute(SQL)
    cols = [d[0].lower() for d in cur.description]
    linhas = [dict(zip(cols, row)) for row in cur.fetchall()]
    cur.close()
    conn.close()

    if args.injetar_defeito_regiao:
        ok = executar_defeito_injetado(linhas)
    else:
        ok = executar_limpo(linhas)

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
