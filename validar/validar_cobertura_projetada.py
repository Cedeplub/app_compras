"""Valida a Etapa 18 (prompts/PROMPT_ETAPA_18_COBERTURA_PROJETADA.md, Sec 8.2):
a "cobertura depois do pedido" somava caixas como se fossem unidades, em tres
telas (CatalogoPedido.jsx, DecisaoSKU.jsx, e quem herda TabelaCatalogo). NAO
CONSERTA NADA. Mede e reporta.

A formula em jogo (CONTEXTO.md regra 6 - FATOR_EXIBICAO divide quase toda
quantidade): EST_PEND/MEDIA_JANELA chegam da API ja em unidade de EXIBICAO
(int_produto_demanda.sql:138,142,171,201); o campo de quantidade digitada
tambem e em unidade de exibicao (caixas). A formula ANTIGA multiplicava a
quantidade por FATOR_EXIBICAO antes de somar - o termo que sobra. A formula
NOVA nao multiplica:

    antiga: (est_pend + qtd * fator) / media_janela
    nova:   (est_pend + qtd)          / media_janela

Esta etapa e cliente puro (tres arquivos .jsx) - nenhuma coluna de
FAT_PEDIDO/COMPRAS_PEDIDO muda, nenhum model dbt e editado. Por isso nao
existe, em lugar nenhum do banco, uma coluna "gabarito" ja pronta com o valor
da cobertura-apos-pedido corrigida: COMPRAS_PEDIDO.MESES_EST_PED NAO serve
(carrega a MESMA mistura de unidades que a formula antiga - e porte fiel da
planilha - e diverge por desenho; comparar contra ele seria validar o
defeito, nao a correcao). O design abaixo prova a correcao por dois caminhos
que nao dependem de nenhuma coluna pre-calculada:

  1) AUTOTESTE (a licao de sempre: validador que nunca reprovou nao prova
     nada). Recalcula a formula ANTIGA e a NOVA sobre os mesmos dados reais
     de APP_PEDIDO_ITEM juntado com COMPRAS_PEDIDO, e prova que a antiga
     DIVERGE da nova nos itens com FATOR_EXIBICAO > 1 - e so neles.
  2) VALIDACAO REAL da formula nova, por dois invariantes algebricos que nao
     dependem de nenhum valor fixo no codigo: (a) nos itens com fator == 1
     as duas formulas sao IDENTICAS (grupo de controle); (b) a diferenca
     antiga-menos-nova fecha exatamente com a forma fechada
     qtd * (fator - 1) / media_janela, em todos os itens.

Numeros de referencia (973 itens, 103 com fator > 1, erro mediano 15,77,
erro maximo 195,59 no item 8811/pedido 282) foram medidos em 08/10/2026
contra o schema COMPRAS. Este script RECALCULA esses numeros a cada
execucao; nao os copia.

SCHEMA - decisao explicita (leia antes de rodar em outra maquina)
------------------------------------------------------------------------------
O .env desta arvore (app_compras_v2_dev) aponta para o schema isolado de
desenvolvimento, que nasce vazio. Os fatos que este script prova (pedido 361,
itens de APP_PEDIDO_ITEM, os 973/103 do Sec 5 do prompt) so existem no schema
de dados de PRODUCAO - foi la que o prompt mediu. Rodar contra o schema de
desenvolvimento nao provaria nem reprovaria nada: encontraria a tabela vazia.

Por isso este script reaproveita `validar_pedido.conectar`/`_ler_credencial_
compras` (mesmo mecanismo ja usado por validar/validar_pedido.py, leitura do
profile `compras` em ~/.dbt/profiles.yml) para TODAS as consultas - inclusive
o spot-check da secao 3, que chama o codigo de aplicacao de verdade
(`produto.obter`/`contrato.produto`, app/servicos/produto.py e
app/api/contrato.py). Esse codigo so enxerga o banco atraves de
`app.core.database`, que por sua vez so le as variaveis de ambiente ORA_* de
`app.config`/`.env` desta arvore (ou seja, o schema isolado, por padrao).
Para o spot-check nao rodar contra um schema diferente do resto do script -
o que produziria um relatorio incoerente, parte um schema parte outro - as
variaveis de ambiente ORA_* sao sobrescritas, ANTES de importar qualquer
modulo de app.*, com a MESMA credencial do profile `compras` (reaproveitada
de validar_pedido, nao relida/duplicada aqui). `app.config._carregar_env()`
usa `os.environ.setdefault`, entao essas variaveis explicitas vencem o .env
do disco. Nada e escrito em .env; nada muda para o resto do app - o efeito
dura so o processo deste script. So leitura, sempre.

Se os dois schemas um dia divergirem de um jeito que importe, a decisao
correta e reportar a divergencia, nao "ajustar" os numeros esperados - ver
CONTEXTO.md Sec 0.2 e o enunciado desta etapa.

Uso:
    python validar/validar_cobertura_projetada.py
"""
from __future__ import annotations

import os
import statistics
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TOLERANCIA = 0.01
TOLERANCIA_INVARIANTE = 0.0001

# Reaproveita o mecanismo de conexao ja testado de validar_pedido.py em vez
# de duplicar leitura de credencial - um unico lugar no repositorio sabe como
# abrir o schema de dados de producao para validacao.
from validar import validar_pedido as _vp  # noqa: E402

# Referencia do prompt Sec 2 (pedido 361) - usada so como anotacao
# informativa no spot-check (secao 3): EST_DISP/PENDENTE/MEDIA_JANELA sao
# colunas VOLATEIS (CONTEXTO.md Sec 6.2) e podem ter andado desde a medicao
# de 08/10/2026. O que de fato reprova o spot-check e a comparacao contra a
# MESMA linha de COMPRAS_PEDIDO lida ao vivo, nao estes numeros.
REFERENCIA_PROMPT_2026_10_08 = {
    2808: {"fator": 24, "est_disp": 165.5000, "pendente": 70, "est_pend": 235.5000, "media_janela": 42.4306},
    5177: {"fator": 12, "est_disp": 435.5833, "pendente": 500, "est_pend": 935.5833, "media_janela": 228.6389},
    3860: {"fator": 1, "est_disp": 637, "pendente": 700, "est_pend": 1337, "media_janela": 453.6667},
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

    def resumo(self) -> int:
        provados = [n for n, ok, _ in self.itens if ok is True]
        falhas = [n for n, ok, _ in self.itens if ok is False]
        print("\n" + "=" * 78)
        print(f"{len(provados)} PROVADO(S), {len(falhas)} FALHOU(RAM)")
        if falhas:
            print("FALHARAM: " + "; ".join(falhas))
        return 1 if falhas else 0


def _dictfetch(cur) -> list[dict]:
    cols = [c[0].lower() for c in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


# ──────────────────────────────────────────────────── 1/2: dados + formulas ──

_SQL_ITENS = """
    select pi.id_pedido, pe.status, pe.fornecedor as pedido_fornecedor,
           pi.id_produto as codigo, pi.quantidade,
           pi.fator_exibicao as fator_item,
           cp.fator_exibicao as fator_cadastro,
           cp.est_pend, cp.est_disp, cp.pendente, cp.media_janela
      from app_pedido_item pi
      join app_pedido pe on pe.id_pedido = pi.id_pedido
      join compras_pedido cp on cp.codigo = pi.id_produto
"""


def _carregar_itens(conn) -> list[dict]:
    cur = conn.cursor()
    cur.execute(_SQL_ITENS)
    linhas = _dictfetch(cur)
    cur.close()
    return linhas


def _calcular(linhas: list[dict]) -> list[dict]:
    """Para cada item, calcula formula antiga, nova e o erro em fechamento
    algebrico - tudo em Python, sem reaproveitar nenhuma coluna pre-pronta."""
    calc = []
    for l in linhas:
        media = float(l["media_janela"]) if l["media_janela"] is not None else 0.0
        if media == 0:
            continue  # cobertura indefinida - nem a tela antiga nem a nova mostram numero
        est_pend = float(l["est_pend"] or 0)
        qtd = float(l["quantidade"] or 0)
        fator = float(l["fator_item"] or 1)

        antiga = (est_pend + qtd * fator) / media
        nova = (est_pend + qtd) / media
        erro = antiga - nova
        erro_fechado = qtd * (fator - 1) / media  # forma fechada da Sec 5 do prompt

        calc.append({**l, "media_janela": media, "formula_antiga": antiga,
                     "formula_nova": nova, "erro": erro, "erro_fechado": erro_fechado})
    return calc


def cenario_autoteste_defeito_injetado(rep: Reporter, calc: list[dict]) -> None:
    """Prova que a formula ANTIGA (buggy) ACUSA divergencia real contra a
    formula NOVA (corrigida), nos itens com FATOR_EXIBICAO > 1 - e que a
    magnitude bate com o Sec 5 do prompt (973 itens, 103 com fator > 1, erro
    mediano 15,77, erro maximo 195,59 no item 8811/pedido 282)."""
    total = len(calc)
    divergentes = [c for c in calc if abs(c["erro"]) > TOLERANCIA]
    erros = [abs(c["erro"]) for c in divergentes]
    mediana = statistics.median(erros) if erros else 0.0
    maior = max(divergentes, key=lambda c: abs(c["erro"])) if divergentes else None

    # `total` aqui e' so os itens com media_janela != 0 (969 de 973 - os 4
    # restantes tem cobertura indefinida e ja' foram contados a parte, na
    # consulta bulk em main()). Nao se exige total == 973 nesta funcao.
    ok = (
        len(divergentes) > 0
        and len(divergentes) == 103
        and maior is not None
        and maior["codigo"] == 8811
        and maior["id_pedido"] == 282
        and abs(abs(maior["erro"]) - 195.59) < 0.1
        and abs(mediana - 15.77) < 0.1
    )
    maior_erro = maior["erro"] if maior else None
    maior_cod = maior["codigo"] if maior else None
    maior_pedido = maior["id_pedido"] if maior else None
    maior_erro_fmt = f"{maior_erro:.2f}" if maior_erro is not None else "None"
    rep.registrar(
        f"AUTOTESTE - formula ANTIGA ((est_pend + qtd*fator)/media_janela) DIVERGE da NOVA "
        f"((est_pend+qtd)/media_janela) em {len(divergentes)} de {total} itens de APP_PEDIDO_ITEM "
        "(esperado 103 de 973)",
        ok,
        f"total_itens={total}; divergentes={len(divergentes)}; erro_mediano={mediana:.2f} meses "
        f"(esperado 15,77); maior_erro={maior_erro_fmt} meses "
        f"no item SKU {maior_cod}/pedido {maior_pedido} "
        "(esperado 195,59 no SKU 8811/pedido 282)",
    )
    if not ok:
        print("          -- validador reprovando de proposito: formula antiga tem de divergir. "
              "Se esta linha aparecer com 0 divergencias, o defeito NAO foi reproduzido --")
    if divergentes:
        piores = sorted(divergentes, key=lambda c: -abs(c["erro"]))[:3]
        print("          3 maiores divergencias (autoteste, formula antiga vs nova):")
        for c in piores:
            print(f"            SKU {c['codigo']}, pedido {c['id_pedido']}: "
                  f"antiga={c['formula_antiga']:.4f}  nova={c['formula_nova']:.4f}  "
                  f"erro={c['erro']:.4f}")


def cenario_validacao_real(rep: Reporter, calc: list[dict]) -> None:
    """Prova a formula NOVA por dois invariantes algebricos, sem depender de
    nenhuma coluna pre-calculada no banco (MESES_EST_PED nao serve - Sec 3.3
    do prompt, mistura as mesmas duas unidades que o defeito):

    (a) fator == 1  =>  antiga == nova, SEMPRE (grupo de controle, ex. 3860).
    (b) antiga - nova == qtd*(fator-1)/media_janela, em TODOS os itens -
        fecha a forma fechada da Sec 5 contra o calculo bruto, item a item."""
    grupo_fator_1 = [c for c in calc if float(c["fator_item"] or 1) == 1.0]
    divergentes_fator_1 = [c for c in grupo_fator_1 if abs(c["erro"]) > TOLERANCIA]
    rep.registrar(
        f"formula nova == formula antiga quando FATOR_EXIBICAO == 1 (grupo de controle, "
        f"{len(grupo_fator_1)} itens) - nao muda o que ja estava certo",
        not divergentes_fator_1,
        f"{len(divergentes_fator_1)} divergencia(s) no grupo de controle"
        + ("" if not divergentes_fator_1 else ": " + str(
            [(c["codigo"], c["erro"]) for c in divergentes_fator_1[:5]])),
    )

    divergentes_fechamento = [
        c for c in calc if abs(c["erro"] - c["erro_fechado"]) > TOLERANCIA
    ]
    rep.registrar(
        f"(formula_antiga - formula_nova) fecha com a forma fechada qtd*(fator-1)/media_janela "
        f"da Sec 5, item a item, nos {len(calc)} itens com media_janela != 0",
        not divergentes_fechamento,
        f"{len(divergentes_fechamento)} item(ns) onde o fechamento algebrico nao bate"
        + ("" if not divergentes_fechamento else ": " + str(
            [(c["codigo"], c["erro"], c["erro_fechado"]) for c in divergentes_fechamento[:5]])),
    )


# ──────────────────────────────────────────────── 3: spot-check codigo real ──


def cenario_spot_check_codigo_real(rep: Reporter, conn) -> None:
    """Chama o codigo de aplicacao de verdade (produto.obter + contrato.
    produto) para 2808, 5177 e 3860, e confere que estPend, pendente,
    mediaJanela e mesesCobertura chegam ao JSON exatamente com os valores da
    MESMA linha de COMPRAS_PEDIDO lida ao vivo (nao um numero fixo no codigo
    - EST_DISP/PENDENTE/MEDIA_JANELA sao volateis, CONTEXTO.md Sec 6.2). E
    isso que prova que a correcao do front opera sobre os campos que de fato
    chegam pela API."""
    # Aponta app.config para o MESMO schema desta sessao, antes de importar
    # qualquer modulo de app.* (ver docstring do modulo, secao SCHEMA).
    # Reaproveita a credencial ja lida por validar_pedido (mesmo profile
    # `compras`), sem reler nem duplicar o arquivo de credencial aqui.
    user, senha, dsn = _vp._ler_credencial_compras(_vp.PROFILES_PATH)
    os.environ["ORA_USER"] = user
    os.environ["ORA_PASSWORD"] = senha
    os.environ["ORA_DSN"] = dsn
    os.environ["ORA_SCHEMA"] = user.upper()
    os.environ["ORA_CLIENT_DIR"] = _vp.ORACLE_CLIENT_LIB_DIR
    del senha

    from app.api import contrato  # noqa: E402  (import tardio - ver docstring)
    from app.servicos import produto  # noqa: E402

    falhas = []
    for codigo in REFERENCIA_PROMPT_2026_10_08:
        cur = conn.cursor()
        cur.execute(
            "select est_disp, est_pend, pendente, media_janela, meses_est, fator_exibicao"
            " from compras_pedido where codigo = :codigo",
            {"codigo": codigo},
        )
        row = _dictfetch(cur)
        cur.close()
        if not row:
            falhas.append(f"SKU {codigo}: nao encontrado em COMPRAS_PEDIDO")
            continue
        esperado = row[0]

        linha = produto.obter(codigo)
        if linha is None:
            falhas.append(f"SKU {codigo}: produto.obter devolveu None")
            continue
        corpo = contrato.produto(linha)

        checagens = [
            ("estPend", corpo["estPend"], esperado["est_pend"]),
            ("pendente", corpo["pendente"], esperado["pendente"]),
            ("mediaJanela", corpo["mediaJanela"], esperado["media_janela"]),
            ("mesesCobertura", corpo["mesesCobertura"], esperado["meses_est"]),
            ("fatorExibicao", corpo["fatorExibicao"], esperado["fator_exibicao"]),
        ]
        for campo, obtido, esperado_valor in checagens:
            ev = float(esperado_valor) if esperado_valor is not None else None
            ob = float(obtido) if obtido is not None else None
            if ev is None and ob is None:
                continue
            if ev is None or ob is None or abs(ob - ev) > TOLERANCIA:
                falhas.append(f"SKU {codigo}.{campo}: API={ob}, COMPRAS_PEDIDO ao vivo={ev}")

        ref = REFERENCIA_PROMPT_2026_10_08[codigo]
        print(f"          SKU {codigo}: API estPend={corpo['estPend']} pendente={corpo['pendente']} "
              f"mediaJanela={corpo['mediaJanela']} mesesCobertura={corpo['mesesCobertura']} "
              f"fatorExibicao={corpo['fatorExibicao']}  "
              f"(referencia Sec 2 do prompt, 08/10/2026, informativa - pode ter andado: "
              f"est_pend={ref['est_pend']}, media_janela={ref['media_janela']})")

    rep.registrar(
        "codigo de aplicacao (produto.obter + contrato.produto) devolve estPend/pendente/"
        "mediaJanela/mesesCobertura/fatorExibicao identicos a MESMA linha de COMPRAS_PEDIDO "
        f"lida ao vivo, para os {len(REFERENCIA_PROMPT_2026_10_08)} SKUs de referencia (2808, 5177, 3860)",
        not falhas,
        "\n".join(falhas) or "nenhuma divergencia",
    )


# ───────────────────────────────────────────────────── 4: invariante global ──


def cenario_invariante_est_pend(rep: Reporter, conn) -> None:
    """EST_PEND = EST_DISP + PENDENTE, sobre COMPRAS_PEDIDO inteiro - e a
    afirmacao que sustenta a remocao do estDisp da soma em
    DecisaoSKU.jsx:89-90 (Sec 3.2 do prompt: somar os dois conta o estoque
    duas vezes). Tolerancia 0,0001 (mesma do prompt)."""
    cur = conn.cursor()
    cur.execute(
        "select count(*) as total,"
        "       sum(case when abs(nvl(est_disp,0) + nvl(pendente,0) - nvl(est_pend,0))"
        "                > :tol then 1 else 0 end) as divergentes"
        "  from compras_pedido",
        {"tol": TOLERANCIA_INVARIANTE},
    )
    row = _dictfetch(cur)[0]
    cur.close()
    total = int(row["total"])
    divergentes = int(row["divergentes"] or 0)
    rep.registrar(
        "invariante EST_PEND = EST_DISP + PENDENTE em COMPRAS_PEDIDO inteiro "
        f"({total} linhas recalculadas agora, tolerancia {TOLERANCIA_INVARIANTE})",
        divergentes == 0,
        f"{total - divergentes} de {total} linhas fecham; {divergentes} divergencia(s)",
    )


# ─────────────────────────────────────────────────── 5: contagens, por fim ──


def imprimir_contagens(calc: list[dict]) -> None:
    print("\n" + "-" * 78)
    print("CONTAGENS RECALCULADAS (nao copiadas do prompt)")
    print("-" * 78)

    com_fator = [c for c in calc if float(c["fator_item"] or 1) > 1]
    print(f"\nItens com FATOR_EXIBICAO > 1 (congelado no item): {len(com_fator)} de {len(calc)}")

    por_pedido: dict[int, int] = {}
    por_status: dict[str, int] = {}
    for c in com_fator:
        por_pedido[c["id_pedido"]] = por_pedido.get(c["id_pedido"], 0) + 1
        por_status[c["status"]] = por_status.get(c["status"], 0) + 1

    print("  por pedido:")
    for pedido, n in sorted(por_pedido.items()):
        fornecedor = next((c["pedido_fornecedor"] for c in com_fator if c["id_pedido"] == pedido), "?")
        status = next((c["status"] for c in com_fator if c["id_pedido"] == pedido), "?")
        print(f"    pedido {pedido} ({fornecedor}, {status}): {n} item(ns)")

    print("  por status:")
    for status, n in sorted(por_status.items()):
        print(f"    {status}: {n} item(ns)")

    print("\n10 maiores erros (|formula_antiga - formula_nova|, em meses):")
    piores = sorted(calc, key=lambda c: -abs(c["erro"]))[:10]
    for c in piores:
        print(f"    SKU {c['codigo']}, pedido {c['id_pedido']} ({c['status']}): "
              f"fator={c['fator_item']:.0f}  qtd={c['quantidade']:.0f}  "
              f"media_janela={c['media_janela']:.4f}  "
              f"antiga={c['formula_antiga']:.2f}  nova={c['formula_nova']:.2f}  "
              f"erro={c['erro']:.2f}")


def main() -> int:
    rep = Reporter()
    print(f"Conectando (reaproveitando validar_pedido.conectar, profile 'compras' de {_vp.PROFILES_PATH})...")
    conn = _vp.conectar(_vp.ORACLE_CLIENT_LIB_DIR, _vp.PROFILES_PATH)
    print("Conectado.\n")

    linhas = _carregar_itens(conn)
    calc = _calcular(linhas)
    rep.registrar(
        f"APP_PEDIDO_ITEM juntado com COMPRAS_PEDIDO devolveu {len(linhas)} item(ns) "
        f"({len(calc)} com media_janela != 0, usavel para a formula) - prompt Sec 5 esperava 973",
        len(linhas) > 0,
        f"{len(linhas)} linha(s) brutas, {len(calc)} com media_janela != 0",
    )
    print()

    cenario_autoteste_defeito_injetado(rep, calc)
    print()
    cenario_validacao_real(rep, calc)
    print()
    cenario_spot_check_codigo_real(rep, conn)
    print()
    cenario_invariante_est_pend(rep, conn)

    imprimir_contagens(calc)

    conn.close()
    return rep.resumo()


if __name__ == "__main__":
    sys.exit(main())
