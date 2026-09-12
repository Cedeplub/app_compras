-- Previne: FATOR_EXIBICAO zero ou negativo.
--
-- Ele é DIVISOR de EST_DISP, PENDENTE, QT_ULT_ENT, EST_FABRICA e de todas as
-- colunas de venda (CONTEXTO.md regra 6). Zero derruba o build inteiro com
-- ORA-01476 no meio de int_produto_demanda, sem dizer de onde veio; negativo é
-- pior, porque não dá erro nenhum - inverte o sinal de estoque e de demanda e
-- o pedido sugerido sai calculado em cima de números invertidos.
--
-- A origem possível é EMBAL_COMPRA (PCPRODUT.QTUNITCX) vir 0 num SKU de
-- fornecedor MASTER. Hoje não acontece em nenhum dos 8.776 SKUs, e é
-- exatamente por isso que o model não carrega uma guarda defensiva na fórmula:
-- guarda silenciosa esconderia um cadastro errado. Aqui a falha é alta e diz
-- qual SKU consertar no WinThor.

with base as (
    select * from {{ ref('int_produto_base') }}
)

select
    codigo,
    fornecedor,
    embal_compra,
    fator_exibicao
  from base
 where fator_exibicao is null
    or fator_exibicao <= 0
