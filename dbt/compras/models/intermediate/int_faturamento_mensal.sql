-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: CTEs `regioes`, `notas_venda`, `movimentacao`, `mov_completo`,
-- `faturamento_item`, `faturamento_mensal`, relatorios_compras/query_mensal.py
-- (conferido também contra app_relatorios/relatorios/compras_mensal.py).
--
-- Grão: mês × produto. Faturamento BRUTO (sem descontar devolução) - o líquido
-- nasce em int_venda_mensal, que soma este model com int_devolucao_mensal.
--
-- Pontos que não podem escorregar (CONTEXTO.md e cabeçalho do agente):
--   * codoper IN ('S','SM','SB') = venda, venda manual, bonificação. ST
--     (transferência) e SD (devolução a fornecedor) NÃO são faturamento.
--   * DECODE(condvenda, 7, qtcont, qt) - venda futura (condvenda=7) mede pela
--     quantidade CONTRATADA, não pela quantidade do movimento.
--   * o vínculo é com a NOTA FISCAL (numtransvenda + codfilial), não com o
--     item do pedido - exigir item em pcpedi descartava venda legítima.
--   * exclusão de clientes_proprios: transferência entre filiais não é venda.
--   * valor = NVL(ROUND(vlsubtotitem,2), ROUND(qt*(punit+frete+outras+
--     frete_rateio+outros),2)) - vlsubtotitem é a fonte preferida.
--   * intervalo semiaberto (>= inicio AND < fim) no filtro de data. Os limites
--     vêm de int_periodo_mensal (ref, uma linha), não mais da macro
--     compras_periodo_inicio()/fim() expandida direto aqui - ver o cabeçalho de
--     int_periodo_mensal para o porquê (janela dessincronizada em build parcial).
-- ─────────────────────────────────────────────────────────────────────────────

with regiao as (
    select * from {{ ref('stg_regiao') }}
),

cliente_proprio as (
    select * from {{ ref('int_cliente_proprio') }}
),

-- Janela mensal lida de int_periodo_mensal (uma linha), nao mais da macro
-- expandida direto aqui - ver cabecalho de int_periodo_mensal para o porque.
periodo as (
    select * from {{ ref('int_periodo_mensal') }}
),

-- Notas de saida validas, no mesmo criterio da rotina 1464.
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

-- O vinculo e com a NOTA FISCAL, nao com o item do pedido (mesmo criterio da
-- 1464). Cliente e regiao saem da propria pcmov, que os tem 100% preenchidos.
movimentacao as (
    select
        m.id_transacao_venda,
        m.id_transacao_item,
        m.id_produto,
        m.id_cliente,
        m.id_regiao,
        -- condvenda 7 (venda futura) mede pela quantidade contratada
        decode(nv.condicao_venda, 7, m.quantidade_contratada, m.quantidade) as quantidade,
        m.preco_unitario,
        nvl(m.valor_frete, 0)         as valor_frete,
        nvl(m.valor_outras_despesas, 0) as valor_outras_despesas,
        nvl(m.valor_frete_rateio, 0)  as valor_frete_rateio,
        nvl(m.valor_outros, 0)        as valor_outros,
        m.data_movimento
      from {{ ref('stg_movimentacao') }} m
     inner join notas_venda nv
        on nv.id_transacao_venda = m.id_transacao_venda
       and nv.id_filial          = m.id_filial
     cross join periodo pe
     where m.data_cancelamento is null
       -- S/SM/SB = venda, venda manual e bonificacao. ST (transferencia) e SD
       -- (devolucao a fornecedor) nao sao faturamento.
       and m.codigo_operacao in ('S', 'SM', 'SB')
       and m.data_movimento >= pe.data_inicio
       and m.data_movimento <  pe.data_fim
       -- transferencia entre filiais nao e faturamento
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
        trunc(f.data_movimento, 'MM') as mes,
        f.id_produto,
        sum(f.quantidade) as quantidade_total,
        sum(f.valor_item) as valor_total,
        count(distinct case when rg.nome_regiao = 'ATACADO' then f.id_cliente end) as quantidade_clientes_atacado,
        count(distinct case when rg.nome_regiao = 'VAREJO'  then f.id_cliente end) as quantidade_clientes_varejo
      from faturamento_item f
      left join regiao rg
        on rg.id_regiao = f.id_regiao
     group by trunc(f.data_movimento, 'MM'), f.id_produto
)

select * from final
