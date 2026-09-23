"""Compara `COMPRAS.COMPRAS_PEDIDO` (producao) com `COMPRAS_DEV.COMPRAS_PEDIDO`
(desenvolvimento), SKU a SKU, coluna a coluna - Etapa 16 secao 9.4.

So' SELECT. Nenhuma escrita em nenhum dos dois schemas.

DESENHO - por que o relatorio sai em TRES blocos, e nao um numero agregado
------------------------------------------------------------------------------
Os dois schemas sao construidos pelo MESMO codigo dbt, contra o MESMO
WinThor, mas em MOMENTOS diferentes (nenhuma Tarefa Agendada builda dev - ver
prompt secao 6). Isso separa a divergencia em tres naturezas, que NAO podem virar
um numero so' sem perder informacao:

  1) FORMULA/CUSTO - todo o resto da tabela (custo, credito, ICMS, PIS/COFINS,
     preco sugerido, ALERTA, CLASSE etc.). O calculo e' deterministico dado o
     mesmo cadastro/preco/estoque de entrada - divergencia aqui e' DEFEITO,
     e o esperado e' ZERO. Se acusar, isso vira etapa para o `dbt-regras`;
     este script NAO conserta nada, so' mede.
  2) WINTHOR AO VIVO - PV_ATACADO, PV_VAREJO, EST_DISP (tabela de preco e
     estoque do WinThor, mudam a cada venda/reajuste) e as colunas derivadas
     MKP_*/MARGEM_* (que leem esses dois precos). Divergencia aqui e'
     DEFASAGEM, nao defeito - os dois builds nao sao simultaneos. O relatorio
     imprime junto a diferenca de `last_ddl_time` entre os dois schemas, em
     horas, para o leitor decidir se a defasagem bate com o esperado.
  3) DECISAO (`APP_*`) - PEDIDO, PEDIDO_UNIDADES, PEDIDO_NA_MEDIDA, ALT_PV_*.
     EXCLUIDAS da comparacao de proposito: `COMPRAS_DEV` nasceu com as
     tabelas `APP_PEDIDO_ITEM`/`APP_DECISAO_PRECO`/`APP_LOTE_PRECO` vazias -
     decisao de compra e de preco e' dado de gente, gravado no dashboard, e
     nao se copia de producao para um ambiente de teste (prompt secao 6). Comparar
     sem excluir reportaria ~175 "divergencias" que sao, na verdade, a
     ausencia esperada de decisao em dev. O script imprime a contagem dos
     dois lados, nunca uma comparacao celula a celula.

EXERCICIO OBRIGATORIO (armadilha 15, aceite 10) - `--injetar-defeito-est-disp`
------------------------------------------------------------------------------
Um comparador que nunca acusou nada nao prova que os ambientes batem. Antes
de confiar no script, rode-o UMA VEZ com `--injetar-defeito-est-disp`, que
move EST_DISP do bloco 2 para o bloco 1 (formula) só para este exercicio -
tem que acusar as divergencias de EST_DISP como DEFEITO. Rode de novo SEM a
flag - EST_DISP tem que voltar a aparecer no bloco 2, como DEFASAGEM, com as
horas de `last_ddl_time` do lado.

LIMITACAO DE FUNDO - o que "bloco 1 = 0" NAO garante
------------------------------------------------------------------------------
Bloco 1 em zero so' e' prova de ausencia de defeito de formula quando os dois
builds leram os MESMOS insumos. Builds em horarios diferentes leem o WinThor
em estados diferentes, e qualquer coluna a jusante de um insumo que mudou vai
divergir sem que haja defeito nenhum. Para isolar de verdade um defeito de
formula, compare apenas os SKUs cujos insumos sao identicos nos dois lados -
p.ex. CUSTO_ULT_ENT so' nos SKUs em que DT_ULT_ENT bate. Medido em 23/09/2026:
dos 9 SKUs com CUSTO_ULT_ENT divergente, os 9 tinham DT_ULT_ENT diferente
(entrada nova em dev, datada de hoje) e ZERO divergiam com a mesma data -
defasagem, nao defeito.

TOLERANCIA
------------------------------------------------------------------------------
Colunas NUMBER comparam com tolerancia absoluta `--tolerancia` (default 0,01).
Colunas texto/char/data comparam por igualdade exata - as duas vem direto do
Oracle dos dois lados (nao ha' celula de Excel aqui), entao NULL e' NULL nos
dois lados; nao existe o caso `IFERROR(...,"")` que aparece nos scripts que
comparam contra a planilha.

Uso:
    python comparar_ambientes.py [--tolerancia 0.01] [--lib-dir ...]
                                  [--profiles-path ...]
                                  [--injetar-defeito-est-disp]
"""
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# Caminhos fixos do ambiente (ver CONTEXTO.md secao 3)
# ─────────────────────────────────────────────────────────────────────────────
ORACLE_CLIENT_LIB_DIR = r"C:\Oracle\instantclient_21_17"
PROFILES_PATH = os.path.expanduser(r"~\.dbt\profiles.yml")

TABELA = "COMPRAS_PEDIDO"
COLUNA_CHAVE = "CODIGO"

# Bloco 3 - decisao humana via APP_*, EXCLUIDAS da comparacao (ver docstring).
# MARGEM_ALVO/MARGEM_ALVO_VAREJO entraram aqui na revisao do opus (etapa 16):
# int_produto_preco_sugerido.sql:134-135 faz nvl(d.margem_alvo, par.margem_alvo_padrao),
# com `d` vindo de stg_decisao_preco -> APP_DECISAO_PRECO - decisao de gente, nao WinThor.
# Ficarem no bloco 2 atribuiria erroneamente qualquer divergencia futura a "defasagem
# do WinThor" quando na verdade seria decisao de preco gravada so' num dos lados.
# VALOR_PEDIDO entrou pelo mesmo motivo de coerencia: int_produto_pedido.sql:195 faz
# valor_pedido = pedido_unidades * custo_tot_oficial, e PEDIDO_UNIDADES ja' e' excluida -
# comparar o filho sem excluir o pai seria incoerente.
COLUNAS_APP_EXCLUIDAS = {
    "PEDIDO", "PEDIDO_UNIDADES", "PEDIDO_NA_MEDIDA",
    "ALT_PV_AT_AV", "ALT_PV_AT_AP", "ALT_PV_VAR_AV", "ALT_PV_VAR_AP",
    "MARGEM_ALVO", "MARGEM_ALVO_VAREJO", "VALOR_PEDIDO",
}

# Bloco 2 - WinThor ao vivo (preco/estoque/movimentacao) + tudo que descende
# disso na MESMA linha. Divergencia aqui e' defasagem, nao defeito.
# Classificado por ORIGEM (rastreamento do opus, etapa 16), nao por amostragem
# de prefixo - a lista original (so' PV_*/EST_DISP/MKP_*/MARGEM_*) deixava de
# fora ~13 colunas que tambem leem estoque/movimentacao ao vivo do WinThor:
#   - int_produto_demanda.sql:138-158 - est_disp, qt_bloqueada, qt_reservada,
#     pendente, qt_ult_ent, vd_mes_atual vem de qtdisp/qtbloqueada/qtreserv/
#     qtpedida/qatual do WinThor.
#   - int_cadastro_estoque.sql:126-134 - dt_ult_ent, qt_ult_ent, dt_ult_saida,
#     custo_ult_ent idem.
#   - int_produto_demanda.sql:201 - est_pend = est_disp + pendente; descendem
#     dai meses_est(273), sug_cobertura(277), dias_sem_venda(251),
#     meses_est_ped(209) e valor_estoque (int_produto_pedido.sql:211).
#   - int_produto_alerta.sql:285-288 - ALERTA le est_pend e dias_sem_venda;
#     REGRAS.md 6.1.1 ja classifica CHECK_ESTOQUE_PARADO como volatil.
#   - CUSTO_ULT_ENT -> CUSTO_TOT_* -> PV_SUG_*: cadeia fechada (REGRAS.md
#     6.1.0 - CUSTO_TOT_GERENCIAL descende de CUSTO_ULT_ENT, zero absoluto
#     ali e' impossivel).
COLUNAS_WINTHOR_VIVAS = {
    "PV_ATACADO", "PV_VAREJO", "EST_DISP",
    "MKP_ATACADO", "MKP_VAREJO",
    "MARGEM_ST_S_VALOR", "MARGEM_OFICIAL", "MARGEM_SEM_RED",
    "MARGEM_ST_S_VALOR_VAREJO", "MARGEM_SEM_RED_VAREJO",
    # estoque/movimentacao ao vivo e derivadas na mesma linha
    "EST_PEND", "MESES_EST", "MESES_EST_PED", "SUG_COBERTURA", "VALOR_ESTOQUE",
    "VD_MES_ATUAL", "QT_RESERVADA", "QT_BLOQUEADA", "PENDENTE",
    "DT_ULT_ENT", "QT_ULT_ENT", "DT_ULT_SAIDA", "DIAS_SEM_VENDA",
    "ALERTA", "CHECK_ESTOQUE_PARADO",
    # custo da ultima entrada e a cadeia CUSTO_TOT_* -> PV_SUG_* que descende dele
    "CUSTO_ULT_ENT",
    "CUSTO_TOT_OFICIAL", "CUSTO_TOT_S_VALOR", "CUSTO_TOT_GERENCIAL", "CUSTO_TOT_SEM_RED",
    "PV_SUG_ST_S_VALOR_AV", "PV_SUG_ST_S_VALOR_AP",
    "PV_SUG_OFICIAL_AV", "PV_SUG_OFICIAL_AP",
    "PV_SUG_SEM_RED_AV", "PV_SUG_SEM_RED_AP",
    "PV_SUG_ST_S_VALOR_VAR_AV", "PV_SUG_ST_S_VALOR_VAR_AP",
    "PV_SUG_SEM_RED_VAR_AV", "PV_SUG_SEM_RED_VAR_AP",
}


# ─────────────────────────────────────────────────────────────────────────────
# Banco (Oracle) - dois schemas, dois profiles do mesmo profiles.yml
# ─────────────────────────────────────────────────────────────────────────────


def _ler_credencial(profiles_path: str, profile: str) -> tuple[str, str, str]:
    import yaml
    with open(profiles_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    perfil = cfg[profile]
    target = perfil["target"]
    out = perfil["outputs"][target]
    return out["user"], out["password"], out["connection_string"]


# alias no molde de validar_pedido.py - mesma assinatura, so' que parametrizado
# por profile (aqui precisamos dos DOIS: `compras` e `compras_dev`).
def _ler_credencial_compras(profiles_path: str, profile: str = "compras") -> tuple[str, str, str]:
    return _ler_credencial(profiles_path, profile)


def conectar(lib_dir: str, profiles_path: str, profile: str):
    import oracledb
    try:
        oracledb.init_oracle_client(lib_dir=lib_dir)
    except oracledb.ProgrammingError:
        pass  # ja inicializado (chamada dupla no mesmo processo) - inofensivo
    user, password, dsn = _ler_credencial(profiles_path, profile)
    conn = oracledb.connect(user=user, password=password, dsn=dsn)
    del password
    return conn


def ler_tabela(conn, owner: str, arraysize: int = 5000):
    """SELECT * na tabela do owner indicado. Devolve (linhas por CODIGO,
    colunas disponiveis, dict coluna->DbType)."""
    import oracledb
    cur = conn.cursor()
    cur.arraysize = arraysize
    cur.prefetchrows = arraysize
    cur.execute(f"select * from {owner}.{TABELA}")
    descr = cur.description
    colunas = [d[0] for d in descr]
    tipos = {d[0]: d.type for d in descr}
    linhas: dict[int, dict] = {}
    while True:
        bloco = cur.fetchmany(arraysize)
        if not bloco:
            break
        for row in bloco:
            r = dict(zip(colunas, row))
            linhas[int(r[COLUNA_CHAVE])] = r
    cur.close()
    return linhas, set(colunas), tipos, oracledb.DB_TYPE_NUMBER


def max_last_ddl_time(conn, owner: str):
    """Maior `last_ddl_time` das tabelas COMPRAS_* do owner - mesma consulta
    do aceite 4 da etapa (`all_objects`, `like 'COMPRAS!_%' escape '!'`)."""
    cur = conn.cursor()
    cur.execute(
        "select max(last_ddl_time) from all_objects where owner = :o "
        "and object_name like 'COMPRAS!_%' escape '!'",
        {"o": owner.upper()},
    )
    (v,) = cur.fetchone()
    cur.close()
    return v


# ─────────────────────────────────────────────────────────────────────────────
# Comparacao
# ─────────────────────────────────────────────────────────────────────────────


def classificar_tipo(dbtype, db_type_number) -> str:
    return "numero" if dbtype == db_type_number else "exato"  # texto/char/data: igualdade exata


def comparar_valor(tipo: str, v1, v2, tol: float):
    """Devolve (diverge, diferenca_absoluta_ou_None)."""
    if v1 is None and v2 is None:
        return False, None
    if tipo == "numero":
        if v1 is None or v2 is None:
            return True, None  # um lado nulo, o outro nao - divergencia sem "diferenca" numerica
        diff = abs(float(v1) - float(v2))
        return diff > tol, diff
    return v1 != v2, None


@dataclass
class ResultadoColuna:
    coluna: str
    bloco: str
    tipo: str
    n_comparado: int
    n_diverge: int
    maior_diferenca: float | None
    exemplos: list = field(default_factory=list)  # (codigo, v_prod, v_dev, diff)

    @property
    def pct(self) -> float:
        return 100.0 * self.n_diverge / self.n_comparado if self.n_comparado else 0.0


def comparar_coluna(nome: str, bloco: str, tipo: str, prod: dict, dev: dict,
                     codigos_comuns: list[int], tol: float) -> ResultadoColuna:
    n_diverge = 0
    maior = None
    exemplos = []
    for cod in codigos_comuns:
        v1 = prod[cod].get(nome)
        v2 = dev[cod].get(nome)
        diverge, diff = comparar_valor(tipo, v1, v2, tol)
        if not diverge:
            continue
        n_diverge += 1
        if diff is not None and (maior is None or diff > maior):
            maior = diff
        if len(exemplos) < 3:
            exemplos.append((cod, v1, v2, diff))
    return ResultadoColuna(nome, bloco, tipo, len(codigos_comuns), n_diverge, maior, exemplos)


def _fmt(v) -> str:
    if v is None:
        return "NULL"
    return str(v)


def imprimir_bloco(titulo: str, nota: str, resultados: list[ResultadoColuna]):
    print()
    print("#" * 92)
    print(titulo)
    print("#" * 92)
    if nota:
        print(nota)
    resultados_ordenados = sorted(resultados, key=lambda r: r.n_diverge, reverse=True)
    n_com_divergencia = sum(1 for r in resultados_ordenados if r.n_diverge > 0)
    print(f"{len(resultados_ordenados)} coluna(s) comparada(s); {n_com_divergencia} com divergencia; "
          f"{len(resultados_ordenados) - n_com_divergencia} em zero.")
    print()
    for r in resultados_ordenados:
        marca = "DIVERGE" if r.n_diverge > 0 else "ok"
        maior_txt = f"{r.maior_diferenca:.6g}" if r.maior_diferenca is not None else "-"
        print(f"  [{marca:7}] {r.coluna:32} tipo={r.tipo:6} diverge={r.n_diverge:5}/{r.n_comparado} "
              f"({r.pct:5.2f}%)  maior_diferenca={maior_txt}")
        for cod, v1, v2, diff in r.exemplos:
            diff_txt = f" diff={diff:.6g}" if diff is not None else ""
            print(f"        exemplo CODIGO={cod}: prod={_fmt(v1)}  dev={_fmt(v2)}{diff_txt}")


def imprimir_bloco_excluido(colunas: set[str], prod: dict, dev: dict, codigos_comuns: list[int]):
    print()
    print("#" * 92)
    print("BLOCO 3 - DECISAO (APP_*) - EXCLUIDAS da comparacao")
    print("#" * 92)
    print("Dev nasce sem decisoes: decisao de compra e de preco e' dado de gente, gravado no")
    print("dashboard, e nao se copia de producao para um ambiente de teste (prompt secao 6). Contagem")
    print("de linhas PREENCHIDAS (nao nulas) de cada lado, sem comparar celula a celula:")
    print()
    for nome in sorted(colunas):
        n_prod = sum(1 for cod in codigos_comuns if prod[cod].get(nome) is not None)
        n_dev = sum(1 for cod in codigos_comuns if dev[cod].get(nome) is not None)
        print(f"  {nome:20} preenchido: prod={n_prod:5}  dev={n_dev:5}")


# ─────────────────────────────────────────────────────────────────────────────
# main
# ─────────────────────────────────────────────────────────────────────────────


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tolerancia", type=float, default=0.01,
                     help="tolerancia absoluta para colunas numericas - default 0,01")
    ap.add_argument("--lib-dir", default=ORACLE_CLIENT_LIB_DIR, help="Oracle Instant Client (modo thick)")
    ap.add_argument("--profiles-path", default=PROFILES_PATH, help="caminho do profiles.yml")
    ap.add_argument("--injetar-defeito-est-disp", action="store_true",
                     help="SO' PARA O EXERCICIO do aceite 10: move EST_DISP do bloco 2 (defasagem) "
                          "para o bloco 1 (formula), para provar que o script acusa quando deveria. "
                          "Nunca usar numa rodada que pretenda ser o veredito real.")
    args = ap.parse_args()

    colunas_winthor_vivas = set(COLUNAS_WINTHOR_VIVAS)
    if args.injetar_defeito_est_disp:
        colunas_winthor_vivas.discard("EST_DISP")
        print("!" * 92)
        print("EXERCICIO ATIVO (--injetar-defeito-est-disp): EST_DISP tratado como bloco 1 (FORMULA) "
              "nesta rodada - so' para provar que o comparador acusa. NAO e' o veredito real.")
        print("!" * 92)

    print("#" * 92)
    print(f"CONECTANDO: profile 'compras' -> schema COMPRAS (producao) | "
          f"profile 'compras_dev' -> schema COMPRAS_DEV (desenvolvimento)")
    print("#" * 92)
    conn_prod = conectar(args.lib_dir, args.profiles_path, "compras")
    conn_dev = conectar(args.lib_dir, args.profiles_path, "compras_dev")

    linhas_prod, colunas_prod, tipos_prod, DB_TYPE_NUMBER = ler_tabela(conn_prod, "COMPRAS")
    linhas_dev, colunas_dev, tipos_dev, _ = ler_tabela(conn_dev, "COMPRAS_DEV")

    dt_ddl_prod = max_last_ddl_time(conn_prod, "COMPRAS")
    dt_ddl_dev = max_last_ddl_time(conn_dev, "COMPRAS_DEV")

    conn_prod.close()
    conn_dev.close()

    codigos_prod = set(linhas_prod.keys())
    codigos_dev = set(linhas_dev.keys())
    codigos_comuns = sorted(codigos_prod & codigos_dev)
    so_prod = codigos_prod - codigos_dev
    so_dev = codigos_dev - codigos_prod

    print()
    print(f"COMPRAS.{TABELA}:      {len(codigos_prod)} SKUs")
    print(f"COMPRAS_DEV.{TABELA}:  {len(codigos_dev)} SKUs")
    print(f"SKUs so' em producao:      {len(so_prod)}"
          + (f" (ex.: {sorted(so_prod)[:5]})" if so_prod else ""))
    print(f"SKUs so' em desenvolvimento: {len(so_dev)}"
          + (f" (ex.: {sorted(so_dev)[:5]})" if so_dev else ""))
    print(f"SKUs comparados (intersecao): {len(codigos_comuns)}")

    colunas_comuns = (colunas_prod & colunas_dev) - {COLUNA_CHAVE}
    faltando_prod = colunas_dev - colunas_prod
    faltando_dev = colunas_prod - colunas_dev
    if faltando_prod or faltando_dev:
        print()
        print(f"AVISO: colunas so' em COMPRAS_DEV: {sorted(faltando_prod)}")
        print(f"AVISO: colunas so' em COMPRAS: {sorted(faltando_dev)}")

    colunas_bloco3 = colunas_comuns & COLUNAS_APP_EXCLUIDAS
    colunas_bloco2 = colunas_comuns & colunas_winthor_vivas
    colunas_bloco1 = colunas_comuns - colunas_bloco2 - colunas_bloco3

    # Bloco 1 - formula/custo: divergencia e' DEFEITO, esperado ZERO.
    resultados_1 = [
        comparar_coluna(nome, "formula", classificar_tipo(tipos_prod[nome], DB_TYPE_NUMBER),
                         linhas_prod, linhas_dev, codigos_comuns, args.tolerancia)
        for nome in colunas_bloco1
    ]
    imprimir_bloco(
        "BLOCO 1 - FORMULA/CUSTO - divergencia aqui e' DEFEITO (esperado: ZERO)",
        "Se alguma coluna abaixo divergir, isto NAO se conserta aqui - vira etapa "
        "propria com o dbt-regras. Este script so' mede.",
        resultados_1,
    )

    # Bloco 2 - WinThor ao vivo: divergencia e' DEFASAGEM.
    resultados_2 = [
        comparar_coluna(nome, "winthor_vivo", classificar_tipo(tipos_prod[nome], DB_TYPE_NUMBER),
                         linhas_prod, linhas_dev, codigos_comuns, args.tolerancia)
        for nome in colunas_bloco2
    ]
    nota_ddl = ""
    if dt_ddl_prod and dt_ddl_dev:
        diff_h = (dt_ddl_prod - dt_ddl_dev).total_seconds() / 3600.0
        nota_ddl = (f"last_ddl_time maximo das tabelas COMPRAS_* : producao={dt_ddl_prod}  "
                    f"dev={dt_ddl_dev}  diferenca={diff_h:+.1f}h (producao - dev; positivo = "
                    f"producao construida mais recentemente).")
    else:
        nota_ddl = "last_ddl_time indisponivel de um dos lados."
    imprimir_bloco(
        "BLOCO 2 - WINTHOR AO VIVO (preco/estoque) - divergencia aqui e' DEFASAGEM, nao defeito",
        nota_ddl,
        resultados_2,
    )

    # Bloco 3 - decisao APP_*: excluido, so' contagem.
    imprimir_bloco_excluido(colunas_bloco3, linhas_prod, linhas_dev, codigos_comuns)

    n_diverge_bloco1 = sum(r.n_diverge for r in resultados_1)
    print()
    print("#" * 92)
    print(f"VEREDITO BLOCO 1 (formula): {'ZERO divergencia - OK' if n_diverge_bloco1 == 0 else f'{n_diverge_bloco1} celula(s) divergente(s) - DEFEITO'}")
    print("#" * 92)
    print("LIMITACAO: bloco 1 = 0 so' prova ausencia de defeito de formula se os dois builds leram os")
    print("MESMOS insumos do WinThor. Builds em horarios diferentes leem estados diferentes - qualquer")
    print("coluna a jusante de um insumo que mudou diverge sem defeito nenhum. Para isolar defeito de")
    print("verdade, compare so' os SKUs com insumo identico dos dois lados (ex.: CUSTO_ULT_ENT so' nos")
    print("SKUs em que DT_ULT_ENT bate). Ver nota completa no cabecalho deste arquivo.")
    print("#" * 92)
    sys.exit(0 if n_diverge_bloco1 == 0 else 1)


if __name__ == "__main__":
    main()
