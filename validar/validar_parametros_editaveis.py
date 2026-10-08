"""Valida a Etapa 19 (prompts/PROMPT_ETAPA_19_PARAMETROS_EDITAVEIS.md, Sec 6.3):
margem/MKP editaveis (item 1), cobertura alvo ajustavel (item 2) e filtro
"sem preco" (item 3). NAO CONSERTA NADA. Mede e reporta.

Esta etapa e' cliente puro nos itens 1 e 2 (web/src/precoEditavel.js e o
controle de cobertura em CatalogoPedido.jsx) e um `where` novo no item 3
(app/servicos/produto.py). Nenhum model dbt muda, nenhuma coluna de
COMPRAS_PEDIDO e recalculada por esta etapa. O que este script prova e' que
o GABARITO que o cliente tem de reproduzir - as formulas do Sec 3.2 e 4.1 do
prompt - de fato bate contra o banco, e que a inversa/ida-e-volta/particao
fecham pelos invariantes certos, nao por numeros congelados do dia
(CONTEXTO.md Sec 6.0.1, e a licao registrada no cabecalho de
`cenario_autoteste_defeito_injetado` de validar_cobertura_projetada.py: uma
contagem como "205 ativos sem preco" ou "516 SKUs de fator>1" muda a cada
`dbt run` e a cada cadastro novo - usar isso como criterio de aprovacao
reprova sozinho em semanas com o codigo correto).

SCHEMA - DOIS schemas, de proposito, e por que nao e' inconsistencia
------------------------------------------------------------------------------
Passos 1-5 (SQL em massa) rodam contra **COMPRAS** (producao), via
`validar_pedido.conectar`/`_ler_credencial_compras` (profile `compras` de
~/.dbt/profiles.yml) - e' o schema que a Sec 6.3 do prompt manda usar, e onde
os 8.944 SKUs materializados existem de verdade.

Passo 6 (spot-check) e' diferente por natureza: ele exercita **CODIGO**
(`produto.obter` + `contrato.produto`), nao SQL solto. Codigo roda contra o
schema que o SEU PROPRIO `.env` aponta - e o `.env` desta arvore
(`app_compras_v2_dev`) aponta para **COMPRAS_DEV**, nunca COMPRAS (comentario
no proprio arquivo: "Ambiente de DESENVOLVIMENTO ISOLADO - schema COMPRAS_DEV,
nunca COMPRAS"). Apontar o codigo desta arvore para COMPRAS por fora (via
ORA_* sobrescrito) cria uma combinacao - codigo da arvore de HOJE + schema de
producao, que pode estar um `dbt run` ATRAS do que o codigo espera - que nao
existe em NENHUM ambiente real: nem em dev (onde o codigo roda com o schema
que o acompanha) nem em producao (onde o codigo DAQUELA pasta, de um commit
mais antigo, e' o que de fato roda). Foi exatamente essa combinacao artificial
que, numa execucao anterior deste script, produziu um ORA-00904 em
CTX.VALOR_TOT_GERENCIAL que parecia "producao quebrada" e nao era - revisado
e corrigido em 08/10/2026. Por isso o passo 6 **nao** sobrescreve ORA_* - ele
deixa o import de `app.*` carregar o `.env` desta arvore (COMPRAS_DEV) do
jeito normal, igual a qualquer execucao de `teste.bat`.

⚠ ARMADILHA DE ORDEM NO DEPLOY (guardar, nao e' falha do validador): quando um
model que adiciona coluna nova (ex. VALOR_TOT_GERENCIAL) subir, o `dbt run`
em producao TEM que rodar ANTES do restart do servico NSSM `app_compras`. Se o
restart vier primeiro - servico novo, banco velho -, producao passa a ter
esse MESMO ORA-00904 para qualquer SKU, so' que de verdade. Este script nao
testa essa ordem (e' operacional, de `infra-windows`/quem publica), mas o
comentario fica registrado aqui porque foi o que o ORA-00904 acima quase fez
este validador reportar por engano como "producao quebrada".

Numeros de referencia do prompt (SKUs 9/11/28, PETRONAS 7305 etc., medidos
contra COMPRAS em 08/10/2026) aparecem no codigo/saida so' como anotacao
INFORMATIVA - o que o passo 6 de fato prova e' que os campos chegam ao JSON
IDENTICOS a' MESMA linha de COMPRAS_PEDIDO lida ao vivo, no MESMO schema que o
codigo usou (COMPRAS_DEV) - os valores numericos podem ser outros, e' o
schema isolado de desenvolvimento, com sua propria carga.

So' leitura, so' SELECT, nos dois schemas, em todo o script.

Uso:
    python validar/validar_parametros_editaveis.py
"""
from __future__ import annotations

import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TOLERANCIA = 0.01
TOLERANCIA_IDA_VOLTA = 1e-6

from validar import validar_pedido as _vp  # noqa: E402


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


# ──────────────────────────────────────────────── 1/2: dados + formulas ──
# Uma consulta so' para todo o catalogo (8.944 SKUs): tudo que entra na
# formula de margem (Sec 3.2) e na de cobertura (Sec 4.1), mais o que o
# filtro de preco (Sec 5.1) precisa. COMPRAS_PARAMETRO tem 1 linha (cross
# join nao multiplica nada); SEED_FORNECEDOR e' a fonte de COBERTURA_ALVO
# por departamento que int_produto_demanda.sql:127 usa, com o MESMO fallback
# (par.cobertura_alvo_padrao) - nao COMPRAS_IND_FORNECEDOR, que e' indice
# separado e pode ficar nulo (HITECH, Sec 2 do prompt).
_SQL_BULK = """
    select p.codigo, p.status, p.fornecedor, p.fator_exibicao,
           p.custo_tot_s_valor, p.custo_adicional_imagem, p.custo_tot_gerencial,
           p.icms_saida_ef, p.icms_sem_red, p.piscof_ef,
           p.margem_alvo, p.margem_alvo_varejo,
           p.pv_sug_st_s_valor_av, p.pv_sug_oficial_av, p.pv_sug_st_s_valor_var_av,
           p.media_janela, p.est_pend, p.sug_cobertura,
           p.pv_atacado, p.pv_varejo,
           par.comissao,
           nvl(f.cobertura_alvo, par.cobertura_alvo_padrao) as cobertura_alvo_resolvido
      from compras_pedido p
      cross join compras_parametro par
      left join seed_fornecedor f
        on upper(f.fornecedor) = upper(p.fornecedor)
"""


def _carregar_bulk(conn) -> list[dict]:
    cur = conn.cursor()
    cur.execute(_SQL_BULK)
    linhas = _dictfetch(cur)
    cur.close()
    return linhas


def _num(v) -> float | None:
    return None if v is None else float(v)


def _round_oracle(x: float) -> int:
    """ROUND do Oracle/Excel: "metade para longe do zero" - diferente de
    `round()` do Python, que e' banker's rounding (metade para o par mais
    proximo). Medido: SKU 3004 tem bruto=2618,5 - Python round() devolve
    2618 (para baixo, par), Oracle ROUND devolve 2619 (para longe do zero) -
    e' exatamente SUG_COBERTURA daquela linha. Usar round() builtin aqui
    teria introduzido divergencia ARTIFICIAL do proprio validador, nao do
    codigo validado (CONTEXTO.md regra 6, comentario de int_produto_demanda.
    sql:275-276 sobre ROUND ja registra o cuidado; o erro aqui seria so'
    Python vs Oracle, nao Math.round vs ROUND)."""
    import math
    # soma um epsilon minusculo para blindar contra representacao binaria de
    # ".5" ligeiramente abaixo (ex. 2618.4999999999995) sem mascarar casos
    # genuinamente diferentes de ".5".
    if x >= 0:
        return math.floor(x + 0.5 + 1e-9)
    return math.ceil(x - 0.5 - 1e-9)


def _calcular(linhas: list[dict]) -> list[dict]:
    """Para cada linha, calcula a inversa (real e sem comissao - defeito),
    a cobertura (real e multiplicada por fator - defeito) e guarda tudo em
    um dict novo, sem mutar a linha original."""
    calc = []
    for l in linhas:
        c = dict(l)
        custo_st = None
        if l["custo_tot_s_valor"] is not None:
            custo_st = float(l["custo_tot_s_valor"]) + float(l["custo_adicional_imagem"] or 0)
        custo_oficial = _num(l["custo_tot_gerencial"])

        icms_sem_red = _num(l["icms_sem_red"])
        icms_saida_ef = _num(l["icms_saida_ef"])
        piscof = _num(l["piscof_ef"])
        comissao = _num(l["comissao"])
        margem = _num(l["margem_alvo"])
        margem_var = _num(l["margem_alvo_varejo"])

        # ── inversa REAL (Sec 3.2) ──────────────────────────────────────
        def _preco(custo, icms, margem_alvo):
            if custo is None or icms is None or piscof is None or comissao is None or margem_alvo is None:
                return None
            denom = 1 - icms - piscof - comissao - margem_alvo
            if denom <= 0:
                return None
            return custo / denom

        c["preco_real_st_at"] = _preco(custo_st, icms_sem_red, margem)
        c["preco_real_oficial"] = _preco(custo_oficial, icms_saida_ef, margem)
        c["preco_real_st_var"] = _preco(custo_st, icms_sem_red, margem_var)

        # ── inversa com DEFEITO INJETADO: sem o termo de comissao ───────
        def _preco_sem_comissao(custo, icms, margem_alvo):
            if custo is None or icms is None or piscof is None or margem_alvo is None:
                return None
            denom = 1 - icms - piscof - margem_alvo  # falta "- comissao"
            if denom <= 0:
                return None
            return custo / denom

        c["preco_defeito_st_at"] = _preco_sem_comissao(custo_st, icms_sem_red, margem)

        # ── ida e volta: recalcula a MARGEM a partir do preco produzido ──
        if (c["preco_real_st_at"] not in (None, 0) and piscof is not None
                and comissao is not None and icms_sem_red is not None):
            c["margem_recalculada_st_at"] = (
                1 - piscof - comissao - icms_sem_red - custo_st / c["preco_real_st_at"]
            )
        else:
            c["margem_recalculada_st_at"] = None

        # ── cobertura (Sec 4.1) ──────────────────────────────────────────
        media = _num(l["media_janela"])
        est_pend = _num(l["est_pend"])
        alvo = _num(l["cobertura_alvo_resolvido"])
        if media is not None and est_pend is not None and alvo is not None:
            c["sug_recalculada"] = max(0.0, _round_oracle(media * alvo - est_pend))
        else:
            c["sug_recalculada"] = None

        fator = _num(l["fator_exibicao"]) or 1.0
        if c["sug_recalculada"] is not None:
            c["sug_defeito_fator"] = c["sug_recalculada"] * fator
        else:
            c["sug_defeito_fator"] = None

        calc.append(c)
    return calc


# ───────────────────────────────── 1: autoteste com defeito injetado ──


def cenario_autoteste_margem_sem_comissao(rep: Reporter, calc: list[dict]) -> None:
    """Prova que a inversa SEM o termo de comissao (custo/(1-icms-piscof-margem))
    ACUSA divergencia real contra PV_SUG_ST_S_VALOR_AV (que e' identica a'
    formula REAL, provado no passo 2).

    ⚠ Invariante por SINAL, nao por tolerancia fixa - e' o que nao envelhece
    nem depende do custo de cada SKU. Tirar "- comissao" do denominador
    AUMENTA o denominador (ja' que COMISSAO > 0 sempre, parametro unico de
    COMPRAS_PARAMETRO), logo o preco do defeito e' SEMPRE MENOR que o preco
    real, para todo SKU com custo > 0: preco_defeito < preco_real, estrito,
    em 100% das linhas calculaveis - isso vale mesmo quando a diferenca em
    R$ e' minuscula demais para passar de 0,01 (custo muito baixo). Exigir
    divergencia > TOLERANCIA em TODAS as linhas reprovaria por motivo errado
    nos SKUs de custo centavos - essa contagem e' impressa a parte, so' como
    leitura do dia."""
    aplicaveis = [
        c for c in calc
        if c["preco_real_st_at"] is not None and c["preco_defeito_st_at"] is not None
        and c["preco_real_st_at"] > 0
    ]
    sempre_menor = [c for c in aplicaveis if c["preco_defeito_st_at"] < c["preco_real_st_at"] - 1e-9]
    visivelmente_divergentes = [
        c for c in aplicaveis if abs(c["preco_defeito_st_at"] - c["pv_sug_st_s_valor_av"]) > TOLERANCIA
    ]

    ok = len(aplicaveis) > 0 and len(sempre_menor) == len(aplicaveis)
    rep.registrar(
        f"AUTOTESTE 1 - inversa de margem SEM comissao (defeito injetado) produz preco SEMPRE "
        f"MENOR que o preco real/PV_SUG_ST_S_VALOR_AV, em TODAS as {len(aplicaveis)} linhas "
        "calculaveis (consequencia direta de COMISSAO > 0: tirar o termo so' pode aumentar o "
        "denominador e reduzir o preco)",
        ok,
        f"aplicaveis={len(aplicaveis)}; sempre_menor={len(sempre_menor)} (tem de ser igual a "
        f"aplicaveis); leitura do dia - visivelmente divergentes (> R$ {TOLERANCIA}): "
        f"{len(visivelmente_divergentes)} de {len(aplicaveis)} (prompt Sec 3.2 cita 8.759 "
        "linhas aplicaveis no total, nao esta contagem)",
    )
    if not ok:
        print("          -- validador reprovando de proposito: a formula sem comissao tem de "
              "produzir preco menor que o real em TODA linha. Se isso nao acontecer, o defeito "
              "nao foi reproduzido --")
    if visivelmente_divergentes:
        piores = sorted(
            visivelmente_divergentes,
            key=lambda c: -abs(c["preco_defeito_st_at"] - c["pv_sug_st_s_valor_av"]),
        )[:3]
        print("          3 maiores divergencias visiveis (sem comissao vs PV_SUG_ST_S_VALOR_AV):")
        for c in piores:
            print(f"            SKU {c['codigo']}: sem_comissao={c['preco_defeito_st_at']:.4f}  "
                  f"PV_SUG={c['pv_sug_st_s_valor_av']:.4f}")


def cenario_autoteste_cobertura_vezes_fator(rep: Reporter, calc: list[dict]) -> None:
    """Prova que multiplicar a sugestao de cobertura (ja correta) por
    FATOR_EXIBICAO ACUSA divergencia contra SUG_COBERTURA.

    ⚠ Invariante, nao numero congelado (mesma licao do precedente, Etapa 18):
    entre os SKUs de fator > 1, so' divergem os que tem sugestao REAL > 0 -
    multiplicar zero por qualquer fator continua zero, entao nao ha' como
    "acusar" ali. Medido hoje: 516 SKUs com fator > 1, dos quais 46 tem
    sugestao > 0 (os outros 470 ja estao supridos - sugestao zero - e por
    isso nao servem de prova, nao porque o defeito deixou de existir).

    O criterio que nao envelhece:
      1. TODO SKU de fator > 1 com sug_recalculada > 0 diverge ao multiplicar.
      2. NENHUM SKU de fator == 1 diverge (grupo de controle).
      3. Existe pelo menos um SKU nessas condicoes - senao o autoteste nao
         testou nada."""
    com_fator = [c for c in calc if (c["fator_exibicao"] or 1) > 1 and c["sug_recalculada"] is not None]
    com_fator_positivos = [c for c in com_fator if c["sug_recalculada"] > 0]
    divergentes = [c for c in com_fator_positivos if abs(c["sug_defeito_fator"] - c["sug_recalculada"]) > TOLERANCIA]

    fator_um = [c for c in calc if (c["fator_exibicao"] or 1) == 1 and c["sug_recalculada"] is not None]
    divergentes_controle = [c for c in fator_um if abs(c["sug_defeito_fator"] - c["sug_recalculada"]) > TOLERANCIA]

    ok = (
        len(com_fator_positivos) > 0
        and len(divergentes) == len(com_fator_positivos)
        and len(divergentes_controle) == 0
    )
    rep.registrar(
        f"AUTOTESTE 2 - sugestao de cobertura x FATOR_EXIBICAO DIVERGE de SUG_COBERTURA em "
        f"TODOS os {len(com_fator_positivos)} SKUs de fator>1 com sugestao>0 (de {len(com_fator)} "
        f"SKUs de fator>1 no total), e em NENHUM SKU de fator==1 ({len(fator_um)} testados)",
        ok,
        f"fator>1: {len(com_fator)} total, {len(com_fator_positivos)} com sugestao>0, "
        f"{len(divergentes)} divergiram (tem de ser igual a com sugestao>0); "
        f"fator==1: {len(divergentes_controle)} divergiram (tem de ser 0)",
    )
    if not ok:
        print("          -- validador reprovando de proposito: multiplicar por FATOR_EXIBICAO>1 "
              "tem de divergir onde a sugestao real e' > 0 --")
    if divergentes:
        piores = sorted(divergentes, key=lambda c: -abs(c["sug_defeito_fator"] - c["sug_recalculada"]))[:3]
        print("          3 maiores divergencias (x fator vs SUG_COBERTURA):")
        for c in piores:
            print(f"            SKU {c['codigo']} (fator {c['fator_exibicao']:.0f}): "
                  f"x_fator={c['sug_defeito_fator']:.2f}  real={c['sug_recalculada']:.2f}")


# ──────────────────────────────────── 2: inversa de margem, real ──


def cenario_inversa_margem_real(rep: Reporter, calc: list[dict]) -> None:
    """custo/(1-icms-piscof-comissao-margem_alvo) x PV_SUG_*_AV, tolerancia
    0,01, nos tres cenarios do Sec 3.2/6.3 ponto 2: ST s/Valor atacado,
    Oficial atacado, ST s/Valor varejo."""
    casos = [
        ("ST s/Valor (atacado)", "preco_real_st_at", "pv_sug_st_s_valor_av"),
        ("Oficial (atacado)", "preco_real_oficial", "pv_sug_oficial_av"),
        ("ST s/Valor (varejo)", "preco_real_st_var", "pv_sug_st_s_valor_var_av"),
    ]
    for nome, campo_calc, campo_coluna in casos:
        aplicaveis = [c for c in calc if c[campo_calc] is not None and c[campo_coluna] is not None]
        divergentes = [c for c in aplicaveis if abs(c[campo_calc] - c[campo_coluna]) > TOLERANCIA]
        rep.registrar(
            f"inversa de margem [{nome}] bate com {campo_coluna.upper()}, tolerancia {TOLERANCIA}, "
            f"em {len(aplicaveis)} linha(s) calculaveis",
            not divergentes,
            f"{len(aplicaveis) - len(divergentes)} de {len(aplicaveis)} linhas fecham; "
            f"{len(divergentes)} divergencia(s)"
            + ("" if not divergentes else ": " + str(
                [(c["codigo"], round(c[campo_calc], 4), round(c[campo_coluna], 4)) for c in divergentes[:3]])),
        )


# ─────────────────────────────────────────────── 3: ida e volta ──


def cenario_ida_e_volta(rep: Reporter, calc: list[dict]) -> None:
    """Aplicar a formula da margem (calcMargem) ao preco que a inversa
    produziu devolve a margem de partida (MARGEM_ALVO), tolerancia 1e-6 -
    prova que os dois campos (preco e margem) nao divergem entre si, no
    cenario ST s/Valor atacado."""
    aplicaveis = [c for c in calc if c["margem_recalculada_st_at"] is not None and c["margem_alvo"] is not None]
    divergentes = [
        c for c in aplicaveis
        if abs(c["margem_recalculada_st_at"] - float(c["margem_alvo"])) > TOLERANCIA_IDA_VOLTA
    ]
    rep.registrar(
        f"ida e volta: calcMargem(precoDeMargem(margem_alvo)) == margem_alvo, tolerancia "
        f"{TOLERANCIA_IDA_VOLTA}, em {len(aplicaveis)} linha(s) (cenario ST s/Valor atacado)",
        not divergentes,
        f"{len(aplicaveis) - len(divergentes)} de {len(aplicaveis)} fecham; {len(divergentes)} divergencia(s)"
        + ("" if not divergentes else ": " + str(
            [(c["codigo"], c["margem_recalculada_st_at"], float(c["margem_alvo"])) for c in divergentes[:3]])),
    )


# ───────────────────────────────── 4: sugestao de cobertura + identidade ──


def cenario_sugestao_cobertura(rep: Reporter, calc: list[dict]) -> None:
    """greatest(0, round(media_janela*nvl(cobertura_alvo,2) - est_pend, 0)) x
    SUG_COBERTURA - espera-se 8.944 de 8.944 (recalculado, nao copiado).
    Depois, a identidade do topo do prompt: (est_pend+sug)/media_janela ==
    alvo, para todo SKU com media_janela>0 e sugestao NAO clampeada em zero
    (quando clampeia, a identidade nao vale por desenho - reportado a' parte,
    nao como falha).

    ⚠ A identidade nao fecha com tolerancia FIXA 0,01: `sug` e' um INTEIRO
    (round de media*alvo-est_pend), entao o erro de arredondamento pode
    chegar a 0,5 unidade, que vira 0,5/media_janela MESES na divisao - grande
    o bastante para estourar 0,01 em qualquer SKU de giro baixo (media<50),
    sem que isso seja defeito nenhum: e' a propria natureza de arredondar
    para um numero inteiro de caixas. O limite que de fato e' invariante,
    bytes a byte - |projetada-alvo| <= 0,5/media_janela, sempre, porque
    |sug-bruto|<=0,5 por construcao do arredondamento - e' esse limite que
    o passo usa, com uma folga de 1e-6 so' para ruido de ponto flutuante."""
    aplicaveis = [c for c in calc if c["sug_recalculada"] is not None and c["sug_cobertura"] is not None]
    divergentes = [c for c in aplicaveis if abs(c["sug_recalculada"] - float(c["sug_cobertura"])) > TOLERANCIA]
    rep.registrar(
        f"SUG_COBERTURA recalculada (greatest(0,round(media_janela*alvo-est_pend,0))) bate com "
        f"a coluna, tolerancia {TOLERANCIA}, em {len(aplicaveis)} de {len(calc)} linha(s)",
        not divergentes,
        f"{len(aplicaveis) - len(divergentes)} de {len(aplicaveis)} fecham; {len(divergentes)} divergencia(s)"
        + ("" if not divergentes else ": " + str(
            [(c["codigo"], c["sug_recalculada"], float(c["sug_cobertura"])) for c in divergentes[:3]])),
    )

    # Identidade: so' vale onde a sugestao NAO foi clampeada em zero, isto e',
    # onde media*alvo - est_pend > 0 de fato (sem o greatest). Clampeados sao
    # contados a' parte, informativamente.
    nao_clampeados = []
    clampeados = []
    for c in calc:
        media = c["media_janela"]
        est_pend = c["est_pend"]
        alvo = c["cobertura_alvo_resolvido"]
        if media is None or est_pend is None or alvo is None or float(media) <= 0:
            continue
        media = float(media)
        est_pend = float(est_pend)
        alvo = float(alvo)
        bruto = media * alvo - est_pend
        if _round_oracle(bruto) > 0:
            nao_clampeados.append((c, media, est_pend, alvo))
        else:
            clampeados.append(c)

    divergentes_identidade = []
    maior_folga = 0.0
    for c, media, est_pend, alvo in nao_clampeados:
        sug = c["sug_recalculada"]
        projetada = (est_pend + sug) / media
        limite = 0.5 / media + 1e-6  # folga de arredondamento (ver docstring)
        erro = abs(projetada - alvo)
        maior_folga = max(maior_folga, erro)
        if erro > limite:
            divergentes_identidade.append((c["codigo"], projetada, alvo, limite))

    rep.registrar(
        "identidade (est_pend+sug)/media_janela == alvo, tolerancia 0,5/media_janela (limite de "
        f"arredondamento do inteiro `sug`, nao 0,01 fixo - ver docstring), em TODOS os "
        f"{len(nao_clampeados)} SKU(s) com media_janela>0 e sugestao NAO clampeada em zero "
        f"({len(clampeados)} SKU(s) clampeados ficam de fora por desenho, reportados a parte)",
        not divergentes_identidade,
        f"{len(nao_clampeados) - len(divergentes_identidade)} de {len(nao_clampeados)} fecham; "
        f"{len(divergentes_identidade)} divergencia(s); maior erro observado={maior_folga:.6f} meses"
        + ("" if not divergentes_identidade else ": " + str(divergentes_identidade[:3])),
    )


# ──────────────────────────────────────── 5: particao do filtro de preco ──


def cenario_particao_filtro_preco(rep: Reporter, conn) -> None:
    """com + sem = total, por status, recalculado agora (nao copiado do
    prompt - hoje 205 ativos sem preco, mas essa contagem envelhece)."""
    cur = conn.cursor()
    cur.execute(
        """
        select p.status,
               sum(case when nvl(p.pv_atacado,0) > 0 then 1 else 0 end) as com_preco,
               sum(case when nvl(p.pv_atacado,0) <= 0 then 1 else 0 end) as sem_preco,
               count(*) as total
          from compras_pedido p
         group by p.status
         order by p.status
        """
    )
    linhas = _dictfetch(cur)
    cur.close()

    falhas = []
    print("          particao recalculada agora, por status:")
    for l in linhas:
        com = int(l["com_preco"])
        sem = int(l["sem_preco"])
        total = int(l["total"])
        fecha = (com + sem == total)
        print(f"            {l['status']}: com={com}  sem={sem}  total={total}  (com+sem=total: {fecha})")
        if not fecha:
            falhas.append(f"{l['status']}: com({com})+sem({sem}) != total({total})")

    total_geral = sum(int(l["total"]) for l in linhas)
    com_geral = sum(int(l["com_preco"]) for l in linhas)
    sem_geral = sum(int(l["sem_preco"]) for l in linhas)
    print(f"            TODOS: com={com_geral}  sem={sem_geral}  total={total_geral}")

    rep.registrar(
        "particao do filtro de preco (com + sem = total), por status E no total, recalculada agora",
        not falhas and (com_geral + sem_geral == total_geral),
        "; ".join(falhas) or f"todas as particoes fecham (geral: com={com_geral}, sem={sem_geral}, total={total_geral})",
    )


# ────────────────────────────────── 6: spot-check pelo codigo de verdade ──

SKUS_SPOT_CHECK = [9, 11, 28]

# Referencia INFORMATIVA do prompt (Sec 3.2/6.3, medida contra COMPRAS em
# 08/10/2026) - impressa so' para contexto de quem le. O passo 6 roda contra
# COMPRAS_DEV (ver docstring do modulo), que tem carga PROPRIA: estes numeros
# quase certamente NAO vao bater, e isso nao e' falha - a comparacao que
# importa e' contra a linha ao vivo do MESMO schema, feita abaixo.
REFERENCIA_PROMPT_2026_10_08 = {
    9: {"custo_st": 237.9053, "icms_sem_red": 0.0, "pis_cofins_ef": 0.0925, "pv_sug_st_s_valor_av": 356.4124},
}


def cenario_spot_check_codigo_real(rep: Reporter) -> None:
    """Chama produto.obter + contrato.produto (CODIGO desta arvore, nao SQL
    reescrito) para os SKUs 9, 11 e 28, e confere que cenariosAtacado[st_valor]
    .custo, .icmsEf, pisCofinsEfetivo, margemAlvo e .pvSugeridoAV chegam ao
    JSON identicos a' MESMA linha de COMPRAS_PEDIDO lida ao vivo - prova que a
    conta do front opera sobre os campos que de fato recebe (Sec 6.3 ponto 6
    do prompt).

    ⚠ Roda contra COMPRAS_DEV, nao COMPRAS (ver "SCHEMA" no cabecalho do
    modulo) - NAO sobrescreve ORA_*, deixa `app.config._carregar_env()` ler o
    `.env` desta arvore do jeito normal. Os valores que batem sao os da MESMA
    linha de COMPRAS_PEDIDO lida ao vivo NESTE schema - os numeros do prompt
    (REFERENCIA_PROMPT_2026_10_08) sao so' leitura informativa, nao gabarito
    desta comparacao (licao de sempre: invariante/vivo, nao numero do dia)."""
    from app.api import contrato  # noqa: E402  (import tardio - carrega .env da arvore aqui)
    from app.core import database  # noqa: E402
    from app.servicos import produto  # noqa: E402

    falhas = []
    for codigo in SKUS_SPOT_CHECK:
        esperado = database.consultar_um(
            "select custo_tot_s_valor, custo_adicional_imagem, icms_sem_red, piscof_ef, "
            "margem_alvo, pv_sug_st_s_valor_av from compras_pedido where codigo = :codigo",
            {"codigo": codigo},
        )
        if not esperado:
            falhas.append(f"SKU {codigo}: nao encontrado em COMPRAS_PEDIDO (COMPRAS_DEV)")
            continue
        custo_esperado = float(esperado["custo_tot_s_valor"] or 0) + float(esperado["custo_adicional_imagem"] or 0)

        try:
            linha = produto.obter(codigo)
        except Exception as exc:  # noqa: BLE001 - reportar, nao mascarar
            msg = str(exc)
            if "ORA-00904" in msg:
                falhas.append(
                    f"SKU {codigo}: produto.obter levantou ORA-00904 ({msg}) — RODE O DBT EM DEV "
                    "(schema COMPRAS_DEV): o codigo desta arvore ja seleciona uma coluna que o "
                    "schema ainda nao tem. Nao e' defeito do validador nem de producao."
                )
            else:
                falhas.append(f"SKU {codigo}: produto.obter levantou {type(exc).__name__}: {exc}")
            continue
        if linha is None:
            falhas.append(f"SKU {codigo}: produto.obter devolveu None")
            continue
        corpo = contrato.produto(linha)
        st_valor = next(cen for cen in corpo["cenariosAtacado"] if cen["id"] == "st_valor")

        checagens = [
            ("cenariosAtacado[st_valor].custo", st_valor["custo"], custo_esperado),
            ("cenariosAtacado[st_valor].icmsEf", st_valor["icmsEf"], esperado["icms_sem_red"]),
            ("pisCofinsEfetivo", corpo["pisCofinsEfetivo"], esperado["piscof_ef"]),
            ("margemAlvo", corpo["margemAlvo"], esperado["margem_alvo"]),
            ("cenariosAtacado[st_valor].pvSugeridoAV", st_valor["pvSugeridoAV"], esperado["pv_sug_st_s_valor_av"]),
        ]
        for campo, obtido, esperado_valor in checagens:
            ev = float(esperado_valor) if esperado_valor is not None else None
            ob = float(obtido) if obtido is not None else None
            if ev is None and ob is None:
                continue
            if ev is None or ob is None or abs(ob - ev) > TOLERANCIA:
                falhas.append(f"SKU {codigo}.{campo}: API={ob}, COMPRAS_PEDIDO (COMPRAS_DEV) ao vivo={ev}")

        ref = REFERENCIA_PROMPT_2026_10_08.get(codigo)
        print(f"          SKU {codigo} (COMPRAS_DEV, ao vivo): custo={st_valor['custo']}  "
              f"icmsEf={st_valor['icmsEf']}  pisCofinsEfetivo={corpo['pisCofinsEfetivo']}  "
              f"margemAlvo={corpo['margemAlvo']}  pvSugeridoAV={st_valor['pvSugeridoAV']}"
              + (f"   [referencia informativa do prompt/COMPRAS, 08/10/2026: custo={ref['custo_st']}, "
                 f"pvSugeridoAV={ref['pv_sug_st_s_valor_av']} - schemas diferentes, nao precisa bater]"
                 if ref else ""))

    rep.registrar(
        "codigo desta arvore (produto.obter + contrato.produto, contra COMPRAS_DEV) devolve "
        "custo/icmsEf/pisCofinsEfetivo/margemAlvo/pvSugeridoAV (cenario ST s/Valor) identicos a' "
        f"MESMA linha de COMPRAS_PEDIDO lida ao vivo, para os {len(SKUS_SPOT_CHECK)} SKUs de "
        "referencia (9, 11, 28)",
        not falhas,
        "\n".join(falhas) or "nenhuma divergencia",
    )


def main() -> int:
    rep = Reporter()
    print(f"Conectando (reaproveitando validar_pedido.conectar, profile 'compras' de {_vp.PROFILES_PATH})...")
    conn = _vp.conectar(_vp.ORACLE_CLIENT_LIB_DIR, _vp.PROFILES_PATH)
    print("Conectado.\n")

    linhas = _carregar_bulk(conn)
    calc = _calcular(linhas)
    rep.registrar(
        f"COMPRAS_PEDIDO x COMPRAS_PARAMETRO x SEED_FORNECEDOR devolveu {len(linhas)} SKU(s) "
        "(esperado ~8.944)",
        len(linhas) > 8000,
        f"{len(linhas)} linha(s)",
    )
    print()

    print("── Passo 1: autoteste com defeito injetado ──────────────────────")
    cenario_autoteste_margem_sem_comissao(rep, calc)
    print()
    cenario_autoteste_cobertura_vezes_fator(rep, calc)
    print()

    print("── Passo 2: inversa de margem, real ──────────────────────────────")
    cenario_inversa_margem_real(rep, calc)
    print()

    print("── Passo 3: ida e volta ──────────────────────────────────────────")
    cenario_ida_e_volta(rep, calc)
    print()

    print("── Passo 4: sugestao de cobertura + identidade ───────────────────")
    cenario_sugestao_cobertura(rep, calc)
    print()

    print("── Passo 5: particao do filtro de preco ──────────────────────────")
    cenario_particao_filtro_preco(rep, conn)
    print()

    print("── Passo 6: spot-check pelo codigo de verdade ────────────────────")
    cenario_spot_check_codigo_real(rep)

    conn.close()
    return rep.resumo()


if __name__ == "__main__":
    sys.exit(main())
