-- Prova que COMPRAS_PRODUTO_CONTEXTO e COMPRAS_PEDIDO têm o MESMO conjunto de
-- CODIGO, nos dois sentidos.
--
-- Falha que este teste previne: o serviço da API junta as duas por LEFT JOIN
-- em CODIGO (mesmo molde de COMPRAS_IND_FORNECEDOR). Um SKU que exista em
-- COMPRAS_PEDIDO e falte aqui não dá erro nenhum: a tela de Decisão do SKU
-- simplesmente abre com regime fiscal, quantidade da última saída e venda do
-- ano passado em branco, como se o produto não tivesse nenhum dos três — e
-- "campo vazio" é indistinguível de "campo nulo por regra" a olho nu. O
-- sentido inverso (SKU aqui e não lá) denuncia espinha errada: este model tem
-- de nascer de fat_pedido, não de um cadastro mais largo.
--
-- ⚠ Oracle: MINUS e UNION ALL têm a MESMA precedência e associam à esquerda,
-- então `A minus B union all B minus A` NÃO isola os dois lados — o Oracle lê
-- `((A minus B) union all B) minus A`, o que ANULA a perda (A menos B) e
-- deixa passar só o excesso. É a mesma armadilha documentada em
-- compras_app_pedido_espelha_fat.sql, medida no banco em 24/08/2026. Por isso
-- os dois lados vão PARENTIZADOS.

(
    select CODIGO from {{ ref('compras_pedido') }}
    minus
    select CODIGO from {{ ref('compras_produto_contexto') }}
)
union all
(
    select CODIGO from {{ ref('compras_produto_contexto') }}
    minus
    select CODIGO from {{ ref('compras_pedido') }}
)
