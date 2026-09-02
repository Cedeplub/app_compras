-- REGIME_FISCAL só pode ser nulo exatamente onde MODALIDADE também é —
-- as duas saem da MESMA linha da aba dICMS (dim_tributacao), buscada pelo
-- mesmo COD_ICMS (BJ). Se uma existe e a outra não, o join foi feito por outra
-- chave.
--
-- Falha que este teste previne: o produto carrega DOIS códigos de tributação
-- independentes, o de ICMS e o de PIS/COFINS (ver o cabeçalho de
-- dim_tributacao), e int_cadastro_estoque ainda expõe um TERCEIRO texto, a
-- descrição da PCTRIB do WinThor. Juntar por qualquer um deles devolve texto
-- plausível — um regime de verdade, escrito em português, que a tela mostraria
-- sem piscar — mas de OUTRA linha fiscal que não é a que calculou o imposto
-- daquele SKU. Nenhum teste de nulo ou de grão pega isso; o casamento com
-- MODALIDADE pega, porque MODALIDADE vem da linha certa por construção
-- (fat_pedido, coluna BL).
--
-- Hoje as duas são nulas nos mesmos 5 SKUs: os de codst = 0 em PCTABTRIB
-- (CONTEXTO.md §6.2), que são também os 5 que recebem o alerta TRIB
-- (§6.4, decisão 3).

select
    p.CODIGO,
    p.COD_ICMS,
    p.MODALIDADE,
    c.REGIME_FISCAL
  from {{ ref('compras_pedido') }} p
  join {{ ref('compras_produto_contexto') }} c
    on c.CODIGO = p.CODIGO
 where (p.MODALIDADE is null     and c.REGIME_FISCAL is not null)
    or (p.MODALIDADE is not null and c.REGIME_FISCAL is null)
