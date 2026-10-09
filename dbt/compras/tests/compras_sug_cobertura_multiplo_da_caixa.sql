-- Testa que SUG_COBERTURA (coluna AZ) é sempre um múltiplo da CAIXA DE COMPRA,
-- expressa na unidade de exibição, e que o arredondamento é só PARA CIMA.
--
-- Origem: feedback do Diretor de Compras em 09/10/2026, item 2. Ele mediu 370
-- das 805 sugestões fora do múltiplo, e deu o SKU 109 como exemplo: vem em
-- caixa 24x1 e recebia sugestão de unidade solta. Sugerir um número que não se
-- pode comprar obriga a refazer a conta à mão em toda linha.
--
-- A caixa, na unidade de exibição, é `embal_compra / fator_exibicao`:
--   * item MASTER (fator = embal_compra) → dá 1, e qualquer inteiro já é
--     múltiplo. O teste passa de graça neles, que é o correto: medido em
--     09/10/2026, 359 dos 806 ativos com sugestão estão nesse caso;
--   * item em unidade (fator 1, caixa 24) → dá 24, e é neles que a regra vale.
--
-- Dois ramos:
--
--   1. MÚLTIPLO. `mod(sug, caixa) <> 0` reprova. É a afirmação direta.
--
--   2. PARA CIMA, NUNCA PARA BAIXO. A sugestão arredondada não pode ser MENOR
--      que a bruta: arredondar para baixo entregaria menos cobertura do que o
--      alvo pede, que é o oposto do que a sugestão existe para fazer. Este
--      ramo pega a troca de `ceil` por `round` ou `floor` — que mantém o
--      múltiplo e continua passando no ramo 1.
--
-- ⚠ ESTE TESTE DECLARA UM DESVIO DA PLANILHA. A V11 para no
-- `MAX(0, ROUND(...))` e não conhece a caixa de compra. A comparação célula a
-- célula de validar/validar_pedido.py passa a divergir em SUG_COBERTURA nos
-- SKUs cuja sugestão subiu — medido: 379 dos 4.552 ativos. Divergência
-- DELIBERADA, decidida com o usuário em 09/10/2026.
--
-- A tolerância de 0,0001 no ramo 2 existe porque `media_janela * alvo` é
-- NUMBER e a diferença pode carregar resíduo de arredondamento; não é folga
-- de medida, é folga de ponto flutuante.

with demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

base as (
    select * from {{ ref('int_produto_base') }}
),

com_caixa as (
    select
        d.codigo,
        d.sug_cobertura,
        -- a bruta, antes do arredondamento para a caixa
        greatest(0, round(d.media_janela * d.cobertura_alvo - d.est_pend, 0)) as bruta,
        b.embal_compra / nullif(b.fator_exibicao, 0)                         as caixa
      from demanda d
      join base b on b.codigo = d.codigo
)

select
    codigo,
    'sugestao nao e multiplo da caixa de compra' as motivo
  from com_caixa
 where caixa is not null
   and caixa > 1
   and sug_cobertura > 0
   and mod(sug_cobertura, caixa) <> 0

union all

select
    codigo,
    'sugestao arredondou para BAIXO' as motivo
  from com_caixa
 where sug_cobertura < bruta - 0.0001
