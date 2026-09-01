-- Testa que (mes, id_produto) é único em int_devolucao_mensal.
-- Duplicata aqui dobra quantidade_devolucao/valor_devolucao no join com
-- int_venda_mensal, subtraindo devolução em dobro do líquido do SKU no mês.
-- Sem dbt_utils no projeto, o grão composto vira teste singular.

select
    mes,
    id_produto,
    count(*) as n
from {{ ref('int_devolucao_mensal') }}
group by mes, id_produto
having count(*) > 1
