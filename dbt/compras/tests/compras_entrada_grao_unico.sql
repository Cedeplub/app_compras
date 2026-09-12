-- Testa que id_transacao_item é único em int_entrada_produto. Duplicata aqui
-- dobra quantidade/valor de uma entrada na tela (mesma classe de defeito do
-- compras_venda_mensal_grao_unico.sql, aplicada ao grão desta cadeia: item de
-- movimento, não dia x produto).

select
    id_transacao_item,
    count(*) as n
  from {{ ref('int_entrada_produto') }}
 group by id_transacao_item
having count(*) > 1
