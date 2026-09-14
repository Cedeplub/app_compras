{{ config(severity = 'warn') }}
-- Aviso de COBERTURA, não invariante de dado.
--
-- `compras_pedido_unidades_usa_fator_congelado` prova a MELHORIA A5 (REGRAS.md
-- §6.1 item 5) comparando `int_produto_pedido` com a soma
-- QUANTIDADE x FATOR_EXIBICAO lida direto de APP_PEDIDO_ITEM. Com a tabela
-- VAZIA, o braço que cobre a regra não tem o que comparar e passa por vazio —
-- verde sem ter medido nada. Foi o estado do sistema em 14/09/2026: a única
-- mudança de lógica da migração (§9.2) estava com cobertura zero de dado.
--
-- Este teste torna esse silêncio audível. É `warn`, nunca `error`, de propósito:
-- "nenhum pedido gravado" é estado legítimo — o sistema acabou de subir, ou os
-- pedidos do mês foram apagados —, e derrubar o build diário por causa disso
-- seria inventar uma regra de negócio que ninguém pediu. O que não pode é a
-- falta de cobertura passar despercebida.
--
-- Some sozinho assim que existir um item gravado.
select
    'APP_PEDIDO_ITEM vazia: A5 (fator congelado) segue SEM cobertura de dado' as aviso,
    count(*) as itens
  from {{ source('compras_app', 'app_pedido_item') }}
having count(*) = 0
