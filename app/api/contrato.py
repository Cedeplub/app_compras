"""Tradução COMPRAS_* → vocabulário do protótipo (`PROTOTIPO.md` §3/§4).

Este é o ÚNICO lugar onde os dois vocabulários se encontram. O SQL fala
`custo_tot_s_valor`; o React fala `custoStValor`. Espalhar essa tradução pelas
rotas faria com que renomear uma coluna do dbt exigisse caçar o nome novo em
cinco arquivos.

Campos que o protótipo tem e o banco ainda não têm saem como `None`, com o
motivo anotado — nunca preenchidos com um valor plausível. Um `null` explícito
a tela sabe tratar; um número inventado ela exibe com a mesma confiança de um
número verdadeiro.
"""
from __future__ import annotations

import datetime as dt
from typing import Any

# ─────────────────────────────────────────────────────────────────────────────
# Cenários de margem.
#
# O protótipo descobre custo e margem de cada cenário com um if/else inferido
# por comparação empírica de números (PROTOTIPO.md §5/§9). Aqui não se infere
# nada: a margem de cada cenário já está materializada coluna a coluna pelo dbt,
# e o custo e a alíquota são lidos de `int_produto_preco_sugerido.sql` — o mesmo
# lugar de onde saem os PV_SUG_*. É a regra de ouro do projeto aplicada à letra:
# a tela não recalcula o que o modelo já calculou, e quando precisa de um
# ingrediente, pega o ingrediente que o modelo usou.
#
# Resumo do que o modelo faz (verificado no SQL, não deduzido):
#
#   cenário    | custo                                    | ICMS de saída
#   -----------|------------------------------------------|----------------
#   ST s/Valor | custo_tot_s_valor + ajuste_imagem         | icms_sem_red
#   Oficial    | custo_tot_gerencial                       | icms_saida_ef
#   Sem Redução| custo_tot_gerencial                       | icms_sem_red
#
# Duas leituras que decorrem daí e valem dizer em voz alta:
#   * Oficial e Sem Redução usam O MESMO custo. O que os separa é a alíquota —
#     redução de base mexe no imposto de SAÍDA, não no custo de entrada.
#   * `custo_tot_gerencial` NÃO é sinônimo de `custo_tot_oficial`, ao contrário
#     do que o protótipo concluiu do mock dele (§9): medido, gerencial =
#     oficial + ajuste_imagem em 100% dos SKUs. Onde o ajuste existe (226 SKUs,
#     todos INGRAX), a diferença chega a R$ 567.
# ─────────────────────────────────────────────────────────────────────────────

CENARIOS_ATACADO = ("st_valor", "oficial", "sem_red")
# Varejo não tem "Oficial": a redução de base é exclusiva das filiais 02/09
# (PROTOTIPO.md §5). Omitir a opção é a própria implementação da regra.
CENARIOS_VAREJO = ("st_valor", "sem_red")

ROTULO_CENARIO = {
    "st_valor": "ST s/Valor",
    "oficial": "Oficial",
    "sem_red": "Sem Redução",
}


def _f(valor: Any) -> float | None:
    """Oracle devolve Decimal; JSON não tem Decimal."""
    return None if valor is None else float(valor)


def _data(valor: Any) -> str | None:
    if valor is None:
        return None
    if isinstance(valor, (dt.datetime, dt.date)):
        return valor.strftime("%Y-%m-%d")
    return str(valor)


# ⚠ CORRIGIDO EM 02/09/2026. A versão anterior inferia o custo de cada cenário
# a partir da lógica do protótipo (um `if` por modalidade) e estava ERRADA nos
# três cenários. O certo foi lido de `int_produto_preco_sugerido.sql`, que é
# quem de fato calcula os PV_SUG_* — a tela precisa mostrar o MESMO custo que
# gerou a sugestão, senão o MKP e a margem exibidos não fecham com o preço
# sugerido ao lado, e ninguém descobre por quê.
#
# Medido: `custo_tot_gerencial = custo_tot_oficial + custo_adicional_imagem` em
# 100% dos 8.635 SKUs com custo. O ajuste de imagem (o 80/20 do Ingrax) é
# diferente de zero em 226 SKUs, todos INGRAX, chegando a R$ 567 — que era
# exatamente o tanto que o custo exibido estava abaixo do usado no cálculo.
_CUSTO_DO_CENARIO = {
    # ST s/Valor: custo sem ST, MAIS o ajuste de imagem.
    "st_valor": lambda p: _soma(p, "custo_tot_s_valor", "custo_adicional_imagem"),
    # Oficial e Sem Redução usam o mesmo custo — o gerencial, que já inclui o
    # ajuste. O que os separa é a ALÍQUOTA, não o custo (ver _ICMS_DO_CENARIO).
    "oficial": lambda p: _f(p.get("custo_tot_gerencial")),
    "sem_red": lambda p: _f(p.get("custo_tot_gerencial")),
}

# Qual alíquota de ICMS de saída cada cenário aplica. A tela usa isto para
# recalcular a margem do preço DIGITADO a cada tecla — sem ela, a margem do
# preço novo sairia com uma alíquota e a do sugerido com outra, lado a lado.
_ICMS_DO_CENARIO = {
    "st_valor": "icms_sem_red",
    "oficial": "icms_saida_ef",
    "sem_red": "icms_sem_red",
}


def _soma(p: dict, *colunas: str) -> float | None:
    """Soma tratando ausência como zero, mas devolvendo None se TUDO for nulo.

    `custo_adicional_imagem` é nulo/zero em 8.403 dos 8.629 SKUs; somar como
    zero é o comportamento certo. Já um custo base nulo não pode virar 0,00 na
    tela — 0,00 diz "de graça", e nulo diz "não sei".
    """
    valores = [p.get(c) for c in colunas]
    if all(v is None for v in valores):
        return None
    return float(sum(v for v in valores if v is not None))


def _custo_do_cenario(p: dict, cenario: str) -> float | None:
    return _CUSTO_DO_CENARIO[cenario](p)


def _cenario_pior(p: dict) -> dict:
    """O cenário de MENOR margem do produto — o custo mais alto, no ICMS cheio.

    Serve o aviso de margem mínima do item 4 do Diretor (09/10/2026) na
    aplicação em LOTE. A tela, que recebe a lista inteira de cenários, acha o
    pior pelo caminho direto: calcula a margem em cada um e pega a menor
    (`margemPiorCenario`, precoEditavel.js). Aqui a lista não viaja — seriam
    cinco objetos a mais em cada um dos 4.552 itens do filtro — então o pior
    vem resolvido, e a redução abaixo é o que torna as duas resoluções
    equivalentes.

    ── Por que dá para resolver sem saber o preço ───────────────────────────
    A margem é `K − icmsEf − custo/preço`, com K igual em todos os cenários.
    Comparando dois a dois:

      * Oficial × Sem Redução: MESMO custo (`custo_tot_gerencial`), então
        quem decide é a alíquota. `icms_saida_ef <= icms_sem_red` sempre —
        redução de base só diminui o imposto. Medido: 0 violações em 4.553
        ativos, e o teste `compras_icms_saida_nao_supera_sem_reducao` guarda
        isso. Logo Oficial NUNCA é o pior.
      * ST s/Valor × Sem Redução: MESMA alíquota (os dois usam `icms_sem_red`,
        ver _ICMS_DO_CENARIO), então quem decide é o custo — e a comparação
        de custos não depende do preço.

    Sobra: pior = maior custo entre os dois, com `icms_sem_red`. Sem preço na
    conta, e por isso resolvível no servidor.

    ⚠ NÃO é `margem_sem_red`, apesar de `int_produto_margem.sql:244` chamar
    aquela coluna de "o PIOR cenario de atacado". Medido em 09/10/2026: ST
    s/Valor dá margem MENOR em 3.014 dos 4.337 ativos com os três cenários,
    com diferença de até 71,5 pontos — porque `custo_tot_s_valor +
    ajuste_imagem` supera `custo_tot_gerencial` em 3.015 ativos.

    Vale para as DUAS praças: varejo não tem Oficial, e o par que sobra é
    exatamente o mesmo.
    """
    custos = [_custo_do_cenario(p, "st_valor"), _custo_do_cenario(p, "sem_red")]
    validos = [c for c in custos if c is not None]
    return {
        "custo": max(validos) if validos else None,
        "icmsEf": _f(p.get("icms_sem_red")),
    }


def _cenario_real(modalidade: str | None) -> str | None:
    """Qual cenário de fato se aplica ao produto hoje.

    ST_SUBSTITUTO → ST s/Valor; NORMAL → Sem Redução (PROTOTIPO.md §5).
    ST_RECOLHIDO não tem cenário real — o protótipo cai no primeiro item do
    array quando precisa de um. Aqui devolvemos `None` e deixamos a decisão de
    apresentação para a tela, em vez de esconder a ausência num fallback.
    """
    m = (modalidade or "").upper()
    if m == "ST_SUBSTITUTO":
        return "st_valor"
    if m == "NORMAL":
        return "sem_red"
    return None


def _cenarios(p: dict, praca: str) -> list[dict]:
    sug = "_var" if praca == "varejo" else ""
    ids = CENARIOS_VAREJO if praca == "varejo" else CENARIOS_ATACADO
    real = _cenario_real(p.get("modalidade"))

    return [
        {
            "id": cid,
            "rotulo": ROTULO_CENARIO[cid],
            "real": cid == real,
            "custo": _custo_do_cenario(p, cid),
            "icmsEf": _f(p.get(_ICMS_DO_CENARIO[cid])),
            "margemAtual": _f(p.get(COLUNA_MARGEM[(cid, praca)])),
            "pvSugeridoAV": _f(p.get(f"pv_sug_{_chave_sug(cid)}{sug}_av")),
            "pvSugeridoAP": _f(p.get(f"pv_sug_{_chave_sug(cid)}{sug}_ap")),
        }
        for cid in ids
    ]


def _cenario_visivel(p: dict, praca: str, escolhido: str | None) -> str:
    """Qual cenário de fato vale para este item nesta praça.

    ⚠ Replica EXATAMENTE `cenarioVisivel` de web/src/precificacao.js:
    o escolhido, senão o REAL do produto, senão o primeiro da lista. Varejo
    não tem "Oficial", então escolher Oficial e olhar o varejo cai no
    fallback — e é por isso que a regra não pode ser "usa o escolhido e
    pronto".

    Existe para a aplicação em LOTE precificar com o mesmo custo e a mesma
    alíquota que a célula mostra. Duas resoluções do cenário é como nasce uma
    tela que sugere um preço e exibe outro — o defeito do protótipo que
    `precificacao.js:52-57` documenta.
    """
    ids = CENARIOS_VAREJO if praca == "varejo" else CENARIOS_ATACADO
    if escolhido in ids:
        return escolhido
    real = _cenario_real(p.get("modalidade"))
    return real if real in ids else ids[0]


def base_precificacao(linhas: list[dict], cenario_sel: str | None) -> dict:
    """Os insumos de preço do filtro inteiro, para a aplicação em lote.

    Payload deliberadamente mínimo — ver `produto._COLUNAS_PRECIFICACAO_LOTE`.
    Cada item traz o custo e a alíquota JÁ RESOLVIDOS por praça, para o
    cliente não ter de repetir a resolução (e errar nela).

    `custo` nulo é "não dá para precificar este": a tela conta esses à parte
    e os PULA, que é o que o Diretor pediu — "pular itens sem custo".
    """
    itens = []
    for p in linhas:
        cen_at = _cenario_visivel(p, "atacado", cenario_sel)
        cen_var = _cenario_visivel(p, "varejo", cenario_sel)
        itens.append({
            "codigo": int(p["codigo"]),
            "pisCofinsEfetivo": _f(p.get("piscof_ef")),
            "custoAT": _custo_do_cenario(p, cen_at),
            "icmsEfAT": _f(p.get(_ICMS_DO_CENARIO[cen_at])),
            "custoVAR": _custo_do_cenario(p, cen_var),
            "icmsEfVAR": _f(p.get(_ICMS_DO_CENARIO[cen_var])),
            "precoDecididoAtacadoAV": _f(p.get("alt_pv_at_av")),
            "precoDecididoVarejoAV": _f(p.get("alt_pv_var_av")),
            # O pior cenário, para o aviso de margem mínima do lote (item 4 do
            # Diretor): um só para as duas praças — ver `_cenario_pior`. Vai
            # na forma `{custo, icmsEf}` de propósito, a MESMA de `_cenarios`,
            # para a tela alimentar `margemPiorCenario` com a lista de uma
            # linha e usar a mesma função dos campos digitados.
            "cenarioPior": _cenario_pior(p),
        })
    return {"itens": itens, "total": len(itens)}


def _chave_sug(cenario: str) -> str:
    return {"st_valor": "st_s_valor", "oficial": "oficial", "sem_red": "sem_red"}[cenario]


# O nome da coluna de margem não segue o id do cenário (`st_valor` mora em
# `MARGEM_ST_S_VALOR`), então o de-para fica explícito aqui em vez de ser
# montado com f-string condicional — que é fácil de escrever e difícil de ler.
# Público de propósito: `app/servicos/produto.py` ordena por estas mesmas
# colunas, e duas cópias fariam a lista ordenar por uma margem e exibir outra.
COLUNA_MARGEM = {
    ("st_valor", "atacado"): "margem_st_s_valor",
    ("oficial",  "atacado"): "margem_oficial",
    ("sem_red",  "atacado"): "margem_sem_red",
    ("st_valor", "varejo"):  "margem_st_s_valor_varejo",
    ("sem_red",  "varejo"):  "margem_sem_red_varejo",
}


# Ordem fixa do histórico mensal — [Atual, M-1, M-2, M-3] — e o rótulo interno
# que `produto._historico_monitoramento` usa para cada período.
# Espelha `produto._PERIODOS_HISTORICO` (sem `ano_anterior`, que sai à parte
# em `_ano_anterior`). Desde 09/10/2026 vai até m12, para a tela poder mostrar
# a janela INTEIRA da média de cada item - ver o comentário lá.
#
# ⚠ As listas continuam com 4 posições: elas não têm `historico_monitoramento`
# (seria uma consulta por linha) e caem no ramo de VD_MES_ATUAL/VD_M_1..3,
# logo abaixo. Quem desenha gráfico é só a tela do produto, que sempre passa
# pelo ramo de cima - então o tamanho diferente não chega a lugar nenhum que
# o use.
_PERIODOS_VENDA_HISTORICO = ("atual", *(f"m{i}" for i in range(1, 13)))

# As quatro métricas do gráfico do produto, e o que fazer com cada uma:
# `True` = divide por FATOR_EXIBICAO (só quantidade — CONTEXTO.md regra 6).
_METRICAS_HISTORICO = {"quantidade": True, "faturamento": False, "peso": False, "litros": False}


def _venda_historico(p: dict) -> dict[str, list[float | None]]:
    """`{quantidade: [...], faturamento: [...], peso: [...], litros: [...]}`,
    cada lista na ordem [Atual, M-1, M-2, M-3]. Fonte: `produto.obter`, chave
    `historico_monitoramento` (uma consulta só, ver lá o porquê).

    ⚠ `historico_monitoramento` só existe quando `p` veio de `produto.obter`
    (rota `/api/produtos/{codigo}`) — `produto.listar` (as listas paginadas:
    Pedidos, Precificação, Alertas) não roda essa consulta por linha, senão
    uma página de 50 produtos disparava 50 consultas extras por clique. Nas
    listas, quantidade continua saindo de VD_MES_ATUAL/VD_M_1.. (já
    materializado em COMPRAS_PEDIDO, sem custo extra); as outras três métricas
    não têm de onde vir ali, e saem nulas — só a tela do produto (§2) as usa."""
    hist = p.get("historico_monitoramento")
    if hist is not None:
        fator = _f(p.get("fator_exibicao")) or 1
        return {
            metrica: [
                _dividir(hist.get(f"{periodo}_{metrica}"), fator if divide else 1)
                for periodo in _PERIODOS_VENDA_HISTORICO
            ]
            for metrica, divide in _METRICAS_HISTORICO.items()
        }
    quantidade = [_f(p.get(c)) for c in ("vd_mes_atual", "vd_m_1", "vd_m_2", "vd_m_3")]
    return {"quantidade": quantidade, "faturamento": [None] * 4,
            "peso": [None] * 4, "litros": [None] * 4}


def _ano_anterior(p: dict) -> dict[str, float | None]:
    """A barra do mesmo mês do ano anterior, uma por métrica.

    `venda_ano_passado` (COMPRAS_PRODUTO_CONTEXTO) decide se a barra EXISTE —
    None aqui é "sem evidência de que o produto existia", e nenhuma métrica
    desenha barra. Havendo evidência (mesmo que a venda tenha sido zero), os
    NÚMEROS das quatro métricas vêm do monitoramento, não de
    `venda_ano_passado` (que só tem quantidade) — exceto nas listas (ver
    `_venda_historico`), onde só quantidade está disponível mesmo."""
    if p.get("venda_ano_passado") is None:
        return {metrica: None for metrica in _METRICAS_HISTORICO}
    hist = p.get("historico_monitoramento")
    if hist is not None:
        fator = _f(p.get("fator_exibicao")) or 1
        return {
            metrica: _dividir(hist.get(f"ano_anterior_{metrica}"), fator if divide else 1)
            for metrica, divide in _METRICAS_HISTORICO.items()
        }
    return {"quantidade": _f(p.get("venda_ano_passado")),
            "faturamento": None, "peso": None, "litros": None}


def _dividir(valor: Any, divisor: float) -> float | None:
    v = _f(valor)
    if v is None:
        return None
    return v / divisor if divisor else v


def produto(p: dict) -> dict:
    """Uma linha de COMPRAS_PEDIDO no formato que as telas do v2 consomem."""
    return {
        # ---------------------------------------------------------- identidade
        "codigo": int(p["codigo"]),
        "nome": p.get("descricao"),
        "codFab": p.get("cod_fab"),

        # O protótipo chama de `fornecedor`, mas COMPRAS_PEDIDO.FORNECEDOR é a
        # DESCRIÇÃO DO DEPARTAMENTO, não o fornecedor legal da NF — regra que
        # vem do Power Query e está no plano v1. A tela do protótipo já rotula
        # essa coluna como "Departamento", então aqui o nome do campo passa a
        # dizer a verdade. Fecha, de passagem, o ajuste 1 do backlog de 26/08.
        "departamento": p.get("fornecedor"),
        "comprador": p.get("comprador"),
        "classe": p.get("classe"),
        "status": p.get("status"),
        "embalagem": p.get("embalagem"),
        "embalCompra": _f(p.get("embal_compra")),

        # FATOR_EXIBICAO já é "pede em caixa fechada?" resolvido em número:
        # embal_compra quando o departamento é MASTER, 1 quando não. Dispensa a
        # lista de 5 nomes que o protótipo repete 6 vezes (§5/§9).
        "fatorExibicao": _f(p.get("fator_exibicao")),
        "pedidoEm": p.get("pedido_em"),

        # Seção/Linha/Categoria ainda não existem no banco: o cadastro está em
        # andamento no Winthor (PROTOTIPO.md §8). Saem nulos de propósito, para
        # a tela poder esconder o filtro em vez de mostrar um vazio silencioso.
        "secao": None,
        "linha": None,
        "categoria": None,

        # ------------------------------------------------------------- estoque
        "estDisp": _f(p.get("est_disp")),
        "estPend": _f(p.get("est_pend")),
        "pendente": _f(p.get("pendente")),
        "mediaJanela": _f(p.get("media_janela")),
        "mesesCobertura": _f(p.get("meses_est")),
        "mesesCoberturaComPedido": _f(p.get("meses_est_ped")),
        "coberturaAlvo": _f(p.get("cobertura_alvo")),
        "sugCobertura": _f(p.get("sug_cobertura")),
        "valorEstoque": _f(p.get("valor_estoque")),
        "diasSemVenda": _f(p.get("dias_sem_venda")),
        "diasSemEstoque": _f(p.get("dias_sem_estoque")),
        "nMeses": _f(p.get("n_meses")),
        "tendPct": _f(p.get("tend_pct")),
        "tend": p.get("tend"),

        # Etapa 13 (§2.5): lista de números → lista POR MÉTRICA. Ordem
        # [Atual, M-1, M-2, M-3], a mesma que o resto do código já assume
        # (confirmada no protótipo, linhas 2420 e 3098). Fonte:
        # COMPRAS_MONITORAMENTO (`produto._historico_monitoramento`), não mais
        # VD_MES_ATUAL/VD_M_1.. de COMPRAS_PEDIDO.
        #
        # ⚠ Quantidade é dividida por FATOR_EXIBICAO; faturamento/peso/litros
        # não (CONTEXTO.md regra 6 — "quase toda quantidade", o "quase" é
        # aqui). Sem a divisão, 230 SKUs de 8.841 mostrariam o gráfico 12x/24x
        # maior que a "Média mensal" ao lado — medido, não suposto.
        "vendaHistorico": _venda_historico(p),
        # A barra do mesmo mês do ano anterior, uma por métrica — "no mesmo
        # formato" de `vendaHistorico`, mas um número só (não uma lista de 4).
        #
        # ⚠ Quem decide se a barra EXISTE continua sendo `venda_ano_passado`
        # (COMPRAS_PRODUTO_CONTEXTO): zero é "estava vivo e não vendeu", nulo é
        # "não há evidência de que existisse" — o monitoramento não sabe fazer
        # essa distinção (ausência de linha é ausência de linha). Os VALORES
        # das quatro métricas vêm do monitoramento; só a existência da barra
        # continua vindo de `venda_ano_passado`.
        "anoAnterior": _ano_anterior(p),

        "clientesAtacado": _f(p.get("qt_cli_atacado")),
        "clientesVarejo": _f(p.get("qt_cli_varejo")),
        "litragemUnidade": _f(p.get("l_por_unidade")),
        "pesoUnidade": _f(p.get("peso_unitario_kg")),

        "ultimaEntrada": _data(p.get("dt_ult_ent")),
        "qtdUltimaEntrada": _f(p.get("qt_ult_ent")),
        # ── Item 1.16 do Diretor de Compras, 09/10/2026 ──────────────────────
        # "Bonificação como última entrada na Precificação: 8817 com R$ 227,87."
        #
        # `ultimaEntrada` é PCEST.DTULTENT, e o WinThor grava ali QUALQUER
        # entrada. No 8817 a única que existe é um RETORNO DE REMESSA (CODOPER
        # 'ER'), 1 unidade a R$ 227,87, num produto cujo atacado é R$ 72,40.
        # Medido nos 4.553 ativos: 4.011 compras, 423 não-compras, 119 sem
        # movimento no dia.
        #
        # Os números NÃO mudam — custo, margem e preço sugerido continuam
        # saindo do que o WinThor gravou (decisão de 09/10/2026). O que muda é
        # a tela DIZER quando a última entrada não foi compra, e oferecer a
        # data da última compra quando existe uma.
        #
        # `null` em `ultEntradaECompra` é "não sei" (sem movimento no dia), não
        # "não foi compra" — a tela não pode marcar em vermelho o que não
        # mediu. `dtUltCompra` é nulo em 185 dos 423: produtos que NUNCA
        # tiveram compra na filial de estoque, e o 8817 é um deles.
        "ultEntradaECompra": (None if p.get("ult_entrada_e_compra") is None
                              else bool(p.get("ult_entrada_e_compra"))),
        "dtUltCompra": _data(p.get("dt_ult_compra")),
        # Item 1.17: 'S'/'N' do cadastro (PCPRODUT.REVENDA). A tela filtra por
        # ele; o 6326 não está marcado, e marcar é do cadastro — ver
        # `servicos/produto._condicoes`.
        "revenda": p.get("revenda"),
        "ultimaSaida": _data(p.get("dt_ult_saida")),
        "qtdUltimaSaida": _f(p.get("qt_ult_saida")),

        # ------------------------------------------------------------- fiscal
        "modalidade": p.get("modalidade"),
        "mva": _f(p.get("mva")),
        "icmsEfSaida": _f(p.get("icms_saida_ef")),
        "icmsEfSemReducao": _f(p.get("icms_sem_red")),
        "creditoICMS": _f(p.get("cred_icms")),
        "creditoPisCofins": _f(p.get("cred_piscof")),
        "pisCofinsEfetivo": _f(p.get("piscof_ef")),
        # Texto descritivo do regime ("RE ST BA MVA 62,35% LUBRI"), de
        # COMPRAS_PRODUTO_CONTEXTO. Nulo nos 5 SKUs sem tributação encontrada —
        # os mesmos que disparam o alerta TRIB. Nulo é a resposta honesta ali:
        # inventar um regime seria pior que admitir que não se sabe.
        "regimeFiscal": p.get("regime_fiscal"),

        # -------------------------------------------------------------- custo
        # Valor da NOTA (bruto de imposto/crédito) na última entrada, já POR
        # UNIDADE (REGRAS.md §regra 8: VL_ULT_ENT nunca é dividido pela
        # embalagem de compra — vem unitário do dbt). Distinto de
        # `custoUltimaEntrada`, que é líquido de imposto/crédito. É esta
        # coluna, e não `custoGerencial`, que passou a ser o padrão de PREÇO
        # UNITÁRIO do item de pedido (24/09/2026 — ver app/servicos/pedido.py).
        "valorEntradaUnitario": _f(p.get("vl_ent_unit")),
        # `valorEntradaUnitario` (VL_ENT_UNIT/PCEST.VALORULTENT) embute o
        # frete quando há — é o valor da nota, usado na Precificação, onde o
        # custo do frete faz parte da decisão de preço. `precoEntradaSemFrete`
        # (COMPRAS_PRODUTO_CONTEXTO.PRECO_ULT_ENT_SEM_FRETE) é o produto puro
        # pela lógica da rotina 218 do WinThor, sem frete — usado em Pedidos,
        # onde se negocia com o fornecedor e o frete não entra. Não trocar um
        # pelo outro.
        "precoEntradaSemFrete": _f(p.get("preco_ult_ent_sem_frete")),
        # O lado "ger" do par que a tela mostra ao lado de
        # `valorEntradaUnitario`, no mesmo formato que o Custo já usa: quanto o
        # produto custou para entrar no estoque SEM descontar nenhum crédito.
        # Decisão do Diretor de Compras em 29/09/2026, validada por ele na tela
        # sobre 9 produtos — ela FECHA a pergunta que `docs/VALOR_NF_PROJETADO.md`
        # deixou aberta em 25/09.
        # ⚠ Não confundir com o "Valor NF projetado" que foi retirado naquela
        # data: aquele reconstruía o valor PARA TRÁS a partir do custo e
        # divergia da nota em até 34%. Este parte de VL_ENT_UNIT e soma para
        # frente, então não tem como divergir dela.
        "valorGerencial": _f(p.get("valor_tot_gerencial")),
        "custoUltimaEntrada": _f(p.get("custo_ult_ent")),
        "custoStValor": _f(p.get("custo_tot_s_valor")),
        "custoOficial": _f(p.get("custo_tot_oficial")),
        # ⚠ No banco, gerencial ≠ oficial onde há ajuste de imagem (Ingrax).
        # O protótipo tratava os dois como o mesmo campo (§9).
        "custoGerencial": _f(p.get("custo_tot_gerencial")),

        # -------------------------------------------------------------- preço
        "pvAtacado": _f(p.get("pv_atacado")),
        "pvVarejo": _f(p.get("pv_varejo")),
        "mkpAtacado": _f(p.get("mkp_atacado")),
        "mkpVarejo": _f(p.get("mkp_varejo")),
        "margemAlvo": _f(p.get("margem_alvo")),
        "margemAlvoVarejo": _f(p.get("margem_alvo_varejo")),
        "cenarioReal": _cenario_real(p.get("modalidade")),
        "cenariosAtacado": _cenarios(p, "atacado"),
        "cenariosVarejo": _cenarios(p, "varejo"),

        # Preço já decidido por gente, de APP_DECISAO_PRECO. Nulo quando
        # ninguém decidiu ainda — nunca preenchido com uma das sugestões,
        # que é o ponto de decisão humana que o modelo existe para preservar.
        "precoDecididoAtacadoAV": _f(p.get("alt_pv_at_av")),
        "precoDecididoAtacadoAP": _f(p.get("alt_pv_at_ap")),
        "precoDecididoVarejoAV": _f(p.get("alt_pv_var_av")),
        "precoDecididoVarejoAP": _f(p.get("alt_pv_var_ap")),

        # Etapa 15 §4: a data ao lado de cada número acompanha a FONTE daquele
        # número. `_data` (trunca no dia), nunca `_dt` — `data(iso)` de
        # web/src/formato.js:109 quebra com ISO com hora.
        "precoAlteradoEmAtacado": _data(p.get("dt_ult_alt_pv_atacado")),
        "precoAlteradoEmVarejo":  _data(p.get("dt_ult_alt_pv_varejo")),
        "precoDecididoEm":        _data(p.get("decisao_atualizado_em")),

        # ------------------------------------------------------------ sucessão
        "sucessao": _sucessao(p),
        # Avisos livres escritos por gente. Ainda não há tabela (PLANO §2.3).
        "sazonalidade": None,
        "campanhaAtiva": None,
        # Atributos de fornecedor que ainda não existem no seed (PLANO §2.3).
        "prazoEntregaDias": None,
        "pedidoMinimo": None,

        # ------------------------------------------------------------ alertas
        "alertas": p.get("alertas", []),
    }


def _sucessao(p: dict) -> list[dict]:
    """ANT_1/PESO_1 e ANT_2/PESO_2 viram uma lista — quase sempre vazia.

    Duas colunas paralelas que quase sempre são nulas é forma de planilha, não
    de API: obrigaria toda tela a checar dois campos para descobrir que não há
    nada. Lista vazia responde a mesma pergunta com um `length`.
    """
    saida = []
    for ant, peso in (("ant_1", "peso_1"), ("ant_2", "peso_2")):
        if p.get(ant):
            saida.append({"antecessor": p[ant], "peso": _f(p.get(peso))})
    return saida


def pagina(linhas: list[dict], total: int, pagina_atual: int, por_pagina: int) -> dict:
    return {
        "itens": [produto(l) for l in linhas],
        "total": total,
        "pagina": pagina_atual,
        "porPagina": por_pagina,
        "totalPaginas": (total + por_pagina - 1) // por_pagina if por_pagina else 0,
    }


def _dt(valor: Any) -> str | None:
    """Timestamp completo (data+hora), ISO 8601 — diferente de `_data`, que
    trunca pro dia. Cabeçalho/histórico de pedido precisa da hora."""
    if valor is None:
        return None
    if isinstance(valor, (dt.datetime, dt.date)):
        return valor.isoformat()
    return str(valor)


def item_pedido(i: dict) -> dict:
    quantidade = _f(i.get("quantidade")) or 0.0
    fator = _f(i.get("fator_exibicao")) or 0.0
    preco = _f(i.get("preco_unitario")) or 0.0
    return {
        "codigo": int(i["codigo"]),
        "descricao": i.get("descricao"),
        "codFab": i.get("cod_fab"),
        "embalagem": i.get("embalagem"),
        "embalCompra": _f(i.get("embal_compra")),
        "quantidade": _f(i.get("quantidade")),
        # Congelado na linha (MELHORIA A5) — não é o fator corrente do cadastro.
        "fatorExibicao": _f(i.get("fator_exibicao")),
        "precoUnitario": _f(i.get("preco_unitario")),
        "quantidadeUnidades": quantidade * fator,
        "valorTotal": quantidade * fator * preco,
        "criadoEm": _dt(i.get("criado_em")),
    }


def pedido(p: dict) -> dict:
    """Cabeçalho de APP_PEDIDO (+ agregados qtd_itens/valor_total quando a
    consulta os trouxe — ausentes só em caminhos que não passam por
    `pedido.obter_pedido`/`listar_pedidos`, o que hoje não acontece)."""
    corpo = {
        "id": int(p["id_pedido"]),
        "fornecedor": p.get("fornecedor"),
        "status": p.get("status"),
        "criadoEm": _dt(p.get("criado_em")),
        "criadoPor": p.get("criado_por"),
        "atualizadoEm": _dt(p.get("atualizado_em")),
        "atualizadoPor": p.get("atualizado_por"),
    }
    if "qtd_itens" in p:
        corpo["qtdItens"] = int(p.get("qtd_itens") or 0)
    if "valor_total" in p:
        corpo["valorTotal"] = _f(p.get("valor_total")) or 0.0
    return corpo


def pedido_detalhe(p: dict) -> dict:
    corpo = pedido(p)
    corpo["itens"] = [item_pedido(i) for i in p.get("itens", [])]
    return corpo


def pagina_pedidos(linhas: list[dict], total: int, pagina_atual: int, por_pagina: int) -> dict:
    return {
        "itens": [pedido(l) for l in linhas],
        "total": total,
        "pagina": pagina_atual,
        "porPagina": por_pagina,
        "totalPaginas": (total + por_pagina - 1) // por_pagina if por_pagina else 0,
    }


def item_lote_preco(i: dict) -> dict:
    """Item de APP_LOTE_PRECO_ITEM (+ os campos calculados por
    `lote_preco.obter_itens`: `situacao`, `entra_arquivo_201`,
    `motivo_exclusao_201`). `pvAtacadoBanco`/`pvVarejoBanco` é o que
    COMPRAS_PEDIDO tem HOJE — junto com `pvAtacado(Atual|Novo)`, dá a
    tela "de -> para -> está" (§4.5 do PROMPT_ETAPA_12)."""
    return {
        "codigo": int(i["codigo"]),
        "descricao": i.get("descricao"),
        "codFab": i.get("cod_fab"),
        "departamento": i.get("departamento"),
        "pvAtacadoAtual": _f(i.get("pv_atacado_atual")),
        "pvAtacadoNovo": _f(i.get("pv_atacado_novo")),
        "pvVarejoAtual": _f(i.get("pv_varejo_atual")),
        "pvVarejoNovo": _f(i.get("pv_varejo_novo")),
        "pvAtacadoBanco": _f(i.get("pv_atacado_banco")),
        "pvVarejoBanco": _f(i.get("pv_varejo_banco")),
        "altPvAtacadoAP": _f(i.get("alt_pv_at_ap")),
        "altPvVarejoAP": _f(i.get("alt_pv_var_ap")),
        # "aplicado" | "pendente" | "parcial" | "divergente" | None (nenhum
        # canal decidido ainda) — medido, nunca declarado por clique (§4.5).
        # "parcial": um canal aplicado e o outro ainda pendente, sem nenhum
        # canal divergente (ver `lote_preco._situacao_item`).
        "situacao": i.get("situacao"),
        "entraArquivo201": i.get("entra_arquivo_201"),
        "motivoExclusao201": i.get("motivo_exclusao_201"),
        "criadoEm": _dt(i.get("criado_em")),
        "criadoPor": i.get("criado_por"),
        "atualizadoEm": _dt(i.get("atualizado_em")),
        "atualizadoPor": i.get("atualizado_por"),
    }


def lote_preco(l: dict) -> dict:
    """Cabeçalho de APP_LOTE_PRECO (+ agregados qtd_itens/qtd_aplicados
    quando a consulta os trouxe — `lote_preco.listar_lotes`/`obter_lote`)."""
    corpo = {
        "id": int(l["id_lote"]),
        "status": l.get("status"),
        "observacao": l.get("observacao"),
        "criadoEm": _dt(l.get("criado_em")),
        "criadoPor": l.get("criado_por"),
        "atualizadoEm": _dt(l.get("atualizado_em")),
        "atualizadoPor": l.get("atualizado_por"),
    }
    if "qtd_itens" in l:
        corpo["qtdItens"] = int(l.get("qtd_itens") or 0)
    if "qtd_aplicados" in l:
        corpo["qtdAplicados"] = int(l.get("qtd_aplicados") or 0)
    if "lote_reaproveitado" in l:
        # Só presente na resposta de POST /lotes-preco sem idLote (criar_lote
        # em app/servicos/lote_preco.py): diz se o servidor reaproveitou o
        # Rascunho aberto do usuário (§4.3) ou abriu documento novo — a tela
        # usa para mostrar "criado o lote #N" vs. "acrescentado ao lote #N".
        corpo["loteReaproveitado"] = bool(l.get("lote_reaproveitado"))
    return corpo


def lote_preco_detalhe(l: dict) -> dict:
    corpo = lote_preco(l)
    corpo["itens"] = [item_lote_preco(i) for i in l.get("itens", [])]
    return corpo


def pagina_lotes_preco(linhas: list[dict], total: int, pagina_atual: int, por_pagina: int) -> dict:
    return {
        "itens": [lote_preco(l) for l in linhas],
        "total": total,
        "pagina": pagina_atual,
        "porPagina": por_pagina,
        "totalPaginas": (total + por_pagina - 1) // por_pagina if por_pagina else 0,
    }


def usuario(u) -> dict:
    return {
        "id": u.id,
        "login": u.login,
        "nome": u.nome,
        "ehAdmin": u.eh_admin,
        "ehDiretoria": u.eh_diretoria,
        "senhaProvisoria": u.senha_provisoria,
    }
