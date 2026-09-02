-- Testa que CODIGO é único em COMPRAS_PRODUTO_CONTEXTO — o grão declarado no
-- cabeçalho do model, 1 linha por SKU.
--
-- Falha que este teste previne: o model tem QUATRO left joins (dim_tributacao,
-- int_cadastro_estoque e duas leituras de int_venda_mensal). Qualquer um deles
-- que perca o grão do lado direito — uma segunda linha de tributação para o
-- mesmo código, um SKU repetido em int_cadastro_estoque por causa de filial,
-- uma segunda linha do mesmo mês em int_venda_mensal — duplica a linha do SKU
-- AQUI e em nenhum outro lugar. O serviço da API junta esta tabela por
-- CODIGO em left join contra COMPRAS_PEDIDO: uma duplicata aqui multiplica a
-- linha do produto na tela de Precificação, que é uma listagem.
--
-- O `unique` do schema.yml cobre a mesma invariante; este teste existe para
-- ela ficar escrita junto do motivo, no mesmo padrão de
-- compras_app_venda_mensal_grao_unico.

select
    CODIGO,
    count(*) as n
from {{ ref('compras_produto_contexto') }}
group by CODIGO
having count(*) > 1
