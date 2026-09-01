-- Testa que não há duplicatas na chave (FORNECEDOR, COD_ICMS) em seed_credito.
-- Duplicata em (FORNECEDOR, COD_ICMS) multiplica linhas no join da etapa 3
-- e calcula crédito duplicado, dobrando o impacto no preço final.

select
    FORNECEDOR,
    COD_ICMS,
    count(*) as n
from {{ ref('seed_credito') }}
group by FORNECEDOR, COD_ICMS
having count(*) > 1
