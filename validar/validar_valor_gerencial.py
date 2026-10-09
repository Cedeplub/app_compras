"""Valida o VALOR GERENCIAL (COMPRAS_PRODUTO_CONTEXTO.VALOR_TOT_GERENCIAL).

Origem: documento "Valor Gerencial e Custo Gerencial - formula e logica de
calculo", 6a versao, do Diretor de Compras, validado por ele DIRETO NA TELA
(compras.cdp.lub/precificacao) em 29/09/2026 sobre 9 produtos que cobrem as 3
modalidades x 2 tratamentos de PIS/COFINS.

SCHEMA - leia antes de rodar
------------------------------------------------------------------------------
Roda contra o schema do `.env` desta arvore, que e COMPRAS_DEV. E deliberado e
necessario: VALOR_TOT_GERENCIAL e coluna NOVA e so existe onde o dbt ja rodou
com o model novo. Em COMPRAS (producao) ela ainda nao existe, e o script avisa
em vez de estourar. Depois do deploy, rodar tambem la.

Somente SELECT. Nao escreve em tabela nenhuma, em schema nenhum.

A ESTRATEGIA, e por que ela nao envelhece
------------------------------------------------------------------------------
O cenario 1 e um VETOR DE TESTE CONGELADO: alimenta a formula com os valores de
ENTRADA que o documento registrou (valor e custo da ultima entrada de cada um
dos 9 produtos, na data em que o Diretor mediu) e exige as SAIDAS que ele
registrou. Entradas e saidas vem ambas do documento, entao o teste vale hoje e
em 2030 - ele nao olha o banco para isso.

Isso importa porque o banco ANDA: medido em 08/10/2026, o YPF 6771 recebeu
entrada nova em 01/10 (valor 23,80 -> 23,53) e o Tecfil 574 em 05/10 (10,38 ->
10,64). Um teste que comparasse o banco de HOJE contra os numeros do documento
reprovaria por isso, sem defeito nenhum. Foi exatamente o que aconteceu na
primeira conferencia desta etapa: 7 dos 9 bateram, e os 2 que nao bateram eram
entrada nova, nao erro de formula.

O cenario 3 e o que olha o banco, e compara contra a formula RECALCULADA com os
insumos de hoje - uma identidade, que nao depende de data.
"""
from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

import oracledb  # noqa: E402

ALIQ_BA = 0.205   # Parametros!$B$16 - conferido contra int_parametro no cenario 0
PERC_NF = 0.80    # PERC_NF_NORMAL_INGRAX - idem
TOL = 0.015       # o documento declara arredondamentos de R$ 0,01

# ---------------------------------------------------------------------------
# O vetor congelado: os 9 produtos como o documento os registrou em 29/09/2026.
# (fornecedor, modalidade, valor_ult_ent, custo_ult_ent, valor_gerencial,
#  custo_gerencial_oficial, custo_st_s_valor | None quando nao se aplica)
# ---------------------------------------------------------------------------
DOCUMENTO = {
    6771: ("YPF",      "ST_SUBSTITUTO", 23.80, 21.67, 31.72, 28.88, 29.59),
    7019: ("Ipiranga", "ST_SUBSTITUTO", 16.46, 14.95, 21.94, 19.92, 20.43),
    3827: ("Ingrax",   "ST_SUBSTITUTO", 12.09, 10.97, 19.14, 17.36, 17.73),
    574:  ("Tecfil",   "ST_SUBSTITUTO", 10.38,  9.69, 14.04, 12.41, 12.65),
    8761: ("Cadillac", "NORMAL",        32.75, 30.87, 32.75, 30.87, None),
    2720: ("CAR80",    "NORMAL",        18.17, 15.34, 18.17, 15.34, None),
    455:  ("3M",       "NORMAL",         6.72,  5.67,  6.72,  5.67, None),
    8825: ("Robust",   "ST_RECOLHIDO",  85.00, 85.00, 85.00, 85.00, None),
    8105: ("MOTUL",    "ST_RECOLHIDO",  69.52, 63.09, 69.52, 63.09, None),
}


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


def valor_gerencial(valor, mva, modalidade, ingrax, st_ja_na_entrada=False,
                    aliq=ALIQ_BA, perc=PERC_NF):
    """A formula da Secao 2 do documento, escrita uma vez so.

    BRUTO = sem nenhum termo de credito: nao subtrai `valor * cred_icms` (como
    BT faz) e nao multiplica o adicional por (1 - piscof_ef) (como BX faz).

    `st_ja_na_entrada` (09/10/2026): quando o ICMS-ST da nota JA esta dentro do
    custo da ultima entrada, somar o calculado contaria duas vezes - entao o
    termo de ST sai. ⚠ A marca e RECALCULADA DA FONTE neste script
    (PCEST.CUSTOULTENT > PCEST.CUSTOULTENTSEMST), nunca lida da nossa coluna
    int_produto_custo.st_ja_na_entrada: um validador que le a propria resposta
    do model nao valida nada. Isso tambem faz o script rodar contra COMPRAS
    antes do deploy, porque as colunas do PCEST ja existem la.
    """
    st = (0.0 if st_ja_na_entrada
          else valor * (1 + mva) * aliq if modalidade == "ST_SUBSTITUTO"
          else 0.0)
    adicional = valor * (1 / perc - 1) if ingrax else 0.0
    return valor + st + adicional


def custo_gerencial(valor, custo, mva, modalidade, ingrax, cred_icms, piscof,
                    base_no_valor, aliq=ALIQ_BA, perc=PERC_NF):
    """Secao 3 do documento. `base_no_valor` escolhe o cenario:

    True  -> "ST s/Valor"            (base do ICMS-ST e o VALOR da ultima entrada)
    False -> "Oficial"/"Sem Reducao" (base e o CUSTO da ultima entrada)

    O termo de credito e sempre sobre o VALOR, nos dois cenarios.
    """
    if modalidade == "ST_SUBSTITUTO":
        base = valor if base_no_valor else custo
        st = max(0.0, base * (1 + mva) * aliq - valor * cred_icms)
    else:
        st = 0.0
    adicional = valor * (1 / perc - 1) * (1 - piscof) if ingrax else 0.0
    return custo + st + adicional


def cenario_0_parametros(rep, cur):
    """As duas constantes saem do banco, nao do codigo - se alguem mudar o
    parametro, este script tem de saber antes de validar qualquer numero."""
    aliq, perc = cur.execute(
        "select aliq_icms_interna_ba, perc_nf_normal_ingrax from int_parametro").fetchone()
    aliq, perc = float(aliq), float(perc)
    ok = abs(aliq - ALIQ_BA) < 1e-9 and abs(perc - PERC_NF) < 1e-9
    rep.registrar(
        "int_parametro bate com as constantes do documento "
        "(aliquota interna BA e % da NF normal da Ingrax)",
        ok,
        f"banco: aliq={aliq} perc_nf={perc} | documento: aliq={ALIQ_BA} perc_nf={PERC_NF}",
    )


def cenario_1_vetor_congelado(rep, cur):
    """Alimenta a formula com os INSUMOS do documento e exige as SAIDAS dele.

    So consulta o banco para MVA / CRED_ICMS / PISCOF_EF, que sao cadastro
    fiscal e nao mudam com entrada de mercadoria. Se um dia mudarem, este
    cenario reprova - e ai e pergunta para o Diretor, nao defeito do codigo: a
    validacao dele foi feita sob aquele cadastro.
    """
    falhas, linhas, n_saidas = [], [], 0
    for sku, dados in DOCUMENTO.items():
        forn, mod, valor, custo, vg_doc, cg_doc, sv_doc = dados
        linha = cur.execute(
            "select mva, cred_icms, piscof_ef from compras_pedido where codigo = :c",
            {"c": sku}).fetchone()
        if linha is None:
            falhas.append(f"SKU {sku} nao existe neste schema")
            continue
        mva = float(linha[0] or 0)
        cred = float(linha[1] or 0)
        piscof = float(linha[2] or 0)
        ingrax = forn.upper() == "INGRAX"

        vg = valor_gerencial(valor, mva, mod, ingrax)
        cg = custo_gerencial(valor, custo, mva, mod, ingrax, cred, piscof, False)
        sv = custo_gerencial(valor, custo, mva, mod, ingrax, cred, piscof, True)

        for rotulo, calc, doc in (("ValorGer", vg, vg_doc),
                                  ("CustoGer", cg, cg_doc),
                                  ("STs/Valor", sv, sv_doc)):
            if doc is None:
                continue
            n_saidas += 1
            if abs(calc - doc) > TOL:
                falhas.append(f"SKU {sku} {rotulo}: calculado {calc:.2f} != documento {doc:.2f}")
        texto = (f"SKU {sku:>5} {forn:<9} {mod:<14} "
                 f"ValorGer {vg:7.2f}/{vg_doc:<7.2f} CustoGer {cg:7.2f}/{cg_doc:<7.2f}")
        if sv_doc is not None:
            texto += f" STs/Valor {sv:7.2f}/{sv_doc:<7.2f}"
        linhas.append(texto)

    detalhe = "calculado/documento:\n" + "\n".join(linhas)
    if falhas:
        detalhe += "\nFALHAS:\n" + "\n".join(falhas)
    rep.registrar(
        f"VETOR CONGELADO - a formula reproduz as {n_saidas} saidas que o Diretor mediu "
        "na tela em 29/09/2026, a partir dos insumos que ele registrou",
        not falhas,
        detalhe,
    )


def _universo(cur):
    """O universo, com a marca de ST-ja-embutido vinda da FONTE (PCEST).

    O join com cedep.pcest e' somente SELECT, como toda leitura do CEDEP neste
    projeto. CODFILIAL = '2' e' a filial de estoque (var compras_filial_estoque
    no dbt_project.yml) - a mesma de onde CUSTO_ULT_ENT e VL_ENT_UNIT saem.
    """
    return cur.execute("""
        select p.codigo, p.vl_ent_unit, p.mva, p.modalidade, p.fornecedor,
               ctx.valor_tot_gerencial,
               case when nvl(e.CUSTOULTENT, 0) > nvl(e.CUSTOULTENTSEMST, 0) + 0.005
                    then 1 else 0 end as st_ja_na_entrada
          from compras_pedido p
          join compras_produto_contexto ctx on ctx.codigo = p.codigo
          left join cedep.pcest e
            on e.CODPROD = p.codigo and e.CODFILIAL = '2'
         where ctx.valor_tot_gerencial is not null""").fetchall()


def cenario_2_autoteste(rep, cur):
    """Prova que as duas parcelas do Valor Gerencial ACUSAM quando removidas.

    Criterio por INVARIANTE, nao por numero do dia (mesma licao que o
    validar_cobertura_projetada.py aprendeu em 08/10/2026): TODO ST_SUBSTITUTO
    com nota > 0 tem de divergir se o ICMS-ST bruto sair, e TODO INGRAX com
    nota > 0 tem de divergir se o adicional sair. Nenhum NORMAL/ST_RECOLHIDO
    sem Ingrax pode divergir - neles o Valor Gerencial e o proprio valor da
    nota, e um desvio ali seria a correcao aplicada no lugar errado.
    """
    linhas = _universo(cur)
    st_nao_acusou, ingrax_nao_acusou, neutro_mexeu = [], [], []
    for cod, vl, mva, mod, forn, _vg, ja_st in linhas:
        vl, mva, ja_st = float(vl), float(mva or 0), bool(ja_st)
        ingrax = (forn or "").upper() == "INGRAX"
        certo = valor_gerencial(vl, mva, mod, ingrax, ja_st)
        sem_st = valor_gerencial(vl, mva, "NORMAL", ingrax, ja_st)
        sem_adicional = valor_gerencial(vl, mva, mod, False, ja_st)
        # ⚠ `and not ja_st`: nos itens em que o ST ja veio na entrada, tirar o
        # termo de ST NAO pode mudar nada - ele ja e zero. Exigir divergencia
        # neles reprovaria a propria correcao de 09/10/2026.
        if mod == "ST_SUBSTITUTO" and vl > 0 and not ja_st and abs(certo - sem_st) <= 0.005:
            st_nao_acusou.append(cod)
        if ingrax and vl > 0 and abs(certo - sem_adicional) <= 0.005:
            ingrax_nao_acusou.append(cod)
        if mod != "ST_SUBSTITUTO" and not ingrax and abs(certo - vl) > 0.005:
            neutro_mexeu.append(cod)

    n_st = sum(1 for r in linhas
               if r[3] == "ST_SUBSTITUTO" and float(r[1]) > 0 and not r[6])
    n_ingrax = sum(1 for r in linhas if (r[4] or "").upper() == "INGRAX" and float(r[1]) > 0)
    ok = (n_st > 0 and n_ingrax > 0 and not st_nao_acusou
          and not ingrax_nao_acusou and not neutro_mexeu)
    rep.registrar(
        "AUTOTESTE - tirar o ICMS-ST bruto muda TODOS os ST_SUBSTITUTO com nota > 0 "
        f"e SEM ST ja na entrada ({n_st}); tirar o adicional muda TODOS os "
        f"INGRAX com nota > 0 ({n_ingrax}); "
        "e nenhum NORMAL/ST_RECOLHIDO sem Ingrax se mexe",
        ok,
        f"ST_SUBSTITUTO que nao acusaram: {len(st_nao_acusou)} (tem de ser 0)\n"
        f"INGRAX que nao acusaram: {len(ingrax_nao_acusou)} (tem de ser 0)\n"
        f"neutros que mexeram: {len(neutro_mexeu)} (tem de ser 0)",
    )


def cenario_3_identidade_no_banco(rep, cur):
    """VALOR_TOT_GERENCIAL do banco == formula recalculada com os insumos de
    hoje. E identidade, nao gabarito: nao envelhece quando entra nota nova."""
    linhas = _universo(cur)
    difs = []
    for cod, vl, mva, mod, forn, vg, ja_st in linhas:
        esperado = valor_gerencial(float(vl), float(mva or 0), mod,
                                   (forn or "").upper() == "INGRAX", bool(ja_st))
        if abs(float(vg) - esperado) > 0.005:
            difs.append((cod, float(vg), esperado))
    detalhe = f"{len(difs)} divergencia(s)"
    for cod, banco, formula in difs[:10]:
        detalhe += f"\n   SKU {cod}: banco {banco:.4f} != formula {formula:.4f}"
    rep.registrar(
        "VALOR_TOT_GERENCIAL do banco == formula do documento, recalculada SKU a SKU "
        f"({len(linhas)} linhas)",
        not difs,
        detalhe,
    )


def cenario_4_ingrax_nos_dois_lados(rep, cur):
    """O adicional de imagem existe nos dois lados (valor e custo) ou em
    nenhum. E o cenario que pega a leitura literal da Secao 2.1 do documento -
    ver o cabecalho de int_produto_custo.sql."""
    so_um_lado = cur.execute("""
        select count(*) from int_produto_custo
         where (valor_adicional_imagem  > 0 and custo_adicional_imagem <= 0)
            or (valor_adicional_imagem <= 0 and custo_adicional_imagem  > 0)""").fetchone()[0]
    normal_ingrax = cur.execute("""
        select count(*) from compras_pedido
         where upper(fornecedor) = 'INGRAX' and modalidade = 'NORMAL'""").fetchone()[0]
    rep.registrar(
        "adicional de imagem presente nos DOIS lados (valor e custo) ou em nenhum",
        so_um_lado == 0,
        f"{so_um_lado} SKU(s) com adicional so num dos lados (tem de ser 0)\n"
        f"{normal_ingrax} SKU(s) INGRAX sao modalidade NORMAL - e por causa deles que a\n"
        "Secao 2.1 do documento nao pode ser lida ao pe da letra (ver int_produto_custo.sql)",
    )


def cenario_5_st_ja_na_entrada(rep, cur):
    """A regra de 09/10/2026, com autoteste proprio.

    Duas afirmacoes, as duas invariantes (nao numero do dia):

      1. Nos itens marcados, o Valor Gerencial E o proprio valor da nota (mais
         o adicional de imagem, quando INGRAX): o ST ja esta dentro e nao se
         soma de novo.
      2. AUTOTESTE: aplicar a formula ANTIGA (somar o ST sempre) a esses itens
         diverge em TODOS eles. Se algum nao divergir, ou a marca nao esta
         pegando ou a correcao nao foi aplicada - os dois casos sao defeito.

    A marca vem da FONTE (PCEST), nao da nossa coluna - ver `valor_gerencial`.

    ⚠ Por que a regra nao e por DATA, que foi como o Diretor a descreveu:
    medido em 09/10/2026, a populacao com ST embutido aparece em TODOS os anos,
    inclusive 2024, 2025 e 2026 - nao houve mudanca de regime em 01/10/2022.
    Um corte naquela data acertaria 131 ativos, alteraria 40 que NAO tem ST
    embutido (erro para baixo no preco de venda) e deixaria 29 de fora.
    """
    linhas = [r for r in _universo(cur) if r[6]]
    marcados_st = [r for r in linhas if r[3] == "ST_SUBSTITUTO" and float(r[1]) > 0]

    erradas, nao_acusou = [], []
    for cod, vl, mva, mod, forn, vg, _ in marcados_st:
        vl, mva, vg = float(vl), float(mva or 0), float(vg)
        ingrax = (forn or "").upper() == "INGRAX"
        esperado = vl + (vl * (1 / PERC_NF - 1) if ingrax else 0.0)
        if abs(vg - esperado) > 0.005:
            erradas.append((cod, vg, esperado))
        # autoteste: a formula ANTIGA tem de divergir em todos
        antiga = valor_gerencial(vl, mva, mod, ingrax, st_ja_na_entrada=False)
        if abs(antiga - vg) <= 0.005:
            nao_acusou.append(cod)

    ok = bool(marcados_st) and not erradas and not nao_acusou
    detalhe = (f"{len(linhas)} SKU(s) marcados no total; {len(marcados_st)} sao "
               f"ST_SUBSTITUTO com nota > 0 (os unicos em que a marca muda algo -\n"
               f"          nas outras modalidades o termo de ST ja era zero)\n"
               f"          valor gerencial != valor da nota: {len(erradas)} (tem de ser 0)\n"
               f"          AUTOTESTE - formula antiga que NAO acusou: {len(nao_acusou)} (tem de ser 0)")
    for cod, banco, esp in erradas[:5]:
        detalhe += f"\n             SKU {cod}: banco {banco:.4f} != esperado {esp:.4f}"
    rep.registrar(
        "ST JA NA ENTRADA - nos itens marcados o Valor Gerencial e o proprio valor "
        "da nota, e a formula antiga diverge em TODOS eles",
        ok,
        detalhe,
    )


def contexto_custo_maior_que_valor(cur):
    """NAO e teste: e contagem informativa de um fato contra-intuitivo.

    CUSTO_ULT_ENT > VL_ENT_UNIT acontece, porque os dois sao campos
    INDEPENDENTES do Winthor (primeira linha do documento do Diretor). Quem
    olhar a tela e estranhar precisa achar isto aqui, em vez de abrir um
    chamado de defeito - e quem for escrever um teste do tipo "valor gerencial
    >= custo gerencial" precisa ver que ele seria FALSO."""
    total = cur.execute("""select count(*) from compras_pedido
                            where custo_ult_ent > vl_ent_unit + 0.01""").fetchone()[0]
    linhas = cur.execute("""
        select codigo, fornecedor, vl_ent_unit, custo_ult_ent
          from compras_pedido
         where custo_ult_ent > vl_ent_unit + 0.01
         order by (custo_ult_ent - vl_ent_unit) desc fetch first 5 rows only""").fetchall()
    print("\n" + "-" * 78)
    print("CONTEXTO (nao e falha): SKUs em que o CUSTO da ultima entrada e MAIOR que")
    print("o VALOR da nota. Os dois campos vem direto do Winthor, independentes um do")
    print("outro - nada no modelo garante a ordem.")
    print("-" * 78)
    print(f"  {total} SKU(s) no total. Os 5 maiores:")
    for cod, forn, vl, custo in linhas:
        print(f"    SKU {cod:>5} {str(forn):<12} valor {float(vl):10.2f}  custo {float(custo):10.2f}")


def main():
    rep = Reporter()
    con = conectar()
    cur = con.cursor()
    try:
        try:
            cur.execute("select valor_tot_gerencial from compras_produto_contexto "
                        "where rownum = 1")
        except oracledb.DatabaseError:
            print("VALOR_TOT_GERENCIAL nao existe neste schema.")
            print("Rode o dbt com o model novo antes (em producao, isso so vale apos o deploy).")
            return 1
        cenario_0_parametros(rep, cur)
        cenario_1_vetor_congelado(rep, cur)
        cenario_2_autoteste(rep, cur)
        cenario_3_identidade_no_banco(rep, cur)
        cenario_4_ingrax_nos_dois_lados(rep, cur)
        cenario_5_st_ja_na_entrada(rep, cur)
        contexto_custo_maior_que_valor(cur)
    finally:
        cur.close()
        con.close()
    return rep.resumo()


if __name__ == "__main__":
    raise SystemExit(main())
