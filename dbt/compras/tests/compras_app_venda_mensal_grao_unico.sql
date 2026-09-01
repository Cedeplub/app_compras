-- Testa que (MES, CODIGO_PRODUTO) é único em COMPRAS_VENDA_MENSAL — o grão
-- declarado no cabeçalho do model, e o único da camada `app` que NÃO é o SKU.
--
-- Falha que este teste previne: o grão composto já é testado em
-- int_venda_mensal (compras_venda_mensal_grao_unico.sql), e hoje a camada de
-- contrato é projeção pura, então o grão é herdado. "Hoje" é a palavra que
-- torna o teste necessário: no dia em que alguém acrescentar aqui um join
-- (para trazer o departamento de dim_produto, por exemplo), a duplicata
-- apareceria SÓ nesta tabela, e nenhum teste da camada intermediate a veria.
-- Quem consome é o dashboard, e uma linha duplicada aqui dobra quantidade e
-- valor do SKU no mês em toda tela de histórico.
--
-- Sem dbt_utils no projeto, grão composto vira teste singular - mesma solução
-- adotada para int_venda_mensal.

select
    MES,
    CODIGO_PRODUTO,
    count(*) as n
from {{ ref('compras_venda_mensal') }}
group by MES, CODIGO_PRODUTO
having count(*) > 1
