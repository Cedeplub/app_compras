-- Testa que (mes, id_produto) é único em int_faturamento_mensal.
-- Duplicata aqui dobra quantidade_total/valor_total no join com
-- int_venda_mensal, inflando faturamento líquido do SKU no mês. Sem
-- dbt_utils no projeto, o grão composto vira teste singular.

select
    mes,
    id_produto,
    count(*) as n
from {{ ref('int_faturamento_mensal') }}
group by mes, id_produto
having count(*) > 1
