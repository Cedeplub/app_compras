-- Índices. CODIGO serve o `exists (... where a.codigo = p.codigo)` que decide
-- quem tem alerta — executado uma vez por linha da listagem. TIPO_ALERTA serve
-- o filtro por tipo e a contagem de cada botão. O composto CODIGO+ORDEM_EXIBICAO
-- serve a busca de alertas de uma página inteira, que já sai ordenada.
--
-- CATEGORIA ganhou índice em 02/09/2026: desde a separação entre "Decisões" e
-- "Pendência de Cadastro" (v2/DECISOES_DIRETOR.md item 2), TODA consulta das
-- duas telas carrega `where CATEGORIA = ...` — é o filtro mais frequente da
-- tabela, à frente de TIPO_ALERTA. O índice é COMPOSTO com TIPO_ALERTA, e não
-- solto: CATEGORIA tem só dois valores (seletividade grosseira, que sozinha
-- não justificaria índice), enquanto (CATEGORIA, TIPO_ALERTA) serve tanto o
-- filtro da tela quanto a contagem por botão de tipo DENTRO dela, que é a
-- consulta real. O índice de TIPO_ALERTA sozinho continua, para quem filtra por
-- tipo sem escolher categoria.
-- PONTUA não ganhou índice: dois valores, distribuição ainda mais desigual, e
-- ele nunca aparece sozinho no WHERE — vem sempre acompanhado de CATEGORIA.
{{ config(post_hook=[
    compras_indice('COMPRAS_ALERTA', 'CODIGO',                  'CODIGO'),
    compras_indice('COMPRAS_ALERTA', 'TIPO_ALERTA',             'TIPO'),
    compras_indice('COMPRAS_ALERTA', 'CODIGO, ORDEM_EXIBICAO',  'CODIGO_ORDEM'),
    compras_indice('COMPRAS_ALERTA', 'CATEGORIA, TIPO_ALERTA',  'CATEGORIA_TIPO')
]) }}

-- ─────────────────────────────────────────────────────────────────────────────
-- compras_alerta — CONTRATO com o dashboard. Tabela física COMPRAS_ALERTA.
-- Projeção PURA de fat_alerta: mesmas colunas, alias em MAIÚSCULA. Sem
-- cálculo, sem case, sem join novo.
--
-- Qual coluna Excel reproduz: os CHECK_* despivotados (X, AL, AO, AP, AV, AY,
-- BS, CC, CD, CE, CL, DO, DB) MAIS dois alertas NOVOS sem coluna na planilha
-- (OPORTUNIDADE_DE_GIRO e MARGEM_ALTA) - ver fat_alerta.sql e
-- int_produto_alerta_extra.sql.
--
-- ⚠ TIPO_ALERTA mudou em 02/09/2026 (v2/DECISOES_DIRETOR.md item 1): é
-- INTERFACE PÚBLICA e a tela filtra por ele. MARGEM_INSTAVEL virou
-- MARGEM_BAIXA, MARGEM_INSTAVEL_VAREJO virou MARGEM_BAIXA_VAREJO, PARADO virou
-- SEM_GIRO/BAIXO_GIRO e INATIVO deixou de existir. Consulta antiga que cite os
-- nomes velhos volta VAZIA, não com erro - é o que precisa ser procurado no
-- dashboard depois deste build.
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
    -- 'DECISAO' | 'CADASTRO'. CADASTRO sai da tela de Alertas e vai para a de
    -- Pendência de Cadastro (v2/DECISOES_DIRETOR.md item 2).
    categoria       as CATEGORIA,
    -- 'S' | 'N'. 'N' = a linha aparece mas NÃO entra no score de priorização.
    -- É o caso de FORA_DE_LINHA (badge visual) e de toda a categoria CADASTRO.
    pontua          as PONTUA,
    fornecedor      as FORNECEDOR,
    comprador       as COMPRADOR,
    classe          as CLASSE,
    descricao       as DESCRICAO
  from {{ ref('fat_alerta') }}
