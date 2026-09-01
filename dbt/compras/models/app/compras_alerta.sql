-- ─────────────────────────────────────────────────────────────────────────────
-- compras_alerta — CONTRATO com o dashboard. Tabela física COMPRAS_ALERTA.
-- Projeção PURA de fat_alerta: mesmas colunas, alias em MAIÚSCULA. Sem
-- cálculo, sem case, sem join novo.
--
-- Qual coluna Excel reproduz: os 14 CHECK_* despivotados (X, Y, AL, AO, AP,
-- AV, AY, BS, CC, CD, CE, CL, DO, DB) - ver fat_alerta.sql.
--
-- Grão: 1 linha por SKU x TIPO DE ALERTA ATIVO. SKU sem alerta não aparece;
-- SKU com quatro alertas aparece quatro vezes.
--
-- ⚠ `count(*)` aqui conta ALERTAS, não PRODUTOS. Para produtos é
-- `count(distinct CODIGO)`. É a armadilha número um da tela de decisão de
-- compra: hoje o mesmo SKU pode ter até 4 linhas aqui, e um card que use
-- `count(*)` como "produtos com alerta" exagera o número.
-- ─────────────────────────────────────────────────────────────────────────────

select
    codigo          as CODIGO,
    tipo_alerta     as TIPO_ALERTA,
    texto_alerta    as TEXTO_ALERTA,
    ordem_exibicao  as ORDEM_EXIBICAO,
    fornecedor      as FORNECEDOR,
    comprador       as COMPRADOR,
    classe          as CLASSE,
    descricao       as DESCRICAO
  from {{ ref('fat_alerta') }}
