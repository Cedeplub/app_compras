-- Testa que cada combinação (id_produto, id_filial) é única em stg_estoque.
-- Se houver duplicatas, multiplica a linha no join com movimentação e erra a posição de estoque.
-- ~70k linhas, roda em ~1s.

select
    id_produto,
    id_filial,
    count(*) as n
from {{ ref('stg_estoque') }}
group by id_produto, id_filial
having count(*) > 1
