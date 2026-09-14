-- ─────────────────────────────────────────────────────────────────────────────
-- stg_decisao_pedido — a decisão de COMPRA que volta da aplicação para o modelo.
-- Alimenta a coluna BA (`PEDIDO`) do gabarito de 122 colunas, via
-- int_produto_pedido, e por consequência BB, BC, BD, BE e BF.
--
-- ── ⚠ MUDANÇA DE FONTE (12/09/2026) ──────────────────────────────────────────
-- Até 12/09/2026 este model lia `APP_DECISAO_PEDIDO`, escrita SÓ pela tela v1.
-- A v1 saiu do projeto e a tabela morreu: último `GRAVAR_DECISAO_PEDIDO` da
-- auditoria em 25/08/2026, 4 linhas. A v2 grava o pedido em APP_PEDIDO +
-- APP_PEDIDO_ITEM, que não entravam em model nenhum da cadeia do fat_pedido —
-- ou seja, a decisão de pedido da v2 NUNCA chegava ao fat_pedido. Medido em
-- 12/09/2026: `FAT_PEDIDO` com 4 linhas de `PEDIDO <> 0` em 8.841, as quatro
-- da tabela morta; `APP_PEDIDO_ITEM` com 66 itens em 4 pedidos.
-- A troca de fonte mata a tabela velha e fecha a lacuna no mesmo movimento.
--
-- ── ⚠ O GRÃO MUDOU: a soma é em unidade REAL, nunca em unidade de exibição ───
-- A tabela velha tinha PK em ID_PRODUTO — uma linha por produto, e `unidades`
-- era só `PEDIDO x FATOR_EXIBICAO`. APP_PEDIDO_ITEM tem PK (ID_PEDIDO,
-- ID_PRODUTO): o MESMO SKU pode aparecer em dois pedidos, e cada item carrega
-- o SEU fator congelado. Hoje convivem fatores 1, 6 e 12 entre os 66 itens.
-- Somar QUANTIDADE entre itens de fatores diferentes soma CAIXA com UNIDADE e
-- produz um número que não é nada — 10 caixas de 12 mais 5 unidades não são
-- "15" de coisa alguma. Por isso a agregação é
-- `sum(QUANTIDADE * FATOR_EXIBICAO)`: unidade real é a única grandeza comum, e
-- é ela que BB (`PEDIDO_UNIDADES`) sempre significou.
--
-- ── O fator congelado sobrevive (MELHORIA A5) ────────────────────────────────
-- `APP_PEDIDO_ITEM.FATOR_EXIBICAO` é NOT NULL e é snapshot do instante da
-- gravação da linha — a mesma garantia que a tabela velha dava, e o que torna
-- esta troca possível sem mexer na regra 6 do CONTEXTO.md. Aqui ele sai como
-- `fator_exibicao` do item MAIS RECENTE do SKU e serve só para REEXIBIR: é a
-- unidade em que `pedido` (BA) é expresso. Quem manda no cálculo é `unidades`.
--
-- `pedido` = `unidades / fator_exibicao` — o total do SKU reexpresso na unidade
-- de exibição da última decisão. Com um único item (100% dos 66 SKUs hoje) isso
-- devolve exatamente a QUANTIDADE digitada, e o comportamento é idêntico ao da
-- fonte antiga. Com dois itens de fatores diferentes, o número pode sair
-- fracionário — e sair fracionário é a informação verdadeira, não um defeito:
-- 120 unidades pedidas em caixas de 12 mais 5 unidades avulsas são 10,4167
-- caixas. A invariante que se preserva é `BA x fator = BB`, que toda a cadeia
-- do gabarito assume.
--
-- ── Todos os STATUS contam ───────────────────────────────────────────────────
-- APP_PEDIDO.STATUS percorre Rascunho → Orçamento Enviado → Fechado →
-- Exportado. A coluna BA do gabarito significa "quanto o comprador decidiu
-- comprar", não "quanto foi aprovado" — e a tabela velha não tinha status
-- nenhum. Contar todos PRESERVA o significado; restringir a "Enviado para cima"
-- seria regra NOVA. Confirmado com o usuário em 12/09/2026: fica como está.
-- Hoje os 4 pedidos estão em Rascunho — filtrar por status devolveria zero e a
-- lacuna continuaria aberta com outra cara.
--
-- ⚠ Este model AGREGA, e por isso foge do `renamed` puro da camada staging: é
-- a última camada onde a mudança de grão (PEDIDO x PRODUTO → PRODUTO) pode ser
-- feita uma vez só, sem que cada consumidor precise lembrar do fator.
-- ─────────────────────────────────────────────────────────────────────────────

with item as (
    select * from {{ source('compras_app', 'app_pedido_item') }}
),

cabecalho as (
    select * from {{ source('compras_app', 'app_pedido') }}
),

-- Um item por linha, com o pedido dono junto e a marca de recência dentro do
-- SKU. O desempate por ID_PEDIDO existe para a ordenação ser TOTAL: CRIADO_EM
-- é timestamp, mas dois itens do mesmo produto gravados no mesmo instante
-- deixariam o `row_number` não determinístico, e o fator de reexibição passaria
-- a mudar de build para build sem nenhuma decisão nova.
item_marcado as (
    select
        i.ID_PRODUTO                as id_produto,
        i.QUANTIDADE                as quantidade,
        i.FATOR_EXIBICAO            as fator_exibicao,
        i.CRIADO_EM                 as atualizado_em,
        c.ATUALIZADO_POR            as atualizado_por,
        row_number() over (
            partition by i.ID_PRODUTO
            order by i.CRIADO_EM desc, i.ID_PEDIDO desc
        )                           as ordem_recencia
      from item i
      join cabecalho c
        on c.ID_PEDIDO = i.ID_PEDIDO
),

renamed as (
    select
        id_produto,
        -- O que o cálculo usa: unidade REAL, somada com o fator de CADA item.
        sum(quantidade * fator_exibicao)                                as unidades,
        -- O que a reexibição usa: o fator congelado do item mais recente.
        max(case when ordem_recencia = 1 then fator_exibicao end)       as fator_exibicao,
        -- BA: o total reexpresso naquela unidade de exibição.
        sum(quantidade * fator_exibicao)
            / max(case when ordem_recencia = 1 then fator_exibicao end) as pedido,
        max(atualizado_em)                                              as atualizado_em,
        max(case when ordem_recencia = 1 then atualizado_por end)       as atualizado_por
      from item_marcado
     group by id_produto
)

select * from renamed
