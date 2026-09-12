-- Testa o grão declarado de fat_alerta: 1 linha por SKU x TIPO DE ALERTA.
--
-- Falha que ele previne: fat_alerta existe para o dashboard CONTAR alertas sem
-- dar parsing na string da coluna D. Uma linha duplicada não quebra tela
-- nenhuma - ela só faz o painel dizer "182 produtos com ruptura" onde há 91.
-- Número inflado em card de dashboard é o tipo de erro que ninguém percebe até
-- alguém conferir na mão.
--
-- A duplicata mais provável vem de fan-out no join de recorte (fornecedor,
-- comprador, classe): hoje ele é contra fat_pedido, que tem grão de SKU, mas
-- trocar essa fonte por um model de grão diferente multiplicaria toda linha em
-- silêncio. Não há chave composta nativa no dbt sem pacote externo, então o
-- teste é singular.

select
    codigo,
    tipo_alerta,
    count(*) as qtd_linhas
  from {{ ref('fat_alerta') }}
 group by codigo, tipo_alerta
having count(*) > 1
