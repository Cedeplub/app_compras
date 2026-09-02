-- ─────────────────────────────────────────────────────────────────────────────
-- int_devolucao_diaria — irmão em grão DIA de int_devolucao_mensal (v2 Etapa
-- 10, tela Monitoramento). MESMO critério da rotina 1464, mesma cópia
-- deliberada (não um novo cálculo) - só o TRUNC muda de 'MM' para dia, e a
-- janela vem de int_periodo_diario. Ver o cabeçalho de int_devolucao_mensal.sql
-- para a explicação de cada filtro, inclusive por que `notas_saida_cv` NÃO
-- leva filtro de data (a venda original pode ser muito mais antiga que a
-- janela diária).
--
-- Grão: dia × produto. Devolução BRUTA - o líquido nasce em int_venda_diaria.
-- ─────────────────────────────────────────────────────────────────────────────

with cliente_proprio as (
    select * from {{ ref('int_cliente_proprio') }}
),

cliente as (
    select * from {{ ref('stg_cliente') }}
),

periodo as (
    select * from {{ ref('int_periodo_diario') }}
),

devolucao_notas_entrada as (
    select
        n.id_transacao_entrada,
        n.id_cliente_devolucao as id_cliente,
        n.id_filial,
        n.data_entrada
      from {{ ref('stg_nota_entrada') }} n
     cross join periodo pe
     where n.data_cancelamento is null
       and n.tipo_descarga in ('6', '7', 'T')
       and nvl(n.codigo_fiscal, 0) in (131, 132, 231, 232, 199, 299)
       and nvl(n.tipo_movimento_garantia, -1) = -1
       and nvl(n.observacao, 'X') <> 'NF CANCELADA'
       and n.id_cliente_devolucao not in (select id_cliente from cliente_proprio)
       and n.data_entrada >= pe.data_inicio
       and n.data_entrada <  pe.data_fim
),

entrada_complemento as (
    select
        id_transacao_entrada,
        id_transacao_venda
      from {{ ref('stg_estoque_complemento') }}
),

devolucao_mov as (
    select
        id_transacao_item,
        id_transacao_entrada,
        id_produto,
        codigo_operacao,
        case
            when nvl(quantidade, 0) = 0 and tipo_mercadoria = 'L'
            then nvl(quantidade_contratada, 0)
            else nvl(quantidade, 0)
        end as quantidade_efetiva,
        nvl(quantidade, 0) as quantidade,
        coalesce(nullif(preco_unitario, 0), preco_unitario_contratado) as preco_unitario_eff,
        nvl(valor_frete, 0) as valor_frete,
        nvl(valor_outras_despesas, 0) as valor_outras_despesas,
        nvl(valor_frete_rateio, 0) as valor_frete_rateio,
        nvl(valor_outros, 0) as valor_outros,
        nvl(valor_repasse, 0) as valor_repasse,
        nvl(valor_st, 0) as valor_st,
        nvl(custo_financeiro, 0) as custo_financeiro
      from {{ ref('stg_movimentacao') }}
     where data_cancelamento is null
       and codigo_operacao = 'ED'
),

notas_saida_cv as (
    select
        id_transacao_venda,
        condicao_venda
      from {{ ref('stg_nota_saida') }}
     where data_cancelamento is null
       and nvl(tipo_venda, 'X') not in ('SR', 'DF')
),

mov_completo_devol as (
    select
        id_transacao_item,
        nvl(bonificacao, 'N') as bonificacao,
        nvl(valor_st_transferencia_cd, 0) as valor_st_transferencia_cd,
        nvl(valor_fecp, 0) as valor_fecp,
        nvl(valor_fecp_transferencia_cd, 0) as valor_fecp_transferencia_cd
      from {{ ref('stg_mov_complemento') }}
),

devolucao_calc as (
    select
        b.data_entrada,
        b.id_cliente,
        dm.id_produto,
        dm.quantidade_efetiva,
        dm.quantidade,
        dm.codigo_operacao,
        nvl(nscv.condicao_venda, 0) as condicao_venda,
        nvl(mcd.bonificacao, 'N') as bonificacao,
        dm.valor_repasse,
        dm.valor_st + nvl(mcd.valor_st_transferencia_cd, 0)
            + nvl(mcd.valor_fecp, 0) + nvl(mcd.valor_fecp_transferencia_cd, 0) as st_fecp_unit,
        case when nvl(nscv.condicao_venda, 0) in (5, 6, 11) then 0 else 1 end as flag_venda_normal,
        case
            when nvl(nscv.condicao_venda, 0) in (5, 6, 11)
                then 0
            when nvl(nscv.condicao_venda, 0) = 1 and nvl(mcd.bonificacao, 'N') = 'N'
                then dm.preco_unitario_eff + dm.valor_frete + dm.valor_outras_despesas
                                            + dm.valor_frete_rateio + dm.valor_outros
            when nvl(nscv.condicao_venda, 0) = 1 and nvl(mcd.bonificacao, 'N') <> 'N'
                then 0
            else
                dm.preco_unitario_eff + dm.valor_frete + dm.valor_outras_despesas
                                       + dm.valor_frete_rateio + dm.valor_outros
        end as preco_calc_unit
      from devolucao_notas_entrada b
     inner join entrada_complemento ec
        on ec.id_transacao_entrada = b.id_transacao_entrada
     inner join devolucao_mov dm
        on dm.id_transacao_entrada = b.id_transacao_entrada
     inner join cliente cli
        on cli.id_cliente = b.id_cliente
      left join notas_saida_cv nscv
        on nscv.id_transacao_venda = ec.id_transacao_venda
      left join mov_completo_devol mcd
        on mcd.id_transacao_item = dm.id_transacao_item
     where nvl(ec.id_transacao_venda, 0) <> 0
       and nvl(nscv.condicao_venda, 0) not in (4, 8, 10, 13, 20, 98, 99)
),

devolucao_final as (
    select
        dc.data_entrada,
        dc.id_produto,
        dc.quantidade_efetiva,
        dc.quantidade_efetiva * dc.preco_calc_unit as valor_devolucao,
        (dc.quantidade_efetiva * dc.preco_calc_unit)
            - (dc.flag_venda_normal * dc.valor_repasse)
            - (dc.flag_venda_normal * dc.st_fecp_unit)
            + round(
                dc.quantidade * case
                    when dc.condicao_venda in (5, 6, 11, 12) then 0
                    when dc.codigo_operacao = 'SB'            then 0
                    else dc.st_fecp_unit
                end,
              2) as valor_devolucao1
      from devolucao_calc dc
),

final as (
    select
        trunc(df.data_entrada) as dia,
        df.id_produto,
        sum(df.quantidade_efetiva) as quantidade_devolucao,
        sum(df.valor_devolucao) as valor_devolucao,
        sum(df.valor_devolucao1) as valor_devolucao_liq
      from devolucao_final df
     group by trunc(df.data_entrada), df.id_produto
)

select * from final
