-- Prova que a camada de contrato não perdeu nem inventou linha: COMPRAS_PEDIDO
-- e fat_pedido têm o MESMO conjunto de CODIGO, nos dois sentidos.
--
-- Falha que este teste previne: compras_pedido é projeção pura de fat_pedido
-- (sem where, sem join) - mas um filtro esquecido, um join acidental num
-- refactor futuro, ou uma junção que quebre o grão silenciosamente faria a
-- camada de contrato divergir da fonte sem que nenhum outro teste percebesse
-- (os testes de fat_pedido validam fat_pedido, não o espelho).
--
-- ⚠ Oracle: MINUS e UNION ALL têm a MESMA precedência e associam à esquerda.
-- `A minus B union all B minus A` NÃO isola os dois lados - o Oracle lê como
-- `((A minus B) union all B) minus A`. MEDIDO no banco em 24/08/2026 com
-- A={1,2,3} e B={2,3,4}: sem parênteses o resultado é {4}, com parênteses é
-- {1,4}. Ou seja, a forma sem parênteses ANULA A MENOS B - a PERDA, o código
-- que existe em fat_pedido e sumiu do espelho - e deixa passar só o excesso.
-- Exatamente o defeito que a injeção de teste desta etapa (remover uma linha
-- de compras_pedido) produz, e que passaria despercebido. Por isso os dois
-- lados vão PARENTIZADOS explicitamente abaixo.

(
    select codigo from {{ ref('fat_pedido') }}
    minus
    select CODIGO as codigo from {{ ref('compras_pedido') }}
)
union all
(
    select CODIGO as codigo from {{ ref('compras_pedido') }}
    minus
    select codigo from {{ ref('fat_pedido') }}
)
