"""Valida a REGRA DAS TRES CONDICOES do ST embutido e monta a lista de
divergencia que vai para o Fiscal.

Origem: regra FECHADA pelo Diretor de Compras em 09/10/2026.

    "O painel so deve somar o ST no custo/valor gerencial quando as TRES
     condicoes forem verdadeiras ao mesmo tempo:
       1. Tributacao cadastrada no produto = ST substituto;
       2. Entrada a partir de 01/10/2022 (Decreto 7.799);
       3. Fornecedor de FORA da Bahia.
     Se qualquer uma das tres falhar, o ST ja esta no valor de entrada (ou nao
     existe) e nao soma.
     A leitura da nota continua como conferencia. Rodar a regra e me mandar a
     lista dos itens em que regra, nota e cadastro discordam."

SCHEMA - leia antes de rodar
------------------------------------------------------------------------------
Roda contra o schema do `.env` desta arvore (COMPRAS_DEV) e le DOIS lugares:
    * `int_produto_custo`  - a regra, ja aplicada pelo dbt;
    * `compras_pedido`     - cadastro, modalidade e descricao.
Somente SELECT. Nao escreve em tabela nenhuma, em schema nenhum.
O unico arquivo que ele cria e o relatorio .txt para o Fiscal, fora do banco.

POR QUE ESTE SCRIPT NAO REIMPLEMENTA A REGRA
------------------------------------------------------------------------------
Um validador que recalcula a regra por conta propria prova que duas copias
concordam, e nao que a regra esta certa - foi a licao do
validar_valor_gerencial.py ("um validador que le a propria resposta nao prova
nada"). Aqui ele faz outra coisa: afirma INVARIANTES sobre o resultado do dbt,
que valem hoje e em 2030 porque nao dependem do numero do dia.

    A. Nenhum produto fora da modalidade ST_SUBSTITUTO soma ST.
    B. Nenhum produto com entrada ANTES do Decreto soma ST.
    C. Nenhum produto comprado DENTRO do estado de destino soma ST.
    D. Nenhum produto sem data de entrada ou sem UF do fornecedor soma ST.
    E. Todo produto que passa nas tres E tem MVA e nota > 0 SOMA ST - este e'
       o lado que falta nos quatro de cima: sem ele, "nao somar nunca" passaria
       em A-D e a regra teria virado o oposto dela mesma, em silencio.

A CONFERENCIA QUE O DIRETOR PEDIU
------------------------------------------------------------------------------
1689 e 2671 (entradas de 2013 e 2014) param de somar ST: o valor gerencial
passa a ser igual ao valor de entrada, R$ 44,14 e R$ 6,99. Esses dois numeros
vem do pedido dele, nao do banco - sao gabarito, nao medida.
"""
from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

import oracledb  # noqa: E402

# O que o Diretor mediu e mandou conferir, em 09/10/2026.
CONFERENCIA = {1689: 44.14, 2671: 6.99}
TOL = 0.015

RELATORIO = RAIZ / "validar" / "saida" / "st_divergencias.txt"


class Reporter:
    def __init__(self):
        self.itens: list[tuple[str, bool, str]] = []

    def registrar(self, nome: str, ok: bool, detalhe: str = "") -> None:
        self.itens.append((nome, ok, detalhe))
        print(f"[{'PROVADO' if ok else 'FALHOU '}] {nome}")
        for linha in (detalhe or "").splitlines():
            print(f"          {linha}")

    def resumo(self) -> int:
        falhas = [n for n, ok, _ in self.itens if not ok]
        print("\n" + "=" * 78)
        print(f"{len(self.itens) - len(falhas)} PROVADO(S), {len(falhas)} FALHOU(RAM)")
        if falhas:
            print("FALHARAM: " + "; ".join(falhas))
        return 1 if falhas else 0


def conectar():
    env = {}
    for linha in (RAIZ / ".env").read_text(encoding="utf-8").splitlines():
        if "=" in linha and not linha.strip().startswith("#"):
            chave, valor = linha.split("=", 1)
            env[chave.strip()] = valor.strip()
    oracledb.init_oracle_client(lib_dir=env["ORA_CLIENT_DIR"])
    con = oracledb.connect(user=env["ORA_USER"], password=env["ORA_PASSWORD"],
                           dsn=env["ORA_DSN"])
    print(f"Conectado ao schema {env['ORA_SCHEMA']} (somente SELECT).\n")
    return con


# `soma_st` e' a leitura do EFEITO: ICMS_ST_BRUTO > 0 significa que o ST de
# fato entrou na conta. Nao e' `st_ja_na_entrada = 0`, que diz o que a regra
# DECIDIU. Conferir contra o efeito, e nao contra a intencao, e' o que pega um
# guarda-corpo esquecido num dos tres `case` de int_produto_custo.
UNIVERSO = """
    select p.codigo, p.descricao, p.modalidade, p.status,
           ctx.revenda,
           c.st_ja_na_entrada, c.st_destacado_na_nota,
           c.dt_ult_ent, c.uf_entrada, c.entrada_sem_nota, c.fornecedor_sem_uf,
           nvl(c.icms_st_bruto, 0)              as st_bruto,
           c.valor_tot_gerencial, p.vl_ent_unit, p.mva,
           case when nvl(c.icms_st_bruto, 0) > 0 then 1 else 0 end as soma_st
      from compras_pedido p
      join int_produto_custo c on c.codigo = p.codigo
      left join compras_produto_contexto ctx on ctx.codigo = p.codigo
     where p.status = 'Ativo'
"""


def _inicio_beneficio(cur):
    """A data do Decreto, lida do seed - nunca escrita aqui.

    Um validador com a data chumbada passaria a reprovar no dia em que a
    diretoria mudasse o parametro, e a culpa pareceria do model.

    Le `int_parametro`, e nao `compras_parametro`: a data e' insumo FISCAL do
    calculo de custo, nao parametro de tela. COMPRAS_PARAMETRO existe para o
    que o front recalcula ao vivo (comissao, fator de prazo, limiares de
    margem) - e publicar ali um parametro que a tela nunca usa so' aumentaria
    o payload de toda tela que chama /api/parametros.
    """
    return cur.execute(
        "select st_beneficio_inicio from int_parametro").fetchone()[0]


def _uf_destino(cur):
    """A UF de destino vem do mesmo lugar que o dbt usa (var compras_uf_destino,
    hoje 'BA'). Aqui ela nao tem tabela, entao fica explicita como constante de
    UM lugar so, e nao espalhada pelos filtros."""
    return "BA"


def cenario_1_invariantes(rep, cur, linhas, inicio, uf_destino):
    """As quatro negativas (A-D) e a positiva (E)."""
    casos = [
        ("A. modalidade fora de ST_SUBSTITUTO",
         lambda r: r["modalidade"] != "ST_SUBSTITUTO"),
        ("B. entrada ANTES do Decreto",
         lambda r: r["dt_ult_ent"] is not None and r["dt_ult_ent"] < inicio),
        (f"C. compra DENTRO de {uf_destino}",
         lambda r: r["uf_entrada"] == uf_destino),
        ("D. sem data de entrada ou sem UF do fornecedor",
         lambda r: r["dt_ult_ent"] is None or r["uf_entrada"] is None),
    ]
    for nome, filtro in casos:
        alvo = [r for r in linhas if filtro(r)]
        fora = [r for r in alvo if r["soma_st"]]
        rep.registrar(
            f"{nome}: nenhum soma ST ({len(alvo)} ativos)",
            not fora,
            "" if not fora else "somaram: " + ", ".join(str(r["codigo"]) for r in fora[:20]),
        )

    # E - a positiva. Sem MVA ou sem nota, BT/BU saem NULL por regra da
    # planilha (o "" do Excel), entao esses ficam de fora do universo: a
    # ausencia ali nao e' decisao da regra do ST.
    devem = [r for r in linhas
             if r["modalidade"] == "ST_SUBSTITUTO"
             and r["dt_ult_ent"] is not None and r["dt_ult_ent"] >= inicio
             and r["uf_entrada"] is not None and r["uf_entrada"] != uf_destino
             and (r["mva"] or 0) > 0 and (r["vl_ent_unit"] or 0) > 0]
    mudos = [r for r in devem if not r["soma_st"]]
    rep.registrar(
        f"E. passa nas tres, tem MVA e nota: TODOS somam ST ({len(devem)} ativos)",
        not mudos,
        "" if not mudos else "nao somaram: " + ", ".join(str(r["codigo"]) for r in mudos[:20]),
    )


def cenario_2_conferencia(rep, cur):
    """Os dois SKUs que o Diretor mandou conferir."""
    falhas, texto = [], []
    for sku, esperado in CONFERENCIA.items():
        linha = cur.execute(
            "select p.vl_ent_unit, c.valor_tot_gerencial, c.dt_ult_ent "
            "  from compras_pedido p join int_produto_custo c on c.codigo = p.codigo "
            " where p.codigo = :c", {"c": sku}).fetchone()
        if linha is None:
            falhas.append(f"SKU {sku} nao existe neste schema")
            continue
        entrada = float(linha[0] or 0)
        gerencial = float(linha[1] or 0)
        dt = linha[2]
        quando = f"{dt:%d/%m/%Y}" if dt else "sem data"
        texto.append(f"SKU {sku}: entrada {entrada:.2f} | gerencial {gerencial:.2f} "
                     f"| esperado {esperado:.2f} | ult. entrada {quando}")
        if abs(gerencial - esperado) > TOL:
            falhas.append(f"SKU {sku}: gerencial {gerencial:.2f} != {esperado:.2f}")
        if abs(gerencial - entrada) > TOL:
            falhas.append(f"SKU {sku}: gerencial {gerencial:.2f} != entrada {entrada:.2f}")
    rep.registrar(
        "CONFERENCIA do Diretor: 1689 e 2671 param de somar ST (gerencial = entrada)",
        not falhas,
        "\n".join(texto + (["FALHAS:"] + falhas if falhas else [])))


def relatorio_divergencias(linhas, inicio, uf_destino):
    """A lista que vai para o Fiscal.

    Quatro grupos, e os dois primeiros sao os que o Diretor nomeou. A ordem e'
    por gravidade do que estaria errado: 1 e 2 apontam CONTRADICAO entre a
    regra e o documento fiscal; 3 e 4 apontam AUSENCIA de evidencia, que nao e'
    a mesma coisa e nao pede a mesma providencia.
    """
    g1 = [r for r in linhas if r["soma_st"] and r["st_destacado_na_nota"]]
    g2 = [r for r in linhas
          if r["modalidade"] != "ST_SUBSTITUTO" and r["st_destacado_na_nota"]]
    g3 = [r for r in linhas
          if r["modalidade"] == "ST_SUBSTITUTO" and not r["soma_st"]
          and not r["st_destacado_na_nota"] and not r["entrada_sem_nota"]
          and r["uf_entrada"] is not None]
    g4 = [r for r in linhas
          if r["modalidade"] == "ST_SUBSTITUTO"
          and (r["entrada_sem_nota"] or r["fornecedor_sem_uf"])]
    # Item 1.17, decidido com o usuario em 09/10/2026: o cadastro e' quem marca
    # o que nao e' de revenda, e o 6326 nao esta marcado. A lista vai junto
    # porque e' a mesma pessoa que resolve as duas coisas.
    nao_revenda = [r for r in linhas if (r.get("revenda") or "S") == "N"]

    def bloco(titulo, explica, itens):
        out = [f"\n{titulo}  ({len(itens)} itens)", "-" * 78, explica, ""]
        if not itens:
            out.append("  (nenhum)")
        for r in sorted(itens, key=lambda x: x["codigo"])[:400]:
            dt = f"{r['dt_ult_ent']:%d/%m/%Y}" if r["dt_ult_ent"] else "sem data"
            nota = "ST destacado" if r["st_destacado_na_nota"] else "sem ST      "
            out.append(f"  {r['codigo']:>5}  {(r['descricao'] or '')[:36]:<36} "
                       f"{r['modalidade'] or '-':<14} {dt:<11} "
                       f"UF {r['uf_entrada'] or '--':<3} "
                       f"nota {nota} "
                       f"regra {'SOMA' if r['soma_st'] else 'nao soma'}")
        if len(itens) > 400:
            out.append(f"  ... e mais {len(itens) - 400}")
        return "\n".join(out)

    texto = [
        "DIVERGENCIAS ENTRE REGRA, NOTA E CADASTRO - ST EMBUTIDO",
        "=" * 78,
        "Regra das tres condicoes fechada pelo Diretor de Compras em 09/10/2026.",
        f"Inicio do beneficio (Decreto 7.799): {inicio:%d/%m/%Y}.",
        f"Estado de destino: {uf_destino}.",
        "",
        "A REGRA soma ST quando as tres valem juntas: cadastro ST substituto,",
        f"entrada a partir da data acima e fornecedor de fora de {uf_destino}.",
        "A NOTA e' conferencia: o WinThor guarda o custo COM e SEM ST, e quando",
        "os dois diferem o ST daquela compra veio destacado.",
        "",
        "Esta lista NAO diz que o painel esta errado. Diz onde a regra e o",
        "documento fiscal contam historias diferentes - e nesses casos a causa",
        "pode estar no CADASTRO do produto, e nao no calculo.",
        bloco("1. REGRA SOMA, MAS A NOTA JA TRAZIA O ST DESTACADO",
              "Cadastro ST substituto, compra de fora do estado depois do Decreto - e a\n"
              "nota, ainda assim, veio com ST destacado. Se a nota estiver certa, o\n"
              "painel soma o imposto duas vezes neste item.", g1),
        bloco("2. CADASTRO NAO E' ST SUBSTITUTO, MAS A NOTA TRAZ ST DESTACADO",
              "O produto esta cadastrado como Normal ou ST recolhido, e mesmo assim a\n"
              "compra veio com ST. Ou o cadastro esta desatualizado, ou o fornecedor\n"
              "destacou ST indevidamente.", g2),
        bloco("3. REGRA NAO SOMA, E A NOTA TAMBEM NAO TRAZIA ST",
              "Cadastro ST substituto, mas a compra foi dentro do estado ou anterior ao\n"
              "Decreto - entao a regra nao soma. So' que a nota tambem nao traz ST\n"
              "destacado: nao ha evidencia de que o imposto ja esteja no preco. Pode\n"
              "ser compra sem ST de fato, ou cadastro de origem errado.", g3),
        bloco("4. SEM COMO CONFERIR",
              "Entrada sem nota (carga inicial do WinThor) ou fornecedor sem UF no\n"
              "cadastro. A regra trata condicao nao comprovada como condicao FALHA e\n"
              "nao soma o ST - a direcao conservadora. Corrigir o cadastro do\n"
              "fornecedor resolve a maior parte destes.", g4),
        bloco("5. NAO E' DE REVENDA, MAS ESTA NO CADASTRO DE COMPRA",
              "Produto marcado REVENDA='N' - material de apoio, nao mercadoria. A\n"
              "Precificacao ja os esconde por padrao (filtro 'Revenda'). Entram aqui\n"
              "so' para conferencia: se algum destes for mercadoria de verdade, e' o\n"
              "cadastro que precisa mudar, e ele sumiu da tela sem dever sumir.\n"
              "\n"
              "⚠ O 6326 (TECFIL DISPLAY DE CHAO) NAO aparece nesta lista, e e' o item\n"
              "que motivou o pedido. Ele esta cadastrado como REVENDA='S',\n"
              "TIPOMERC='L' e TIPOPROD=1 - identico ao 2720 e ao 1689, que sao\n"
              "produtos de verdade. Nada no cadastro o distingue, entao o painel nao\n"
              "tem como esconde-lo.\n"
              "PROVIDENCIA: marcar o 6326, e os displays/expositores semelhantes,\n"
              "como REVENDA='N' no WinThor. Feito isso eles somem da Precificacao\n"
              "sozinhos, agora e no futuro.",
              nao_revenda),
    ]
    RELATORIO.parent.mkdir(parents=True, exist_ok=True)
    RELATORIO.write_text("\n".join(texto) + "\n", encoding="utf-8")
    print(f"\nRelatorio para o Fiscal: {RELATORIO}")
    print(f"  grupo 1 (regra soma x nota ja tinha ST) ........ {len(g1)}")
    print(f"  grupo 2 (cadastro nao-ST x nota com ST) ........ {len(g2)}")
    print(f"  grupo 3 (nao soma, mas nota nao tinha ST) ...... {len(g3)}")
    print(f"  grupo 4 (sem nota ou sem UF) ................... {len(g4)}")
    print(f"  grupo 5 (nao e de revenda) ..................... {len(nao_revenda)}")


def main():
    rep = Reporter()
    con = conectar()
    cur = con.cursor()
    try:
        try:
            cur.execute("select st_destacado_na_nota from int_produto_custo where rownum = 1")
        except oracledb.DatabaseError:
            print("ST_DESTACADO_NA_NOTA nao existe neste schema.")
            print("Rode o dbt com o model novo antes (em producao, so apos o deploy).")
            return 1
        inicio = _inicio_beneficio(cur)
        uf_destino = _uf_destino(cur)
        cur.execute(UNIVERSO)
        cols = [d[0].lower() for d in cur.description]
        linhas = [dict(zip(cols, r)) for r in cur.fetchall()]
        print(f"{len(linhas)} produtos ativos.\n")

        cenario_1_invariantes(rep, cur, linhas, inicio, uf_destino)
        cenario_2_conferencia(rep, cur)
        relatorio_divergencias(linhas, inicio, uf_destino)
    finally:
        cur.close()
        con.close()
    return rep.resumo()


if __name__ == "__main__":
    raise SystemExit(main())
