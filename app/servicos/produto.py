"""Leitura de produto para a API v2 (Etapa 7).

Uma consulta só, com o conjunto de campos que o protótipo pede (`PROTOTIPO.md`
§3/§4). O serviço devolve as colunas do banco como estão — em minúsculo, com o
nome que têm em COMPRAS_PEDIDO. A tradução para o vocabulário do protótipo
(`custoStValor`, `margemAtacadoOficial`, ...) mora em `app/api/contrato.py`, e
só lá: quem mexe em SQL não precisa saber como o React chama o campo, e quem
mexe no React não precisa abrir SQL.

⚠ Só COMPRAS_* aqui. Nada de CEDEP, nada de int_*/fat_* — a camada de contrato
do dbt é o limite (CONTEXTO.md §2/§5).
"""
from __future__ import annotations

from app.api import alertas
from app.core import database

# ─────────────────────────────────────────────────────────────────────────────
# COBERTURA_ALVO e PEDIDO_EM vêm de COMPRAS_IND_FORNECEDOR, não de
# COMPRAS_PEDIDO — o grão de lá é o departamento, e é lá que o seed_fornecedor
# desemboca. Evita ter de esperar um `dbt run` só para projetar duas colunas
# que já estão materializadas ao lado.
#
# PEDIDO_EM merece nota: o protótipo resolve "esse fornecedor pede em caixa
# fechada?" com uma lista de 5 nomes escrita à mão, repetida literalmente 6
# vezes no arquivo (PROTOTIPO.md §5/§9). Os 5 nomes são exatamente os que têm
# PEDIDO_EM='MASTER' no seed. Aqui a pergunta se responde com o dado, uma vez
# só — e FATOR_EXIBICAO, que já existe em COMPRAS_PEDIDO, é o mesmo fato já
# convertido em número (embal_compra quando MASTER, 1 quando não).
# ─────────────────────────────────────────────────────────────────────────────
_COLUNAS = """
    p.codigo, p.cod_fab, p.descricao, p.fornecedor, p.comprador, p.classe,
    p.status, p.embalagem, p.embal_compra, p.fator_exibicao,

    p.est_disp, p.est_pend, p.pendente, p.media_janela, p.meses_est,
    p.meses_est_ped, p.sug_cobertura, p.valor_estoque, p.dias_sem_venda,
    p.dias_sem_estoque, p.n_meses, p.tend_pct, p.tend,

    p.vd_mes_atual, p.vd_m_1, p.vd_m_2, p.vd_m_3,
    p.qt_cli_atacado, p.qt_cli_varejo,
    p.l_por_unidade, p.peso_unitario_kg,

    p.modalidade, p.mva, p.icms_saida_ef, p.icms_sem_red,
    p.cred_icms, p.cred_piscof, p.piscof_ef,

    p.vl_ent_unit, p.custo_ult_ent, p.custo_tot_s_valor,
    p.custo_tot_oficial, p.custo_tot_gerencial, p.custo_adicional_imagem,

    p.pv_atacado, p.pv_varejo, p.mkp_atacado, p.mkp_varejo,
    p.margem_st_s_valor, p.margem_oficial, p.margem_sem_red,
    p.margem_st_s_valor_varejo, p.margem_sem_red_varejo,
    p.margem_alvo, p.margem_alvo_varejo,

    p.pv_sug_st_s_valor_av, p.pv_sug_st_s_valor_ap,
    p.pv_sug_oficial_av,    p.pv_sug_oficial_ap,
    p.pv_sug_sem_red_av,    p.pv_sug_sem_red_ap,
    p.pv_sug_st_s_valor_var_av, p.pv_sug_st_s_valor_var_ap,
    p.pv_sug_sem_red_var_av,    p.pv_sug_sem_red_var_ap,
    d.alt_pv_at_av                                     as alt_pv_at_av,
    d.alt_pv_at_av  * par.fator_prazo_atacado          as alt_pv_at_ap,
    d.alt_pv_var_av                                    as alt_pv_var_av,
    d.alt_pv_var_av * par.fator_prazo_varejo           as alt_pv_var_ap,

    p.dt_ult_ent, p.qt_ult_ent, p.dt_ult_saida,
    p.ant_1, p.peso_1, p.ant_2, p.peso_2, p.check_sucessao,

    f.cobertura_alvo, f.pedido_em, f.meses_media
"""

# ⚠ APP_DECISAO_PRECO entra AO VIVO, por join, e não pelas colunas ALT_PV_* da
# tabela materializada.
#
# COMPRAS_PEDIDO só é recalculado no próximo `dbt run` — o dbt LÊ as APP_* e
# nunca escreve nelas. Ler o preço decidido de lá faria a tela mostrar o valor
# VELHO logo depois de gravar, e o comprador concluiria que a gravação falhou.
# É exatamente o defeito que apareceu na tela de compra em 25/08/2026 e cuja
# correção está documentada em `app/servicos/compra.py`.
#
# O "a prazo" é RECALCULADO aqui a partir do à vista ao vivo, com o fator vindo
# de COMPRAS_PARAMETRO. Trazer ALT_PV_AT_AP da tabela materializada enquanto o
# AV vem ao vivo faria os dois discordarem entre si na mesma linha — dois
# números que deveriam ser um só, e nenhum aviso de que divergiram.
#
# COMPRAS_PARAMETRO tem 1 linha; o cross join não multiplica nada.
_DE = """
      from compras_pedido p
      cross join compras_parametro par
      left join compras_ind_fornecedor f
        on f.fornecedor = p.fornecedor
      left join app_decisao_preco d
        on d.id_produto = p.codigo
"""

ORDENACOES = {
    # A ordem padrão da tela de Alertas: soma dos pesos dos alertas ativos do
    # produto + peso da curva ABC (PROTOTIPO.md §2.1). Ver app/api/alertas.py.
    "prioridade": alertas.sql_ordem_prioridade("p"),
    # nulls last em todas: produto sem cobertura calculada não pode encabeçar
    # uma lista ordenada por cobertura só porque o Oracle põe null primeiro.
    "cobertura": "p.meses_est asc nulls last, p.codigo",
    "margem": "p.margem_oficial asc nulls last, p.codigo",
    "giro": "p.dias_sem_venda desc nulls last, p.codigo",
    "valor": "p.valor_estoque desc nulls last, p.codigo",
    "codigo": "p.codigo",
    "descricao": "p.descricao",
}


def _condicoes(filtros: dict, incluir_alerta: bool = True) -> tuple[str, dict]:
    """Monta o `where`.

    `incluir_alerta=False` devolve a base SEM o filtro de tipo de alerta. É o
    recorte que o protótipo chama de `baseFiltrada` (§2.1) e que alimenta os 3
    KPIs e a contagem de cada botão de tipo. Tem de ser assim: o número no botão
    "Ruptura 425" responde "quantos eu veria se ligasse este", então não pode já
    estar filtrado pelo que está ligado — senão o botão desligado mostraria
    zero e ninguém mais o ligaria.
    """
    condicoes: list[str] = []
    binds: dict = {}

    if filtros.get("departamento"):
        condicoes.append("p.fornecedor = :departamento")
        binds["departamento"] = filtros["departamento"]

    if filtros.get("comprador"):
        condicoes.append("p.comprador = :comprador")
        binds["comprador"] = filtros["comprador"]

    if filtros.get("classe"):
        condicoes.append("p.classe = :classe")
        binds["classe"] = filtros["classe"]

    # "Ativo"/"Inativo" na tela; STATUS no banco guarda o mesmo vocabulário.
    # Sem valor = todos, que é o que "Todos" na tela significa.
    if filtros.get("status"):
        condicoes.append("p.status = :status")
        binds["status"] = filtros["status"]

    if filtros.get("busca"):
        condicoes.append(
            "(to_char(p.codigo) like :busca"
            " or upper(p.descricao) like upper(:busca)"
            " or upper(p.cod_fab) like upper(:busca))"
        )
        binds["busca"] = f"%{filtros['busca'].strip()}%"

    if not incluir_alerta:
        return (f"where {' and '.join(condicoes)}" if condicoes else ""), binds

    # ── Um tipo de alerta, ou vários ──────────────────────────────────────────
    # Nunca `like` na string ALERTA concatenada: COMPRAS_ALERTA já vem
    # despivotado, uma linha por tipo (CONTEXTO §6).
    #
    # A categoria recorta QUAL universo de alerta conta. A tela de Alertas usa
    # 'DECISAO'; a de Pendência de Cadastro usará 'CADASTRO'. Sem esse recorte,
    # 1.871 SKUs cujo único alerta é de cadastro entrariam na lista de decisão
    # de compra — foi o que o Diretor mandou separar no item 2.
    #
    # ⚠ O bind de categoria é registrado DENTRO de cada ramo que o usa, e não
    # aqui em cima. Registrá-lo antes causou um 500 em produção (ORA-01036,
    # 02/09/2026): ao ligar um botão de tipo, o `exists` passava a usar só
    # `:ta0..:taN`, o `:categoria` sobrava na lista de binds, e o Oracle recusa
    # bind declarado e não usado. Um `where` montado por pedaços não pode ter
    # bind pendurado num pedaço que não entrou.
    categoria = filtros.get("categoria")

    def _com_categoria(sql_alerta: str) -> str:
        if not categoria:
            return sql_alerta
        binds["categoria"] = categoria
        return f"{sql_alerta} and a.categoria = :categoria"

    tipos = filtros.get("tipos_alerta") or []
    if tipos:
        marcas = ", ".join(f":ta{i}" for i in range(len(tipos)))
        binds.update({f"ta{i}": t for i, t in enumerate(tipos)})
        condicoes.append(
            "exists (select 1 from compras_alerta a"
            + _com_categoria(f" where a.codigo = p.codigo and a.tipo_alerta in ({marcas})")
            + ")"
        )
    elif filtros.get("so_com_alerta"):
        # A tela de Alertas sem nenhum tipo ligado mostra "todo mundo que tem
        # pelo menos 1 alerta" (PROTOTIPO.md §2.1), que não é o mesmo que
        # "todo mundo".
        condicoes.append(
            "exists (select 1 from compras_alerta a"
            + _com_categoria(" where a.codigo = p.codigo")
            + ")"
        )

    onde = f"where {' and '.join(condicoes)}" if condicoes else ""
    return onde, binds


def listar(filtros: dict, pagina: int, itens_por_pagina: int,
           ordenacao: str = "codigo") -> tuple[list[dict], int]:
    onde, binds = _condicoes(filtros)

    total_linha = database.consultar_um(
        f"select count(*) as n from compras_pedido p {onde}", binds
    )
    total = int(total_linha["n"]) if total_linha else 0

    pagina = max(1, pagina)
    ordem = ORDENACOES.get(ordenacao, ORDENACOES["codigo"])
    linhas = database.consultar(
        f"""
        select {_COLUNAS}
          {_DE}
          {onde}
         order by {ordem}
        offset :offset rows fetch next :limite rows only
        """,
        {**binds, "offset": (pagina - 1) * itens_por_pagina, "limite": itens_por_pagina},
    )
    anexar_alertas(linhas, filtros.get("categoria"))
    return linhas, total


def resumo(filtros: dict) -> dict:
    """Os KPIs do topo da tela, somados sobre o FILTRO INTEIRO.

    O protótipo soma em memória porque tem 8 produtos no array (§4.1). Aqui são
    8.777 SKUs paginados de 50 em 50: somar o que veio na página daria números
    que mudam ao virar a página — e número que se move sozinho é pior que
    número nenhum.

    ── Por que são DOIS indicadores de valor, e não um ────────────────────────
    O protótipo tem só "Valor em risco" = soma do valor de ESTOQUE dos produtos
    com alerta. Medimos o que isso esconde: dos 425 produtos em ruptura, 201
    têm valor de estoque ZERO — porque ruptura é, por definição, não ter
    estoque. O pior problema da operação contribuía com R$ 0 para o indicador
    que deveria medi-lo.

    O Diretor separou em dois (item 5):
      * CAPITAL PARADO  — dinheiro imobilizado: valor de estoque de quem tem
        alerta. É a fórmula antiga, sem mudança.
      * VENDA EM RISCO  — dinheiro que deixa de entrar: para quem está em
        ruptura, média mensal de venda x preço de atacado. É o indicador que a
        ruptura sempre deveria ter alimentado.
    Somar os dois seria erro de leitura: um é estoque, o outro é faturamento.
    """
    onde, binds = _condicoes(filtros, incluir_alerta=False)
    categoria = filtros.get("categoria")
    filtro_cat = " and a.categoria = :categoria" if categoria else ""
    if categoria:
        binds["categoria"] = categoria

    linha = database.consultar_um(
        f"""
        select
            count(case when exists (select 1 from compras_alerta a
                                     where a.codigo = p.codigo{filtro_cat})
                       then 1 end)                                  as com_alerta,
            nvl(sum(case when exists (select 1 from compras_alerta a
                                       where a.codigo = p.codigo{filtro_cat})
                         then p.valor_estoque end), 0)              as capital_parado,
            count(case when exists (select 1 from compras_alerta a
                                     where a.codigo = p.codigo
                                       and a.tipo_alerta = 'RUPTURA')
                       then 1 end)                                  as rupturas,
            nvl(sum(case when exists (select 1 from compras_alerta a
                                       where a.codigo = p.codigo
                                         and a.tipo_alerta = 'RUPTURA')
                         then p.media_janela * p.pv_atacado end), 0) as venda_em_risco
          from compras_pedido p
          {onde}
        """,
        binds,
    )
    return {
        "comAlerta": int(linha["com_alerta"] or 0),
        "capitalParado": float(linha["capital_parado"] or 0),
        "rupturas": int(linha["rupturas"] or 0),
        "vendaEmRisco": float(linha["venda_em_risco"] or 0),
    }


def contagem_por_tipo(filtros: dict) -> dict[str, int]:
    """Quantos produtos cada tipo de alerta pega, dentro do filtro atual.

    Sem o filtro de tipo (ver `_condicoes`): é o número que vai no botão, e ele
    tem de responder "quantos eu veria se ligasse este". Já a categoria vale,
    porque a tela de Alertas não desenha botão para alerta de cadastro.
    """
    onde, binds = _condicoes(filtros, incluir_alerta=False)
    categoria = filtros.get("categoria")
    filtro_cat = " and a.categoria = :categoria" if categoria else ""
    if categoria:
        binds["categoria"] = categoria

    linhas = database.consultar(
        f"""
        select a.tipo_alerta, count(distinct a.codigo) as n
          from compras_alerta a
         where a.codigo in (select p.codigo from compras_pedido p {onde})
               {filtro_cat}
         group by a.tipo_alerta
        """,
        binds,
    )
    return {l["tipo_alerta"]: int(l["n"]) for l in linhas}


def obter(codigo: int) -> dict | None:
    linha = database.consultar_um(
        f"select {_COLUNAS} {_DE} where p.codigo = :codigo", {"codigo": codigo}
    )
    if linha:
        anexar_alertas([linha])
    return linha


def anexar_alertas(linhas: list[dict], categoria: str | None = None) -> None:
    """Uma consulta para a página inteira, não uma por linha.

    Mesmo desenho de `compra.py._anexar_alertas`, e pelo mesmo motivo: a coluna
    ALERTA de COMPRAS_PEDIDO é string concatenada com "; ", boa para quem lê a
    planilha e péssima para a tela. Dar split("; ") no cliente quebraria em
    silêncio no dia em que um texto de alerta contivesse ";".
    """
    if not linhas:
        return
    codigos = [int(l["codigo"]) for l in linhas]
    marcas = ", ".join(f":c{i}" for i in range(len(codigos)))
    binds = {f"c{i}": c for i, c in enumerate(codigos)}
    # A categoria tem de valer AQUI também, não só no filtro da lista. Sem isto
    # a linha entra na tela por ter um alerta de decisão e chega mostrando
    # "IMPORTADO" ao lado — 63 das primeiras 200 linhas faziam isso. O Diretor
    # foi explícito no item 2: os alertas de cadastro "saem inteiramente da tela
    # de Alertas". Filtrar a lista e não as etiquetas seria tirá-los pela porta
    # e deixá-los voltar pela janela.
    filtro_cat = ""
    if categoria:
        filtro_cat = " and categoria = :categoria"
        binds["categoria"] = categoria
    achados = database.consultar(
        f"""
        select codigo, tipo_alerta, texto_alerta, categoria, pontua
          from compras_alerta
         where codigo in ({marcas}){filtro_cat}
         order by codigo, ordem_exibicao
        """,
        binds,
    )
    por_codigo: dict[int, list[dict]] = {}
    for a in achados:
        por_codigo.setdefault(int(a["codigo"]), []).append(
            {"tipo": a["tipo_alerta"], "texto": a["texto_alerta"],
             "categoria": a["categoria"], "pontua": a["pontua"] == "S"}
        )
    for l in linhas:
        l["alertas"] = por_codigo.get(int(l["codigo"]), [])


def opcoes() -> dict:
    """Listas para preencher os filtros. Sempre de COMPRAS_*, nunca do CEDEP."""
    return {
        "departamentos": [r["fornecedor"] for r in database.consultar(
            "select distinct fornecedor from compras_pedido"
            " where fornecedor is not null order by 1"
        )],
        "compradores": [r["comprador"] for r in database.consultar(
            "select distinct comprador from compras_pedido"
            " where comprador is not null order by 1"
        )],
        "classes": [r["classe"] for r in database.consultar(
            "select distinct classe from compras_pedido where classe is not null order by 1"
        )],
        "status": [r["status"] for r in database.consultar(
            "select distinct status from compras_pedido where status is not null order by 1"
        )],
        "tipos_alerta": [
            {"tipo": r["tipo_alerta"], "quantidade": int(r["n"])}
            for r in database.consultar(
                "select tipo_alerta, count(*) as n from compras_alerta"
                " where tipo_alerta is not null group by tipo_alerta order by 1"
            )
        ],
    }
