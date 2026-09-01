-- Testa que ST_SUBSTITUTO sempre tem MVA preenchida em seed_icms.
-- Se MVA for nula em MODALIDADE='ST_SUBSTITUTO', o custo total oficial fica branco
-- e apaga a cadeia de preço inteira daquele SKU.
-- Falha crítica: qualquer produto com ST fica sem preço.

select *
from {{ ref('seed_icms') }}
where MODALIDADE = 'ST_SUBSTITUTO'
  and MVA is null
