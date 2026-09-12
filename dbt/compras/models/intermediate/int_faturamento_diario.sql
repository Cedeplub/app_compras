-- ─────────────────────────────────────────────────────────────────────────────
-- int_faturamento_diario — irmão em grão DIA de int_faturamento_mensal (v2
-- Etapa 10, tela Monitoramento). MESMAS regras de negócio, cópia deliberada
-- do critério da rotina 1464 (não um novo cálculo) - só a granularidade do
-- TRUNC muda, de 'MM' para dia, e a janela vem de int_periodo_diario, não de
-- int_periodo_mensal. Ver o cabeçalho de int_faturamento_mensal.sql para a
-- explicação de cada filtro; não repetido aqui linha a linha para não
-- divergir se um dos dois for corrigido e o outro não.
--
-- Grão: dia × produto. Faturamento BRUTO - o líquido nasce em
-- int_venda_diaria, que soma este model com int_devolucao_diaria (mesmo
-- desenho de int_venda_mensal).
-- ─────────────────────────────────────────────────────────────────────────────

with regiao as (
    select * from {{ ref('stg_regiao') }}
),

cliente_proprio as (
    select * from {{ ref('int_cliente_proprio') }}
),

periodo as (
    select * from {{ ref('int_periodo_diario') }}
),

notas_venda as (
    select
        n.id_transacao_venda,
        n.id_filial,
        n.condicao_venda
      from {{ ref('stg_nota_saida') }} n
     cross join periodo pe
     where n.data_cancelamento is null
       and nvl(n.tipo_venda, 'X') not in ('SR', 'DF')
       and n.codigo_fiscal not in (522, 622, 722, 532, 632, 732)
       and n.condicao_venda not in (4, 8, 10, 13, 20, 98, 99)
       and n.data_saida >= pe.data_inicio
       and n.data_saida <  pe.data_fim
),

movimentacao as (
    select
        m.id_transacao_venda,
        m.id_transacao_item,
        m.id_produto,
        m.id_cliente,
        m.id_regiao,
        decode(nv.condicao_venda, 7, m.quantidade_contratada, m.quantidade) as quantidade,
        m.preco_unitario,
        nvl(m.valor_frete, 0)           as valor_frete,
        nvl(m.valor_outras_despesas, 0) as valor_outras_despesas,
        nvl(m.valor_frete_rateio, 0)    as valor_frete_rateio,
        nvl(m.valor_outros, 0)          as valor_outros,
        m.data_movimento
      from {{ ref('stg_movimentacao') }} m
     inner join notas_venda nv
        on nv.id_transacao_venda = m.id_transacao_venda
       and nv.id_filial          = m.id_filial
     cross join periodo pe
     where m.data_cancelamento is null
       and m.codigo_operacao in ('S', 'SM', 'SB')
       and m.data_movimento >= pe.data_inicio
       and m.data_movimento <  pe.data_fim
       and m.id_cliente not in (select id_cliente from cliente_proprio)
),

mov_completo as (
    select
        id_transacao_item,
        valor_subtotal_item
      from {{ ref('stg_mov_complemento') }}
),

faturamento_item as (
    select
        mv.id_produto,
        mv.id_cliente,
        mv.id_regiao,
        mv.data_movimento,
        mv.quantidade,
        nvl(
            round(mc.valor_subtotal_item, 2),
            round(
                mv.quantidade * (
                    mv.preco_unitario + mv.valor_frete + mv.valor_outras_despesas
                    + mv.valor_frete_rateio + mv.valor_outros
                ), 2
            )
        ) as valor_item
      from movimentacao mv
      left join mov_completo mc
        on mc.id_transacao_item = mv.id_transacao_item
),

final as (
    select
        trunc(f.data_movimento) as dia,
        f.id_produto,
        sum(f.quantidade) as quantidade_total,
        sum(f.valor_item) as valor_total,
        count(distinct case when rg.nome_regiao = 'ATACADO' then f.id_cliente end) as quantidade_clientes_atacado,
        count(distinct case when rg.nome_regiao = 'VAREJO'  then f.id_cliente end) as quantidade_clientes_varejo
      from faturamento_item f
      left join regiao rg
        on rg.id_regiao = f.id_regiao
     group by trunc(f.data_movimento), f.id_produto
)

select * from final
