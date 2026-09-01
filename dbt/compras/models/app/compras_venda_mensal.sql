-- ─────────────────────────────────────────────────────────────────────────────
-- compras_venda_mensal — CONTRATO com o dashboard. Tabela física
-- COMPRAS_VENDA_MENSAL. Projeção PURA de int_venda_mensal: mesmas colunas,
-- mesma ordem, alias em MAIÚSCULA. Sem cálculo, sem case, sem join novo.
--
-- Qual coluna Excel reproduz: nenhuma - não existe na planilha. É o
-- relatório mensal de venda por produto (relatorios_compras/query_mensal.py,
-- ver o cabeçalho de int_venda_mensal.sql), publicado como contrato de
-- leitura para a tela de histórico do dashboard.
--
-- ⚠ Grão: 1 linha por MÊS x PRODUTO. É o ÚNICO model da camada `app` cujo
-- grão NÃO é o SKU. Quem juntar isto com COMPRAS_PEDIDO sem agregar por
-- CODIGO_PRODUTO antes multiplica linha - COMPRAS_PEDIDO tem 1 linha por SKU
-- e esta tem N (uma por mês do período).
--
-- ⚠ O mês corrente está EM ANDAMENTO e muda entre um build e outro (venda
-- ainda sendo lançada). Comparação mês a mês só fecha sobre meses FECHADOS -
-- comparar o mês corrente de dois builds diferentes é comparar fotos de
-- estados de carregamento distintos, não uma divergência real.
-- ─────────────────────────────────────────────────────────────────────────────

select
    mes                          as MES,
    codigo_produto               as CODIGO_PRODUTO,
    produto                      as PRODUTO,
    teve_venda                   as TEVE_VENDA,
    fora_de_linha                as FORA_DE_LINHA,
    codepto                      as CODEPTO,
    departamento                 as DEPARTAMENTO,
    codsec                       as CODSEC,
    secao                        as SECAO,
    quantidade_total              as QUANTIDADE_TOTAL,
    valor_total                  as VALOR_TOTAL,
    quantidade_devolucao         as QUANTIDADE_DEVOLUCAO,
    valor_devolucao              as VALOR_DEVOLUCAO,
    quantidade_liquida           as QUANTIDADE_LIQUIDA,
    valor_liquido                as VALOR_LIQUIDO,
    preco_medio                  as PRECO_MEDIO,
    dias_sem_estoque             as DIAS_SEM_ESTOQUE,
    quantidade_clientes_atacado  as QUANTIDADE_CLIENTES_ATACADO,
    quantidade_clientes_varejo   as QUANTIDADE_CLIENTES_VAREJO
  from {{ ref('int_venda_mensal') }}
