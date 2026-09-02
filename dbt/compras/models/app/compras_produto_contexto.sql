-- Índice do único join que esta tabela existe para servir: o LEFT JOIN por
-- CODIGO que o serviço da API (app/servicos/produto.py) faz contra
-- COMPRAS_PEDIDO, no mesmo molde do que já faz com COMPRAS_IND_FORNECEDOR.
-- Vai em post_hook porque a
-- materialização `table` derruba e recria a tabela a cada build — índice criado
-- à mão sumiria no build seguinte (ver o cabeçalho do macro compras_indice,
-- que documenta a armadilha do __dbt_backup).
{{ config(post_hook=[
    compras_indice('COMPRAS_PRODUTO_CONTEXTO', 'CODIGO', 'CODIGO')
]) }}

-- ─────────────────────────────────────────────────────────────────────────────
-- compras_produto_contexto — CONTRATO com o dashboard (Etapa 8 do ciclo v2).
-- Tabela física COMPRAS_PRODUTO_CONTEXTO. Grão: 1 linha por SKU (CODIGO), o
-- mesmo grão de COMPRAS_PEDIDO.
--
-- ── ⚠ QUAL COLUNA EXCEL REPRODUZ: NENHUMA, e é por isso que este model existe
-- Os três campos aqui NÃO existem na aba `pedido` da planilha v11. fat_pedido
-- reproduz as 122 colunas daquela aba e compras_pedido é projeção PURA dele —
-- acrescentar coluna em qualquer um dos dois quebraria de uma vez o teste
-- compras_fat_pedido_122_colunas, o espelho compras_app_pedido_espelha_fat e a
-- validação célula a célula contra a V10/V11, que casa coluna pelo NOME. As
-- telas de Precificação e Decisão do SKU (v2/PLANO.md §2.2/§2.3,
-- v2/prototipo/PROTOTIPO.md §2.9/§2.10/§3.9) precisam de contexto que a
-- planilha não tem; esse contexto mora aqui, ao lado, e é juntado por CODIGO.
--
-- Espinha: fat_pedido. Deliberada — garante o MESMO universo de SKU de
-- COMPRAS_PEDIDO (o teste compras_produto_contexto_cobre_pedido prova nos dois
-- sentidos) e entrega o COD_ICMS já RESOLVIDO, com o código padrão aplicado
-- por int_produto_fiscal. Ler a tributação direto de int_cadastro_estoque
-- pegaria o código cru, sem esse padrão, e as duas telas mostrariam um regime
-- diferente do que o cálculo fiscal usou.
--
-- ── REGIME_FISCAL ─────────────────────────────────────────────────────────
-- Texto descritivo do regime (ex.: "RE ST BA MVA 62,35% LUBRI C/PIS"), que o
-- protótipo mostra ao lado do badge de MODALIDADE. É dim_tributacao.descricao,
-- ou seja, a coluna DESCRICAO da aba dICMS, buscada pelo COD_ICMS (BJ) do
-- produto — a mesma linha de onde saem MODALIDADE (BL), MVA (BM),
-- ICMS_SAIDA_EF (CA) e ICMS_SEM_RED (CB). Não é o texto da PCTRIB do WinThor
-- (int_cadastro_estoque.tributacao): o regime que a tela mostra tem de ser o
-- que o modelo usou para calcular imposto, e o modelo usa o seed.
--
-- ⚠ NULO quando o código do produto não existe na tabela de ICMS. É o caso
-- medido dos 5 SKUs com codst = 0 em PCTABTRIB (CONTEXTO.md §6.2): eles saem
-- sem MODALIDADE, sem alíquota, com margem em branco, e é exatamente para eles
-- que o alerta TRIB dispara (§6.4, decisão 3). NULL aqui é a resposta certa —
-- inventar texto ("Sem tributação", "NORMAL") faria a tela afirmar um regime
-- que a tabela fiscal não tem, e apagaria o silêncio que o alerta TRIB existe
-- para quebrar.
--
-- ── QT_ULT_SAIDA ──────────────────────────────────────────────────────────
-- Quantidade da última saída, para o protótipo mostrar junto de DT_ULT_SAIDA
-- (AM), que COMPRAS_PEDIDO já expõe sozinha. Vem pronta de
-- int_cadastro_estoque.qt_ult_saida — a quantidade do movimento 'S'/'ST' mais
-- recente do SKU na filial de estoque —, sem redefinição aqui.
--
-- ⚠ NULA para SKU sem nenhum movimento de saída registrado (3.400 dos 8.829
-- em 02/09/2026). É a ausência de movimento, não a quantidade zero: nvl(...,0)
-- faria a tela dizer "última saída: 0 unidades" para produto que nunca saiu.
--
-- ⚠ NÃO é dividida por FATOR_EXIBICAO: é quantidade de um movimento histórico
-- em unidades, e o pareamento dela é com DT_ULT_SAIDA, que também não é.
--
-- ── VENDA_ANO_PASSADO ─────────────────────────────────────────────────────
-- Quantidade vendida no MESMO MÊS do ano anterior — a barra amarela do
-- mini-gráfico de venda (PROTOTIPO.md §2.10), ao lado das quatro barras de
-- VD_MES_ATUAL (AC) e VD_M_1/2/3 (AD/AE/AF).
--
-- Mês de referência: max(mes) de int_venda_mensal, o MESMO que
-- int_venda_mensal_pivot usa para montar QATUAL/Q00..Q11. Assim a barra
-- amarela fica exatamente 12 meses atrás da barra de VD_MES_ATUAL, e não
-- "12 meses atrás de hoje", que descolaria da janela materializada num build
-- feito na virada do mês.
--
-- LÍQUIDA (faturado − devolvido): usa int_venda_mensal.quantidade_liquida, a
-- mesma coluna que o pivot soma em Q00..Q11 (verificado no model, linhas
-- 117-128 de int_venda_mensal_pivot.sql). CONTEXTO.md regra 1. Por isso o
-- valor pode ser NEGATIVO — 5 SKUs em 02/09/2026, mês em que a devolução
-- superou o faturado. Negativo é dado correto, não defeito, e a tela precisa
-- saber desenhar isso.
--
-- ── ⚠ ZERO x NULO: a decisão, e por que ela é essa ────────────────────────
-- "Vendeu zero" e "não existe dado" leem diferente no gráfico, então os dois
-- estados existem aqui:
--
--   • NÚMERO (inclusive 0) quando HÁ EVIDÊNCIA de que o SKU estava vivo
--     naquele mês: ou ele tem linha no mês-alvo, ou tem linha em algum mês
--     ANTERIOR/IGUAL ao alvo dentro da janela de 24 meses. Sem linha no alvo,
--     mas com linha antes dele, o valor é 0 de verdade: a espinha de
--     int_venda_mensal só cria linha onde houve faturamento ou devolução, e
--     "movimentou antes, não movimentou no alvo" é vender zero.
--   • NULO quando não há evidência nenhuma: o SKU não aparece em mês algum
--     igual ou anterior ao alvo. Aí o modelo não sabe se ele vendeu zero ou
--     se ainda não existia, e afirmar 0 seria pior que calar — o gráfico
--     mostraria barra amarela nula e a leitura "vs. ano passado" do §3.9
--     (`((hist[0] − vendaAnoPassado) / vendaAnoPassado) × 100`) viraria uma
--     queda de 100% inventada para produto que nem tinha nascido.
--
-- Medido em 02/09/2026, mês-alvo 09/2025, sobre os 8.829 SKUs de
-- COMPRAS_PEDIDO: 3.395 com linha no alvo (763 delas valendo exatamente 0 e
-- 5 negativas), 477 sem linha no alvo mas com linha anterior (viram 0),
-- 116 cuja primeira linha é POSTERIOR ao alvo e 4.841 que não aparecem em mês
-- nenhum — esses 4.957 saem NULOS.
--
-- ⚠ O limite honesto da regra: "primeira linha na janela" é PROVA DE
-- MOVIMENTO, não data de cadastro. SKU cadastrado há anos que só voltou a se
-- mover depois de 09/2025 sai NULO, e não 0. Preferimos calar a afirmar.
--
-- ⚠ SUCESSÃO NÃO É HERDADA AQUI, e as quatro barras vizinhas herdam.
-- VD_MES_ATUAL e VD_M_1/2/3 passam por int_venda_mensal_sucessao (colunas
-- QATUAL/Q00/Q01/Q02, com PESO_1/PESO_2 do antecessor); VENDA_ANO_PASSADO lê
-- o histórico do PRÓPRIO SKU. Hoje isso não muda um único número: as 25 linhas
-- de seed_sucessao estão todas com ATIVO='NAO', então a herança é neutra —
-- e o teste compras_produto_contexto_ano_passado_bate_pivot prova a igualdade
-- contra Q11 (o mesmo mês-alvo, pelo caminho da sucessão) e QUEBRA no dia em
-- que alguém ativar uma sucessão, forçando a decisão em vez de deixar a barra
-- amarela ficar silenciosamente incomparável com as outras quatro.
-- ─────────────────────────────────────────────────────────────────────────────

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

tributacao as (
    select * from {{ ref('dim_tributacao') }}
),

cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

venda_mensal as (
    select * from {{ ref('int_venda_mensal') }}
),

-- Mesmo mes de referencia do pivot (int_venda_mensal_pivot.mes_ref): o mes
-- mais recente materializado, nao trunc(sysdate) - ver cabecalho.
mes_alvo as (
    select add_months(max(mes), -12) as mes from venda_mensal
),

venda_alvo as (
    select
        v.codigo_produto,
        v.quantidade_liquida
      from venda_mensal v
     cross join mes_alvo a
     where v.mes = a.mes
),

-- Evidencia de que o SKU estava vivo no mes-alvo: alguma linha de movimento
-- em mes igual ou anterior a ele. E o que separa "vendeu zero" de "nao ha
-- dado" - ver cabecalho.
existia_no_alvo as (
    select distinct v.codigo_produto
      from venda_mensal v
     cross join mes_alvo a
     where v.mes <= a.mes
),

final as (
    select
        p.codigo                                        as CODIGO,
        t.descricao                                     as REGIME_FISCAL,
        c.qt_ult_saida                                  as QT_ULT_SAIDA,
        -- ⚠ DIVIDIDO POR FATOR_EXIBICAO, e essa divisão não é detalhe.
        -- VD_MES_ATUAL e VD_M_1/2/3 saem de int_produto_demanda JÁ divididos
        -- pelo fator (linhas 158-161 de lá): para departamento que pede em
        -- caixa fechada, aqueles quatro números estão em CAIXAS. Esta coluna é
        -- a quinta barra do mesmo gráfico — sem a divisão ela viria em
        -- UNIDADES, e a barra do ano passado apareceria `fator` vezes mais
        -- alta que as quatro ao lado.
        --
        -- Medido em 02/09/2026, antes da correção: no SKU 6771 (YPF, fator 12)
        -- a razão era exatamente 12; entre os 187 SKUs em caixa com os dois
        -- valores, 126 tinham razão próxima do fator. Não era coincidência,
        -- era unidade trocada.
        --
        -- FATOR_EXIBICAO é sempre >= 1 (há teste disso em
        -- compras_fator_exibicao_valido), mas o nullif fica como cinto: uma
        -- divisão por zero aqui derrubaria o build inteiro.
        case
            when va.codigo_produto is not null
                 then va.quantidade_liquida / nullif(p.fator_exibicao, 0)
            when ex.codigo_produto is not null then 0
        end                                             as VENDA_ANO_PASSADO
      from pedido p
      left join tributacao t
        on t.cod_tributacao = p.cod_icms
      left join cadastro c
        on c.codprod = p.codigo
      left join venda_alvo va
        on va.codigo_produto = p.codigo
      left join existia_no_alvo ex
        on ex.codigo_produto = p.codigo
)

select * from final
