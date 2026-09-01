-- Testa que int_cliente_proprio tem pelo menos 1 linha.
-- Se essa tabela vier vazia, o `not in (select id_cliente from cliente_proprio)`
-- de int_faturamento_mensal (e a exclusão equivalente em int_devolucao_mensal)
-- passa a ser verdadeiro para TODA linha - transferência entre filiais entra
-- como venda e o faturamento infla para o catálogo inteiro, sem erro nenhum.

select 'int_cliente_proprio esta vazio' as motivo
  from dual
 where not exists (select 1 from {{ ref('int_cliente_proprio') }})
