-- Testa que (mes, id_produto) é único em int_dias_sem_estoque_mensal.
-- Duplicata aqui dobra dias_sem_estoque no join com int_venda_mensal, o que
-- se propaga para a taxa de ruptura do SKU no mês. Sem dbt_utils no projeto,
-- o grão composto vira teste singular.

select
    mes,
    id_produto,
    count(*) as n
from {{ ref('int_dias_sem_estoque_mensal') }}
group by mes, id_produto
having count(*) > 1
