-- Testa que (mes, codigo_produto) é único em int_venda_mensal.
-- Duplicata aqui multiplica a linha em qualquer join a jusante (marts) e
-- dobra quantidade/valor do SKU no mês. Sem dbt_utils no projeto, o grão
-- composto vira teste singular.

select
    mes,
    codigo_produto,
    count(*) as n
from {{ ref('int_venda_mensal') }}
group by mes, codigo_produto
having count(*) > 1
