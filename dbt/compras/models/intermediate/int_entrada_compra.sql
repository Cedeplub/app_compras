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
-- ── ⚠ A JANELA MUDOU EM 08/10/2026: de 180 DIAS para 96 MESES ───────────────
-- Era `trunc(sysdate) - var('compras_entrada_dias_historico', 180)`, com esta
-- justificativa: "a tela agrupa só em Hoje/Ontem/Essa semana/Esse mês, com
-- navegação Dia/Semana/Mês (sem 'Ano' - diferente de Monitoramento)".
--
-- A premissa estava ERRADA, e pelo mesmo motivo que derrubou a janela de 400
-- dias do Monitoramento em 05/10/2026: a tela Entradas usa o MESMO componente
-- `SeletorPeriodo` das demais, que renderiza as quatro granularidades de
-- `GRANULARIDADES` (web/src/periodo.js) - **Ano inclusive**. Nunca existiu
-- versão desta tela sem "Ano"; o comentário descrevia o protótipo, não o que
-- foi construído. O backend (`entradas()` em app/servicos/monitoramento.py)
-- também é agnóstico de granularidade - recebe `de`/`ate` prontos e soma
-- COMPRAS_ENTRADA. Com 180 dias, escolher "Ano" e voltar um período devolvia
-- tela vazia: não por falta de dado, por falta de janela.
--
-- Agora são `var('compras_entrada_meses_historico', 96)` meses, o MESMO valor
-- de compras_meses_historico e de compras_monitoramento_meses_historico, e
-- ALINHADOS PELO MÊS (add_months sobre trunc(sysdate,'MM')), não por dia
-- corrido - o mesmo alinhamento de int_periodo_diario/int_periodo_mensal, para
-- que as três janelas do app comecem no mesmo mês.
--
-- Custo medido em 08/10/2026: 12.006 itens em 180 dias contra 196.999 em 96
-- meses (4.837 produtos distintos, a partir de 11/2018). Tabela pequena -
-- COMPRAS_MONITORAMENTO tem 2,0 MILHÕES de linhas. O build deste model com a
-- janela nova levou 5,1s (`dbt run --select int_entrada_compra+` inteiro: 11,6s).
--
-- ⚠ Um micro-benchmark do "núcleo" desta consulta, rodado solto contra o CEDEP
-- antes da mudança, deu 10s -> 75s e teria condenado a janela. O build real
-- levou 5,1s. O motivo é que o model lê as VIEWS stg_* já no schema do dbt e o
-- Oracle escolhe outro plano; a consulta avulsa reconstruía as CTEs à mão.
-- É o MESMO erro de método que subestimou em 4x o custo da janela de 96 meses
-- do Monitoramento em 05/10/2026, agora na direção oposta: medir fora do dbt
-- não mede o dbt. A medição que vale é a do `dbt run`.
--
-- ⚠ POR QUE A JANELA É INLINE AQUI, e não um model `int_periodo_entrada`:
-- int_periodo_mensal/int_periodo_diario existem porque VÁRIOS models precisam
-- da MESMA janela e uma espinha de meses/dias desincronizaria num build parcial
-- (ver o cabeçalho de int_periodo_mensal). Aqui há um model só, sem espinha -
-- nada com que dessincronizar. Se um segundo model passar a ler entrada por
-- data, aí sim extrair a janela para um `int_periodo_entrada` antes de duplicar
-- a expressão.
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
-- (160 deles dentro da janela de 180 dias que vigorava quando isto foi medido;
-- o teste compras_entrada_grao_unico segue PASSANDO com os 96 meses), com
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
       -- Janela alinhada ao MÊS - ver o bloco "A JANELA MUDOU" no cabeçalho.
       -- `- 1` porque a contagem INCLUI o mês corrente: 96 meses = os 95
       -- anteriores mais este.
       and n.data_entrada >= add_months(trunc(sysdate, 'MM'),
                                        -({{ var('compras_entrada_meses_historico', 96) }} - 1))
       and n.data_entrada <  trunc(sysdate) + 1
)

select * from final
