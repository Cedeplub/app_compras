-- ─────────────────────────────────────────────────────────────────────────────
-- fat_alerta — as 14 colunas CHECK_* da aba `pedido` DESPIVOTADAS.
-- Grão: 1 linha por SKU x TIPO DE ALERTA ATIVO. SKU sem nenhum alerta não
-- aparece; SKU com quatro alertas aparece quatro vezes.
--
-- Qual coluna Excel reproduz: as mesmas X, Y, AL, AO, AP, AV, AY, BS, CC, CD,
-- CE, CL, DO, DB de int_produto_alerta - nenhum texto novo é inventado aqui.
-- O que muda é só a FORMA: lá são 14 colunas lado a lado (o formato da
-- planilha), aqui são linhas (o formato de quem filtra e conta).
--
-- ── Por que existe: para ninguém precisar dar parsing na coluna D ──────────
-- `ALERTA` (D) é uma string concatenada com "; ". Contar "quantos SKUs têm
-- problema de margem" a partir dela exige `like '%MARGEM%'`, que casaria
-- também com "ALERTA DE MARGEM" do varejo, e "quantos têm ruptura" exigiria
-- extrair o número de dias de dentro da frase. Toda contagem sairia frágil e
-- cada tela do dashboard reinventaria a sua. Aqui `tipo_alerta` é uma chave
-- limpa: `where tipo_alerta = 'MARGEM_INSTAVEL'` e pronto. A Etapa 6 (o
-- dashboard) depende disto - é o único caminho previsto para filtrar e contar
-- por tipo.
--
-- ⚠ Consequência de grão que quem consome precisa saber: somar/contar sobre
-- esta tabela conta ALERTAS, não PRODUTOS. Para contar produtos é
-- `count(distinct codigo)`. Um card de dashboard que mostre `count(*)` como
-- "produtos com alerta" exagera o número - hoje 4.790 SKUs geram mais de 6 mil
-- linhas aqui.
--
-- ── A ordem de `ordem_exibicao` é a da coluna D, não a alfabética ──────────
-- A concatenação de ALERTA segue X, Y, AL, AV, AO, AP, AY, BS, CC, CD, CE, CL,
-- DO, DB - ordem do Excel, com AV antes de AO e DO antes de DB (ver
-- int_produto_alerta). Uma tela que ordene por `tipo_alerta` alfabético
-- mostraria os mesmos alertas em ordem DIFERENTE da planilha que o comprador
-- conhece. `ordem_exibicao` carrega a ordem certa para que a tela possa
-- reproduzi-la sem redescobri-la.
--
-- ── As colunas de recorte vêm de fat_pedido, não de um segundo join ────────
-- fornecedor, comprador e classe são lidos de fat_pedido - que já é a junção
-- consolidada. Buscá-los de novo em int_produto_base/int_produto_classe_abc
-- criaria a chance de esta tabela e o fat_pedido discordarem sobre o
-- fornecedor do mesmo SKU depois de um refactor. Uma fonte só.
-- ─────────────────────────────────────────────────────────────────────────────

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

-- O unpivot manual: um union all por check. Escrito por extenso, e nao com
-- UNPIVOT, porque cada ramo precisa carregar o TIPO e a ORDEM DE EXIBICAO
-- proprios - e porque assim a coluna Excel de origem fica visivel linha a
-- linha, do mesmo jeito que nos outros models.
despivotado as (
    select codigo, 'FABRICA'                  as tipo_alerta,  1 as ordem_exibicao, check_fabrica                as texto_alerta from pedido  -- X
     union all
    select codigo, 'INATIVO',                  2, check_inativo                from pedido  -- Y
     union all
    select codigo, 'RUPTURA',                  3, check_ruptura                from pedido  -- AL
     union all
    select codigo, 'DEVOLUCAO',                4, check_devolucao_alta         from pedido  -- AV
     union all
    select codigo, 'PARADO',                   5, check_estoque_parado         from pedido  -- AO
     union all
    select codigo, 'FORA_DE_LINHA',            6, check_fora_de_linha          from pedido  -- AP
     union all
    select codigo, 'LITRAGEM',                 7, check_litragem               from pedido  -- AY
     union all
    select codigo, 'IMPORTADO',                8, check_importado              from pedido  -- BS
     union all
    select codigo, 'TRIB',                     9, check_trib                   from pedido  -- CC
     union all
    select codigo, 'MVA',                     10, check_mva                    from pedido  -- CD
     union all
    select codigo, 'CUSTO',                   11, check_custo                  from pedido  -- CE
     union all
    select codigo, 'MARGEM_INSTAVEL',         12, check_margem_instavel        from pedido  -- CL
     union all
    select codigo, 'SUCESSAO',                13, check_sucessao               from pedido  -- DO
     union all
    select codigo, 'MARGEM_INSTAVEL_VAREJO',  14, check_margem_instavel_varejo from pedido  -- DB
),

final as (
    select
        d.codigo,
        d.tipo_alerta,
        d.texto_alerta,
        d.ordem_exibicao,
        -- recorte: como o comprador filtra a lista dele
        p.fornecedor,
        p.comprador,
        p.classe,
        p.descricao
      from despivotado d
      join pedido p
        on p.codigo = d.codigo
     -- so' alerta ATIVO vira linha - e' o grao declarado no cabecalho
     where d.texto_alerta is not null
)

select * from final
