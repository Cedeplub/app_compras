-- Reconciliação entre a cadeia DIÁRIA nova (int_venda_diaria, v2 Etapa 10) e a
-- cadeia MENSAL já validada contra a rotina 1464 (int_venda_mensal): somando
-- VALOR_LIQUIDO/QUANTIDADE_LIQUIDA por (mês, produto) a partir dos dias, o
-- resultado tem que bater com int_venda_mensal, produto a produto, em
-- qualquer mês que as duas janelas cubram em comum. Isso prova que a cópia da
-- lógica de negócio em grão dia (int_faturamento_diario/int_devolucao_diaria)
-- não divergiu da versão mês, e é o jeito mais barato de flagrar um copy-paste
-- errado sem reconstruir tudo à mão.
--
-- Só compara MESES FECHADOS dos dois lados (mesmo motivo do critério de
-- int_venda_mensal contra query_mensal.py, CONTEXTO.md §6.3): o mês corrente
-- está em andamento nas duas cadeias e diverge por sincronia, não por defeito.
-- Também só compara onde a janela DIÁRIA (mais curta,
-- compras_monitoramento_dias_historico) cobre o mês INTEIRO - mês em que a
-- janela diária começa no meio fica com soma diária menor por CONSTRUÇÃO
-- (faltam dias antes do início da janela), não por erro.

with diaria as (
    select
        trunc(dia, 'MM') as mes,
        codigo_produto,
        sum(quantidade_liquida) as quantidade_liquida,
        sum(valor_liquido)      as valor_liquido,
        min(dia)                as primeiro_dia_no_mes
      from {{ ref('int_venda_diaria') }}
     group by trunc(dia, 'MM'), codigo_produto
),

periodo_diario as (
    select * from {{ ref('int_periodo_diario') }}
),

mensal as (
    select mes, codigo_produto, quantidade_liquida, valor_liquido
      from {{ ref('int_venda_mensal') }}
),

comparavel as (
    select d.*
      from diaria d
     cross join periodo_diario pe
     where d.mes < trunc(sysdate, 'MM')                 -- só mês fechado
       and d.mes >= trunc(add_months(pe.data_inicio, 1), 'MM')  -- só mês coberto inteiro pela janela diária
)

select
    c.mes,
    c.codigo_produto,
    c.quantidade_liquida as qtd_diaria,
    m.quantidade_liquida as qtd_mensal,
    c.valor_liquido       as valor_diario,
    m.valor_liquido        as valor_mensal
  from comparavel c
  join mensal m
    on m.mes = c.mes
   and m.codigo_produto = c.codigo_produto
 where abs(nvl(c.quantidade_liquida, 0) - nvl(m.quantidade_liquida, 0)) > 0.01
    or abs(nvl(c.valor_liquido, 0) - nvl(m.valor_liquido, 0)) > 0.01
