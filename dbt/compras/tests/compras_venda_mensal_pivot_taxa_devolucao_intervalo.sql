{{ config(severity = 'warn') }}

-- TX_DEVOLUCAO_3M e' uma proporcao (devolvido/faturado, offsets 0..2) e
-- normalmente fica entre 0 e 1. Medido contra o dado real em 20/08/2026:
-- > 1 acontece de verdade quando o cliente devolve, dentro da janela de 3
-- meses, unidades vendidas ANTES da janela (codigo_produto 810, 6927 e 7095 -
-- quantidade_devolucao supera quantidade_total do trimestre em
-- int_venda_mensal, e quantidade_liquida do mes fica ate negativa). E'
-- comportamento real do dado, nao erro de porte - por isso severidade WARN:
-- o build nao quebra por um evento legitimo, mas o caso continua visivel.
-- < 0 nunca deveria acontecer (faturado bruto e devolvido bruto sao sempre
-- >= 0) - se aparecer, e' o mesmo WARN acusando, e vale investigar de fato.

select codigo_produto, tx_devolucao_3m
  from {{ ref('int_venda_mensal_pivot') }}
 where tx_devolucao_3m < 0 or tx_devolucao_3m > 1
