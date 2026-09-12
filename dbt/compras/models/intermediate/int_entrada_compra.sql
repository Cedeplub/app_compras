-- ─────────────────────────────────────────────────────────────────────────────
-- int_entrada_compra — cadeia NOVA (v2 Etapa 10, tela Entradas). Não porta
-- nenhuma CTE de query.py / query_mensal.py: nenhum dos dois relatórios
-- rastreia entrada de compra (os dois olham venda e devolução). Origem:
-- PCNFENT (stg_nota_entrada) x PCMOV (stg_movimentacao), medido direto no
-- banco em 02/09/2026 - não há gabarito para conferir contra.
--
-- O QUE CONTA COMO "ENTRADA" AQUI, medido no banco (filial 2, 2 meses):
--   CODOPER  TIPODESCARGA  significado                          decisão
--   'E'      '1'           compra normal (fornecedor real,       ENTRA
--                            100% casa com PCFORNEC.CODFORNEC)
--   'EB'     '5'           bonificação do fornecedor (mercadoria ENTRA
--                            física recebida, valor pode ser 0)
--   'ED'     -              devolução de CLIENTE (já é o domínio  FORA
--                            de int_devolucao_mensal; CODFORNEC
--                            aqui guarda CODCLI, não fornecedor)
--   'ET'     -              transferência ENTRE FILIAIS: 1.223    FORA
--                            linhas em 2 meses e NENHUMA casa com
--                            PCNFENT (não tem nota de entrada
--                            associada) - não é compra
--   'ER'     'R'            "regularização de estoque" / anulação FORA
--                            de nota - visto no OBS: 'REGULARIZACAO
--                            DE ESTOQUE', 'NF CANCELADA', 'ANULACAO
--                            REF A NF ...' - ajuste manual, não compra
-- Sem essa exclusão, ET/ER inflam a tela de "o que chegou" com transferência
-- interna e correção de estoque que não representam compra nenhuma.
--
-- Cancelamento: mesma convenção de int_devolucao_mensal (que também lê
-- PCNFENT/PCMOV) - filtra data_cancelamento IS NULL tanto na NOTA quanto no
-- MOVIMENTO. Medido: 258 das 4.423 linhas 'E' de 2 meses tinham dtcancel
-- preenchido nos dois lugares ao mesmo tempo.
--
-- Fornecedor: a coluna reaproveitada de stg_nota_entrada chama
-- `id_cliente_devolucao` porque para 'ED' ela guarda o CLIENTE. Para 'E'/'EB'
-- (o único universo deste model) o MESMO campo físico (PCNFENT.CODFORNEC) é
-- genuinamente o fornecedor - medido: 3.607 de 3.607 notas tipodescarga='1'
-- casam com PCFORNEC.CODFORNEC (100%). Renomeada aqui para id_fornecedor,
-- sem ambiguidade possível porque ED nunca entra neste model.
--
-- Quantidade/valor: PCMOVCOMPLE.VLSUBTOTITEM (a fonte preferida em
-- int_faturamento_mensal) NÃO é preenchida para item de ENTRADA - medido:
-- 0 de 1.830 linhas 'E'/30 dias têm vlsubtotitem. Por isso valor = QT * PUNIT
-- direto, sem CTE de complemento.
--
-- Histórico: {{ var('compras_entrada_dias_historico', 180) }} dias corridos
-- (~6 meses) - deliberadamente MENOR que os 24 meses de compras_meses_historico.
-- A tela (PROTOTIPO.md §2.3) agrupa só em Hoje/Ontem/Essa semana/Esse mês, com
-- navegação Dia/Semana/Mês (sem "Ano" - diferente de Monitoramento). 180 dias
-- dá margem generosa para navegar alguns meses para trás sem carregar uma
-- janela dimensionada para comparação anual, que esta tela não faz.
--
-- Grão: 1 linha por ITEM DE MOVIMENTO de entrada (id_transacao_item) - não
-- agregado por dia. Decisão: o mesmo produto pode entrar mais de uma vez no
-- mesmo dia por notas/fornecedores diferentes (medido: produto 163 recebeu de
-- ICONIC e de 3R TRANSPORTES no mesmo dia, valores e quantidades distintos) -
-- agregar por (produto, dia) esconderia isso e impediria auditar de que nota
-- veio cada entrada. A tela agrupa por Hoje/Ontem/Semana/Mês na CAMADA DE
-- APRESENTAÇÃO, que soma o que precisar a partir daqui.
--
-- ⚠ ARMADILHA MEDIDA: PCNFENT.NUMTRANSENT NÃO é chave única da tabela. 4.125
-- valores de NUMTRANSENT têm mais de uma linha em PCNFENT no banco inteiro
-- (160 deles dentro da janela de compras_entrada_dias_historico), com
-- CODFORNEC e às vezes CODFISCAL diferentes por linha - dois "cabeçalhos de
-- nota" compartilhando o mesmo NUMTRANSENT. Um join direto de `movimentacao`
-- (1 linha por item) contra `nota` sem desduplicar FAN-OUT: o mesmo item de
-- movimento aparece 2x, uma vez por fornecedor, dobrando quantidade e valor
-- na soma (achado pelo teste compras_entrada_grao_unico.sql - 866 itens
-- duplicados antes desta correção). Resolvido do mesmo jeito que o dedupe de
-- embalagem (CONTEXTO.md §6.2): agrupar por chave antes de juntar, escolhendo
-- 1 valor deterministicamente (MIN) - não é "a resposta certa" sobre qual
-- fornecedor é o real, é evitar contar o item duas vezes.
-- ─────────────────────────────────────────────────────────────────────────────

with nota_bruta as (
    select * from {{ ref('stg_nota_entrada') }}
),

-- Dedupe por id_transacao_entrada - ver cabeçalho. MAX(data_cancelamento):
-- se QUALQUER cabeçalho duplicado estiver cancelado, trata a nota inteira
-- como cancelada (conservador - não conta entrada de nota parcialmente
-- cancelada).
nota as (
    select
        id_transacao_entrada,
        min(id_cliente_devolucao) as id_fornecedor,
        min(tipo_descarga)        as tipo_descarga,
        min(data_entrada)         as data_entrada,
        max(data_cancelamento)    as data_cancelamento
      from nota_bruta
     group by id_transacao_entrada
),

movimentacao as (
    select * from {{ ref('stg_movimentacao') }}
),

final as (
    select
        n.id_transacao_entrada,
        m.id_transacao_item,
        m.id_produto,
        m.id_filial,
        n.id_fornecedor,  -- ver cabeçalho: 'E'/'EB' -> fornecedor real
        case when m.codigo_operacao = 'EB' then 'BONIFICACAO' else 'COMPRA' end as tipo_entrada,
        n.data_entrada,
        nvl(m.quantidade, 0)            as quantidade,
        m.preco_unitario,
        nvl(m.quantidade, 0) * nvl(m.preco_unitario, 0) as valor
      from movimentacao m
      join nota n
        on n.id_transacao_entrada = m.id_transacao_entrada
     where m.id_filial = '{{ var("compras_filial_estoque", "2") }}'
       and m.codigo_operacao in ('E', 'EB')
       -- cinturão e suspensório: medido que 'E' sempre casa tipodescarga='1' e
       -- 'EB' sempre '5' - o filtro por tipodescarga trava isso se um dia
       -- aparecer um codoper 'E'/'EB' fora desse padrão (ex.: reclassificação).
       and n.tipo_descarga in ('1', '5')
       and m.data_cancelamento is null
       and n.data_cancelamento is null
       and n.data_entrada >= trunc(sysdate) - {{ var('compras_entrada_dias_historico', 180) }}
       and n.data_entrada <  trunc(sysdate) + 1
)

select * from final
