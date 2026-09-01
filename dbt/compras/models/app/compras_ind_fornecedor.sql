-- ─────────────────────────────────────────────────────────────────────────────
-- compras_ind_fornecedor — CONTRATO com o dashboard. Tabela física
-- COMPRAS_IND_FORNECEDOR. O ÚNICO model da camada `app` com agregação -
-- os outros três são projeção pura.
--
-- ⚠ 1. ESTA TABELA NÃO EXISTE NA PLANILHA. Não reproduz coluna Excel nenhuma
-- - é indicador NOVO, para a tela de Indicadores (PDF §13.3). As definições
-- abaixo são as que foram fixadas na Etapa 5; o Diretor de Compras valida na
-- v1 e pode trocá-las.
--
-- Grão: 1 linha por FORNECEDOR (texto do DEPARTAMENTO, CONTEXTO.md regra 7).
-- Espinha: dim_fornecedor - ela já é a UNIÃO do seed com o catálogo, então
-- LEFT JOIN do agregado de fat_pedido por fornecedor. Departamento cadastrado
-- sem nenhum SKU aparece com contagens ZERADAS em vez de sumir (é a lista do
-- que está cadastrado e não alcança produto nenhum). Um INNER esconderia essa
-- lista - por isso o left é de propósito, e todo `count` sobre fat_pedido usa
-- nvl(...,0) para o departamento sem SKU sair zerado, e não nulo.
--
-- Todo QTD_SKU_* é contado sobre fat_pedido, NÃO sobre fat_alerta: em
-- fat_alerta a mesma contagem daria linhas de ALERTA (um SKU pode aparecer
-- várias vezes), não produtos.
--
-- ⚠ 2. POR QUE HÁ DUAS MARGENS MÉDIAS. "Margem média do fornecedor" é
-- ambíguo: a média SIMPLES (MARGEM_OFICIAL_MEDIA) trata um SKU de R$ 50 em
-- estoque igual a um de R$ 500 mil; a PONDERADA (MARGEM_OFICIAL_POND_ESTOQUE)
-- responde "qual a margem do dinheiro parado neste departamento". As duas
-- estão aqui porque respondem perguntas diferentes. O sufixo `_POND_ESTOQUE`
-- diz explicitamente qual é o peso - não é ponderada por VENDA, que seria
-- outro número, ainda não calculado.
--
-- A ponderada só soma linhas em que margem_oficial E valor_estoque são
-- ambos não nulos - senão o numerador (soma de margem*estoque) e o
-- denominador (soma de estoque) cobririam conjuntos diferentes de SKU e a
-- razão resultante não significaria nada.
--
-- ⚠ 3. NENHUMA DESSAS MÉDIAS É SOMÁVEL. Rolar isto para "margem da empresa"
-- somando linha por fornecedor não funciona (média de médias não é a média
-- do total). Quem precisar da margem agregada da empresa inteira agrega o
-- fat_pedido de novo, não esta tabela.
-- ─────────────────────────────────────────────────────────────────────────────

with dim as (
    select * from {{ ref('dim_fornecedor') }}
),

pedido as (
    select * from {{ ref('fat_pedido') }}
),

agregado as (
    select
        fornecedor,
        count(*)                                                          as qtd_sku,
        count(case when status = 'Ativo' then 1 end)                      as qtd_sku_ativo,
        count(case when alerta is not null then 1 end)                    as qtd_sku_com_alerta,
        count(case when check_ruptura is not null then 1 end)             as qtd_sku_ruptura,
        count(case when check_margem_instavel is not null then 1 end)     as qtd_sku_margem_instavel,
        count(case when check_fora_de_linha is not null then 1 end)       as qtd_sku_fora_de_linha,
        count(case when classe = 'A' then 1 end)                          as qtd_sku_a,
        count(case when classe = 'B/C' then 1 end)                        as qtd_sku_bc,
        count(case when classe = 'S/VEND' then 1 end)                     as qtd_sku_svend,
        sum(valor_estoque)                                                as valor_estoque,
        sum(valor_pedido)                                                 as valor_pedido,
        avg(margem_oficial)                                               as margem_oficial_media,
        sum(case when margem_oficial is not null and valor_estoque is not null
                 then margem_oficial * valor_estoque end)
          / nullif(sum(case when margem_oficial is not null and valor_estoque is not null
                            then valor_estoque end), 0)                   as margem_oficial_pond_estoque,
        avg(margem_sem_red_varejo)                                        as margem_varejo_media,
        avg(meses_est)                                                    as meses_est_medio
      from pedido
     group by fornecedor
),

final as (
    select
        d.fornecedor                                as FORNECEDOR,
        d.comprador                                 as COMPRADOR,
        d.pedido_em                                 as PEDIDO_EM,
        d.meses_media                               as MESES_MEDIA,
        d.cobertura_alvo                            as COBERTURA_ALVO,
        d.tem_regra_cadastrada                      as TEM_REGRA_CADASTRADA,
        nvl(a.qtd_sku, 0)                           as QTD_SKU,
        nvl(a.qtd_sku_ativo, 0)                     as QTD_SKU_ATIVO,
        nvl(a.qtd_sku_com_alerta, 0)                as QTD_SKU_COM_ALERTA,
        nvl(a.qtd_sku_ruptura, 0)                   as QTD_SKU_RUPTURA,
        nvl(a.qtd_sku_margem_instavel, 0)           as QTD_SKU_MARGEM_INSTAVEL,
        nvl(a.qtd_sku_fora_de_linha, 0)             as QTD_SKU_FORA_DE_LINHA,
        nvl(a.qtd_sku_a, 0)                         as QTD_SKU_A,
        nvl(a.qtd_sku_bc, 0)                        as QTD_SKU_BC,
        nvl(a.qtd_sku_svend, 0)                     as QTD_SKU_SVEND,
        nvl(a.valor_estoque, 0)                     as VALOR_ESTOQUE,
        nvl(a.valor_pedido, 0)                      as VALOR_PEDIDO,
        a.margem_oficial_media                      as MARGEM_OFICIAL_MEDIA,
        a.margem_oficial_pond_estoque                as MARGEM_OFICIAL_POND_ESTOQUE,
        a.margem_varejo_media                       as MARGEM_VAREJO_MEDIA,
        a.meses_est_medio                           as MESES_EST_MEDIO
      from dim d
      left join agregado a
        on upper(a.fornecedor) = d.chave_fornecedor
)

select * from final
