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
# O protótipo descobre o custo de cada cenário com um if/else inferido por
# comparação empírica de números (PROTOTIPO.md §5/§9). Aqui não é preciso
# inferir: o dbt já materializou a margem de cada cenário coluna a coluna.
#
# O custo, sim, precisa de uma regra — e ela é fiscal, não empírica: redução de
# base de ICMS mexe no imposto de SAÍDA, não no custo de entrada. Por isso
# "Sem Redução" não tem custo próprio; ele reusa o custo do regime que de fato
# se aplica ao produto: quem é ST_SUBSTITUTO carrega o ST no custo (Oficial),
# quem é NORMAL não carrega (ST s/Valor). É a mesma conclusão a que o protótipo
# chegou por tentativa, agora pelo caminho da razão.
#
# ⚠ CUSTO_TOT_OFICIAL e CUSTO_TOT_GERENCIAL são DOIS campos no nosso banco, e
# diferem onde há ajuste de imagem (o 80/20 do Ingrax). O protótipo tinha um só
# no mock e concluiu que "custoGerencial é sinônimo do custo Oficial" (§9). Para
# cenário fiscal usa-se o OFICIAL; o gerencial é para leitura de margem interna
# e não entra em base de ST.
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


def _custo_do_cenario(p: dict, cenario: str) -> float | None:
    if cenario == "st_valor":
        return _f(p.get("custo_tot_s_valor"))
    if cenario == "oficial":
        return _f(p.get("custo_tot_oficial"))
    # sem_red: ver o bloco de comentário acima.
    eh_st = (p.get("modalidade") or "").upper() == "ST_SUBSTITUTO"
    return _f(p.get("custo_tot_oficial" if eh_st else "custo_tot_s_valor"))


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
            "margemAtual": _f(p.get(_COLUNA_MARGEM[(cid, praca)])),
            "pvSugeridoAV": _f(p.get(f"pv_sug_{_chave_sug(cid)}{sug}_av")),
            "pvSugeridoAP": _f(p.get(f"pv_sug_{_chave_sug(cid)}{sug}_ap")),
        }
        for cid in ids
    ]


def _chave_sug(cenario: str) -> str:
    return {"st_valor": "st_s_valor", "oficial": "oficial", "sem_red": "sem_red"}[cenario]


# O nome da coluna de margem não segue o id do cenário (`st_valor` mora em
# `MARGEM_ST_S_VALOR`), então o de-para fica explícito aqui em vez de ser
# montado com f-string condicional — que é fácil de escrever e difícil de ler.
_COLUNA_MARGEM = {
    ("st_valor", "atacado"): "margem_st_s_valor",
    ("oficial",  "atacado"): "margem_oficial",
    ("sem_red",  "atacado"): "margem_sem_red",
    ("st_valor", "varejo"):  "margem_st_s_valor_varejo",
    ("sem_red",  "varejo"):  "margem_sem_red_varejo",
}


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

        # [Atual, M-1, M-2, M-3] — a ordem do protótipo, confirmada no .jsx
        # (linhas 2420 e 3098: `// [Atual, M-1, M-2, M-3]`).
        "vendaHistorico": [
            _f(p.get("vd_mes_atual")), _f(p.get("vd_m_1")),
            _f(p.get("vd_m_2")), _f(p.get("vd_m_3")),
        ],
        # Mesmo mês do ano anterior. Derivável de COMPRAS_VENDA_MENSAL, mas
        # ainda não projetado em COMPRAS_PEDIDO — entra na Etapa 8 (PLANO §2.3).
        "vendaAnoPassado": None,

        "clientesAtacado": _f(p.get("qt_cli_atacado")),
        "clientesVarejo": _f(p.get("qt_cli_varejo")),
        "litragemUnidade": _f(p.get("l_por_unidade")),
        "pesoUnidade": _f(p.get("peso_unitario_kg")),

        "ultimaEntrada": _data(p.get("dt_ult_ent")),
        "qtdUltimaEntrada": _f(p.get("qt_ult_ent")),
        "ultimaSaida": _data(p.get("dt_ult_saida")),
        "qtdUltimaSaida": None,   # existe em int_cadastro_estoque, falta projetar (PLANO §2.2)

        # ------------------------------------------------------------- fiscal
        "modalidade": p.get("modalidade"),
        "mva": _f(p.get("mva")),
        "icmsEfSaida": _f(p.get("icms_saida_ef")),
        "icmsEfSemReducao": _f(p.get("icms_sem_red")),
        "creditoICMS": _f(p.get("cred_icms")),
        "creditoPisCofins": _f(p.get("cred_piscof")),
        "pisCofinsEfetivo": _f(p.get("piscof_ef")),
        # Texto descritivo do regime ("RE ST BA MVA 62,35% LUBRI"). Está em
        # dim_tributacao.descricao; sobe para a camada de contrato na Etapa 8.
        "regimeFiscal": None,

        # -------------------------------------------------------------- custo
        "valorNfUnitario": _f(p.get("vl_ent_unit")),
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


def usuario(u) -> dict:
    return {
        "id": u.id,
        "login": u.login,
        "nome": u.nome,
        "ehAdmin": u.eh_admin,
        "ehDiretoria": u.eh_diretoria,
        "senhaProvisoria": u.senha_provisoria,
    }
