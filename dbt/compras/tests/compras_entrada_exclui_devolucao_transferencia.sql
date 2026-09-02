-- Previne: alguém alargar o filtro `codigo_operacao in ('E','EB')` de
-- int_entrada_compra.sql e deixar entrar 'ED' (devolução de cliente - domínio
-- de int_devolucao_mensal, CODFORNEC ali é CODCLI) ou 'ET'/'ER' (transferência
-- entre filiais / regularização de estoque - nenhum dos dois é compra, ver o
-- cabeçalho do model). Junta de volta em stg_movimentacao (nunca direto no
-- CEDEP - REGRAS.md) via id_transacao_item porque int_entrada_compra não
-- expõe codigo_operacao (decisão de escopo: a tela só precisa de
-- tipo_entrada COMPRA/BONIFICACAO).

select m.id_transacao_item, m.codigo_operacao
  from {{ ref('int_entrada_compra') }} e
  join {{ ref('stg_movimentacao') }} m
    on m.id_transacao_item = e.id_transacao_item
 where m.codigo_operacao not in ('E', 'EB')
