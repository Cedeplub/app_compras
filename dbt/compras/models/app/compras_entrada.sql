-- Índices: DATA_ENTRADA serve o agrupamento Hoje/Ontem/Essa semana/Esse mês
-- (PROTOTIPO.md §2.3), que é a primeira coisa que a tela calcula em cima da
-- lista inteira. CODIGO serve filtro/busca por produto. CODEPTO serve o
-- filtro por Departamento.
{{ config(post_hook=[
    compras_indice('COMPRAS_ENTRADA', 'DATA_ENTRADA',          'DATA_ENTRADA'),
    compras_indice('COMPRAS_ENTRADA', 'CODIGO',                'CODIGO'),
    compras_indice('COMPRAS_ENTRADA', 'CODEPTO',                'CODEPTO')
]) }}

-- ─────────────────────────────────────────────────────────────────────────────
-- compras_entrada — CONTRATO com o dashboard (v2 Etapa 10, tela Entradas).
-- Tabela física COMPRAS_ENTRADA. Projeção PURA de int_entrada_produto: mesmas
-- colunas, alias em MAIÚSCULA, sem cálculo novo.
--
-- Qual coluna Excel reproduz: nenhuma - não existe na planilha nem em
-- query.py/query_mensal.py. Ver o cabeçalho de int_entrada_compra.sql para a
-- decisão de escopo (CODOPER 'E'+'EB', filial 2, janela de
-- {{ var('compras_entrada_dias_historico', 180) }} dias).
--
-- Grão: 1 linha por ITEM DE MOVIMENTO de entrada (ID_TRANSACAO_ITEM). O mesmo
-- produto pode aparecer várias vezes no mesmo dia (notas/fornecedores
-- diferentes) - ver cabeçalho de int_entrada_compra.sql.
--
-- ⚠ O agrupamento Hoje/Ontem/Essa semana/Esse mês NÃO está pré-calculado
-- aqui de propósito: é a mesma razão pela qual o projeto rejeita o "hoje"
-- como default silencioso de filtro_periodo (dbt_project.yml, seção de vars) -
-- se o rótulo do bucket fosse calculado no build, ele ficaria PARADO no dia do
-- último `dbt run` até o próximo build, mesmo com a data real do dispositivo
-- tendo avançado. DATA_ENTRADA sai crua; quem monta a tela agrupa usando a
-- data REAL do momento da consulta, não a data do build.
-- ─────────────────────────────────────────────────────────────────────────────

select
    id_transacao_entrada as ID_TRANSACAO_ENTRADA,
    id_transacao_item    as ID_TRANSACAO_ITEM,
    id_produto           as CODIGO,
    produto               as PRODUTO,
    status                as STATUS,
    codepto               as CODEPTO,
    departamento          as DEPARTAMENTO,
    codsec                as CODSEC,
    secao                 as SECAO,
    id_fornecedor         as ID_FORNECEDOR,
    tipo_entrada          as TIPO_ENTRADA,
    data_entrada          as DATA_ENTRADA,
    quantidade            as QUANTIDADE,
    preco_unitario        as PRECO_UNITARIO,
    valor                 as VALOR
  from {{ ref('int_entrada_produto') }}
