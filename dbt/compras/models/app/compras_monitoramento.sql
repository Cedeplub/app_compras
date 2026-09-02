-- Índices: DIA sozinho serve qualquer agregação por período (dia/semana/mês/
-- ano são todos deriváveis de DIA na camada de consulta - ver cabeçalho).
-- CODEPTO e CODSEC servem a quebra Departamento -> Seção (PROTOTIPO.md §5,
-- "dimensão automática de quebra"). Composto (DIA, CODEPTO, CODSEC) serve a
-- consulta real da tela: período + quebra ao mesmo tempo.
{{ config(post_hook=[
    compras_indice('COMPRAS_MONITORAMENTO', 'DIA',                          'DIA'),
    compras_indice('COMPRAS_MONITORAMENTO', 'DIA, CODEPTO, CODSEC',         'DIA_DEPTO_SECAO'),
    compras_indice('COMPRAS_MONITORAMENTO', 'CODIGO_PRODUTO',               'CODIGO_PRODUTO')
]) }}

-- ─────────────────────────────────────────────────────────────────────────────
-- compras_monitoramento — CONTRATO com o dashboard (v2 Etapa 10, tela
-- Monitoramento). Tabela física COMPRAS_MONITORAMENTO. Projeção PURA de
-- int_venda_diaria: mesmas colunas, alias em MAIÚSCULA, sem cálculo novo.
--
-- Grão: DIA × PRODUTO. Cobre os últimos
-- {{ var('compras_monitoramento_dias_historico', 400) }} dias corridos - ver
-- o cabeçalho de int_periodo_diario.sql para o porquê desse número (não são
-- os 24 meses de COMPRAS_VENDA_MENSAL).
--
-- ⚠ NÃO É AGREGADO POR PERÍODO. Não existe coluna "período" nem bucket
-- pré-calculado: Dia/Semana/Mês/Ano (PROTOTIPO.md §2.2) e a navegação
-- ←/→ (offsetPeriodo) são responsabilidade de quem monta a consulta da API,
-- somando DIA dentro do intervalo desejado. Três decisões que quem for montar
-- essa consulta precisa conhecer:
--
--   1. SEMANA: primeiro dia é SEGUNDA-feira (TRUNC(DIA,'IW') no Oracle -
--      'IW' é semana ISO-8601, sempre começa na segunda, INDEPENDENTE do
--      NLS_TERRITORY da sessão; 'W'/'D' dependem de idioma/território e
--      já causaram confusão em outros projetos). Não existe uma "semana
--      Winthor" diferente disso.
--
--   2. PERÍODO PARCIAL (mês em andamento): comparar o mês corrente
--      (parcial, só até hoje) contra o mês inteiro do ano anterior SUBESTIMA
--      o crescimento e é o defeito que o "+6,4%" fixo do protótipo escondia
--      (PROTOTIPO.md §8/§9, confirmado com Felipe: precisa virar cálculo de
--      verdade). A comparação correta é PARCIAL contra PARCIAL: somar só os
--      primeiros N dias do período do ano anterior, onde N é quantos dias do
--      período atual já se passaram. COMPRAS_PARAMETRO.DATA_REFERENCIA (novo
--      campo, ver compras_parametro.sql) é o "até quando" para calcular esse
--      N - não use SYSDATE da sessão da API, que pode rodar depois da
--      meia-noite do build e contar um dia que esta tabela ainda não tem.
--
--   3. PESO_LIQUIDO_KG / LITROS_LIQUIDO são APROXIMAÇÃO com fator ATUAL do
--      cadastro, não medida histórica - ver cabeçalho de int_venda_diaria.sql.
--
-- Para Mês/Ano com histórico mais longo que 400 dias, use COMPRAS_VENDA_MENSAL
-- (24 meses, grão mês × produto) em vez desta tabela - é mais barato de somar
-- e já é o contrato existente para esse grão.
-- ─────────────────────────────────────────────────────────────────────────────

select
    dia                          as DIA,
    codigo_produto                as CODIGO_PRODUTO,
    produto                       as PRODUTO,
    status                        as STATUS,
    codepto                       as CODEPTO,
    departamento                  as DEPARTAMENTO,
    codsec                        as CODSEC,
    secao                         as SECAO,
    quantidade_liquida            as QUANTIDADE_LIQUIDA,
    valor_liquido                 as VALOR_LIQUIDO,
    peso_liquido_kg               as PESO_LIQUIDO_KG,
    litros_liquido                as LITROS_LIQUIDO,
    quantidade_clientes_atacado   as QUANTIDADE_CLIENTES_ATACADO,
    quantidade_clientes_varejo    as QUANTIDADE_CLIENTES_VAREJO
  from {{ ref('int_venda_diaria') }}
