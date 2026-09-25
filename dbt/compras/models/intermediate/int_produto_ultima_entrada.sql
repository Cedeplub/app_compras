-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_ultima_entrada — PREÇO UNITÁRIO DA ÚLTIMA ENTRADA, SEM FRETE,
-- pela lógica da ROTINA 218 do WinThor.
--
-- ── ⚠ QUAL COLUNA EXCEL REPRODUZ: NENHUMA. ────────────────────────────────
-- Este número NÃO existe na aba `pedido` da planilha v11 e NÃO entra em
-- fat_pedido nem em compras_pedido — aqueles dois são as 122 colunas do
-- gabarito e só elas (tests/compras_fat_pedido_122_colunas.sql e
-- tests/compras_app_pedido_espelha_fat.sql quebram no dia em que alguém
-- acrescentar uma coluna lá). O consumidor é compras_produto_contexto, o
-- lugar onde mora o "contexto que a planilha não tem".
--
-- ── POR QUE ELE EXISTE, e por que NÃO é VL_ENT_UNIT ───────────────────────
-- `VL_ENT_UNIT` (coluna BH do gabarito) vem de PCEST.VALORULTENT
-- (stg_estoque.valor_ultima_entrada). Esse campo é o valor de entrada como o
-- WinThor o registra no estoque, e ele EMBUTE O FRETE quando a nota tem frete
-- rateado. Para custo, margem e preço de venda isso está certo — frete é
-- custo. Para NEGOCIAR COM O FORNECEDOR, não: a tela de Pedidos precisa do
-- preço do PRODUTO PURO, que é o que se discute com o vendedor da indústria.
-- Daí os dois números conviverem, com nomes diferentes, lado a lado:
--
--   VL_ENT_UNIT              PCEST.VALORULTENT, COM frete  -> custo/preço
--   preco_ult_ent_sem_frete  PCMOV.PUNIT (rotina 218)      -> pedido
--
-- Comparação medida no build de 25/09/2026 (filial 2, 6.562 SKUs com valor
-- nos dois lados, tolerância 0,01): 4.884 iguais (74,4%), 1.286 em que a 218
-- é MENOR (é ali que o frete está embutido no VALORULTENT) e 392 em que a 218
-- é MAIOR — provável diferença de qual nota cada lado considera "a última".
--
-- ⚠ A tela de PRECIFICAÇÃO continua usando o valor COM frete. Trocar a fonte
-- lá mudaria custo e margem de 1.678 SKUs sem ninguém ter decidido isso.
--
-- ── A QUERY DA 218, condição por condição ─────────────────────────────────
--   DECODE(NVL(PUNIT,0), 0, NVL(PUNITCONT,0), PUNIT)  -> o case abaixo: usa
--     PUNIT; se for zero OU nulo, cai em PUNITCONT (venda/compra futura, onde
--     o valor mora no campo "contratado").
--   CODOPER LIKE 'E%' AND CODOPER NOT IN ('ED','EA')  -> entrada de verdade,
--     fora devolução de cliente ('ED') e acerto ('EA').
--   DTCANCEL IS NULL                                  -> movimento não cancelado.
--   QT > 0 OR (QTCONT > 0 AND TIPODESCARGA = '4')     -> reproduzido literal.
--   TIPODESCARGA NOT IN ('6','7','8','N','F')         -> fora devolução e
--     descargas que não são compra.
--   CODFILIAL                                         -> var compras_filial_estoque
--     (hoje '2', sem zero à esquerda — REGRAS.md regra 3). Nunca chumbado.
--
-- ── ⚠ DESVIO DELIBERADO DA 218: a condição que depende de PCCONSUM ────────
-- A 218 aceita a nota por TRÊS caminhos alternativos:
--   (a) CODCONT = NVL(CODCONTFOR, PCCONSUM.CODCONTFOR)
--   (b) CODCONT = PCCONSUM.CODCONTAJUSTEEST  AND  TIPODESCARGA = '4'
--   (c) TIPODESCARGA = 'S' AND ESPECIE IN ('NF','NE')
-- ⚠ O GRANT em PCCONSUM FOI CONCEDIDO em 25/09/2026, a pedido. Ou seja: o
-- desvio abaixo NÃO é mais falta de acesso — é ESCOLHA, tomada com o número
-- na mão. Quem ler isto no futuro não deve "consertar" achando que faltava
-- permissão.
--   • (b) FICA DE FORA, por DECISÃO DO USUÁRIO em 25/09/2026. Medido com o
--     GRANT já ativo: incluí-la mudaria o preço de 75 produtos, que passariam
--     a usar o valor do AJUSTE DE ESTOQUE em vez o da última compra — e o
--     ajuste é sistematicamente MAIS BARATO (ex.: SKU 2021 JVC SOLUPAN
--     236,90 → 191,63, −19%; SKU 3393 JVC SHAMPOO 26,32 → 20,65, −22%).
--     O ganho seria de UM único produto em cobertura.
--     Ajuste de estoque é reavaliação contábil interna, não o que o
--     fornecedor cobrou — e este número serve para negociar com o fornecedor
--     E para gravar o preço do item de pedido. Por isso fica fora.
--   • (a) entra SEM o NVL de PCCONSUM, e isso agora é MEDIDO como inócuo, não
--     suposto: a única nota com CODCONTFOR nulo (numtransent 1118284, filial
--     2, emitida em 17/09/2026) tem ZERO movimentos de entrada em PCMOV —
--     nenhum preço de produto sai dela.
--   • (c) entra literal.
-- Por (a) e (b) acima, PCCONSUM NÃO é source deste projeto de propósito:
-- acrescentar uma dependência que comprovadamente não muda nenhum número é
-- pior que não acrescentá-la. O GRANT existe e permanece disponível se a
-- decisão sobre (b) mudar.
--
-- ── SEM JANELA DE DATA, de propósito ──────────────────────────────────────
-- A 218 recebe :DTP1..:DTP4 porque é consulta de TELA, onde o usuário escolhe
-- o período. Aqui a pergunta é outra: "qual foi a última entrada, seja
-- quando for". Um corte por idade faria o SKU de giro lento perder o preço e
-- a tela de Pedidos ficar sem número justamente onde o comprador mais precisa
-- dele. Medido: a entrada mais antiga que vira "a última" de algum SKU é de
-- 03/07/2013.
--
-- ── GRÃO: 1 LINHA POR PRODUTO, e isso é obrigatório ───────────────────────
-- compras_produto_contexto tem teste de grão único
-- (tests/compras_produto_contexto_grao_unico.sql) e é LEFT JOIN por CODIGO:
-- duplicar aqui duplicaria a tabela de contrato e quebraria o build.
-- Garantido por row_number() = 1, com desempate DETERMINÍSTICO em três
-- níveis: data_movimento desc, id_transacao_entrada desc, id_transacao_item
-- desc. Sem os dois últimos, duas entradas do mesmo SKU no MESMO DIA fariam o
-- número trocar de build para build sem ninguém ter mexido em nada.
--
-- ⚠ FAN-OUT de PCNFENT: NUMTRANSENT NÃO é chave única daquela tabela (4.125
-- valores repetidos no banco — ver o cabeçalho de int_entrada_compra.sql).
-- Por isso a CTE `nota` AGRUPA por id_transacao_entrada antes de juntar, em
-- vez de juntar linha a linha: a nota qualifica se QUALQUER cabeçalho dela
-- qualifica, e o item de movimento é contado uma vez só.
--
-- Desempenho: PCMOV é a tabela de movimentação (grande). O filtro por
-- CODOPER e o join contra a lista de notas já qualificadas resolvem em ~4 s
-- medidos contra o CEDEP em 25/09/2026, devolvendo 6.601 produtos.
-- ─────────────────────────────────────────────────────────────────────────────

with nota_bruta as (
    select * from {{ ref('stg_nota_entrada') }}
),

-- Agrupada por id_transacao_entrada para não duplicar o item de movimento -
-- ver o aviso de FAN-OUT no cabeçalho. `tem_descarga_ajuste` sobrevive ao
-- agrupamento porque a condição de quantidade da 218 (QTCONT > 0 AND
-- TIPODESCARGA = '4') precisa dele do lado do movimento.
nota as (
    select
        id_transacao_entrada,
        max(case when tipo_descarga = '4' then 1 else 0 end) as tem_descarga_ajuste
      from nota_bruta
     where id_filial = '{{ var("compras_filial_estoque", "2") }}'
       and tipo_descarga not in ('6', '7', '8', 'N', 'F')
       -- (a) sem o NVL de PCCONSUM (medido inocuo) e (c) literal; (b) fora
       -- por DECISAO de 25/09/2026, nao por falta de GRANT - ver cabecalho.
       and (id_conta_contabil = id_conta_contabil_fornecedor
            or (tipo_descarga = 'S' and especie in ('NF', 'NE')))
     group by id_transacao_entrada
),

movimentacao as (
    select * from {{ ref('stg_movimentacao') }}
),

entrada as (
    select
        m.id_produto,
        m.data_movimento,
        m.id_transacao_entrada,
        m.id_transacao_item,
        -- DECODE(NVL(PUNIT,0), 0, NVL(PUNITCONT,0), PUNIT) da 218, na forma
        -- que o projeto usa. Mesma semântica: PUNIT manda; zero OU nulo cai
        -- em PUNITCONT.
        case
            when nvl(m.preco_unitario, 0) = 0 then nvl(m.preco_unitario_contratado, 0)
            else m.preco_unitario
        end as preco_ult_ent_sem_frete,
        row_number() over (
            partition by m.id_produto
            order by m.data_movimento desc,
                     m.id_transacao_entrada desc,
                     m.id_transacao_item desc
        ) as ordem
      from movimentacao m
      join nota n
        on n.id_transacao_entrada = m.id_transacao_entrada
     where m.codigo_operacao like 'E%'
       and m.codigo_operacao not in ('ED', 'EA')
       and m.data_cancelamento is null
       and (m.quantidade > 0
            or (m.quantidade_contratada > 0 and n.tem_descarga_ajuste = 1))
),

final as (
    select
        id_produto,
        data_movimento          as dt_ult_ent_sem_frete,
        id_transacao_entrada,
        preco_ult_ent_sem_frete
      from entrada
     where ordem = 1
)

select * from final
