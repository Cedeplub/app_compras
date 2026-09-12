-- Soma de Q00..Q11 de um SKU tem que bater com a soma de quantidade_liquida
-- dos 12 meses fechados correspondentes (mesmo offset 0..11) em
-- int_venda_mensal. Falha aqui pega erro no cálculo do offset_mes ou na
-- agregação condicional do pivot.

with venda_mensal as (
    select * from {{ ref('int_venda_mensal') }}
),

mes_ref as (
    select max(mes) as mes_atual from venda_mensal
),

soma_origem as (
    select
        v.codigo_produto,
        sum(v.quantidade_liquida) as soma_q
      from venda_mensal v
     cross join mes_ref r
     where round(months_between(r.mes_atual, v.mes)) - 1 between 0 and 11
     group by v.codigo_produto
),

soma_pivot as (
    select
        codigo_produto,
        q00+q01+q02+q03+q04+q05+q06+q07+q08+q09+q10+q11 as soma_q
      from {{ ref('int_venda_mensal_pivot') }}
)

select
    o.codigo_produto,
    o.soma_q as soma_origem,
    p.soma_q as soma_pivot
  from soma_origem o
  join soma_pivot p on p.codigo_produto = o.codigo_produto
 where abs(nvl(o.soma_q, 0) - nvl(p.soma_q, 0)) > 0.01
