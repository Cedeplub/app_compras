-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: `shared fVendaMes`, docs/gabarito_powerquery.m — consolidação por
-- SKU do relatório mensal (int_venda_mensal) em 35 colunas: Q00..Q11,
-- V00..V05, os *_ATUAL, TX_DEVOLUCAO_3M, os *_00 e as médias MED02..MED12.
--
-- Grão: 1 linha por SKU (codigo_produto). A base é TODO SKU que apareceu em
-- QUALQUER mês de int_venda_mensal, inclusive o corrente (CONTEXTO.md regra 9,
-- comentário "TodosCodigos" do gabarito) — não só quem tem mês fechado. Produto
-- de primeira venda no mês corrente aparece aqui com os meses fechados
-- zerados.
--
-- offset_mes = MONTHS_BETWEEN(mes_atual, mes) - 1, onde mes_atual = MAX(mes)
-- de int_venda_mensal (comentário "ComOffset" do gabarito). O -1 é proposital:
-- o mês corrente fica com offset -1, e "fechado" é offset >= 0 — ou seja Q00
-- é o ÚLTIMO MÊS FECHADO, não o corrente.
--
-- Sempre LÍQUIDO (quantidade_liquida/valor_liquido), com uma única exceção:
-- TX_DEVOLUCAO_3M usa quantidade_total (faturado bruto) e quantidade_devolucao
-- (devolvido bruto) dos offsets 0..2 — por definição é taxa sobre o bruto
-- (CONTEXTO.md regra 1, comentário "Dev3" do gabarito). Faturado 0 dá TAXA 0,
-- não nulo.
--
-- Nulo (SKU sem linha naquele offset) vira 0 em tudo, EXCETO fora_de_linha,
-- que vira 'N' (gabarito: passos "SemNulo"/"SemNuloTxt").
--
-- ── ⚠ MELHORIA A3 | FORA_DE_LINHA vem do registro MAIS RECENTE, não do mês
--    corrente (divergência DELIBERADA da planilha) ────────────────────────────
-- Registro: MELHORIAS.md item A3, aprovado em 21/08/2026; CONTEXTO.md §6.0.
--
-- O QUE A PLANILHA FAZ: o passo "Atual" do Power Query recorta fVendaMes no mês
-- corrente e é dali que sai a coluna Y (FORA_DE_LINHA); quem não tem linha no
-- mês corrente cai no IFERROR(...,"N") da coluna AP.
--
-- POR QUE ISSO FALHA: produto fora de linha tende a não ter movimento nenhum no
-- mês corrente — e sem movimento não há linha. O alerta some exatamente para os
-- produtos que ele existe para apontar. Medido em 21/08/2026: 71 SKUs com 'S'
-- em mês fechado saíam 'N' aqui e NÃO disparavam CHECK_FORA_DE_LINHA (AP).
--
-- O QUE PASSAMOS A FAZER: fora_de_linha sai do registro mais recente em que o
-- SKU aparece (row_number() por mes desc). Tem linha no mês corrente? Vale ela —
-- o resultado é idêntico ao da planilha nesse caso. Não tem? Vale a do mês mais
-- recente em que aparece, em vez de um 'N' que só significa "não vendeu".
--
-- Nota sobre a natureza do campo: fora_de_linha NÃO é histórico. Ele vem de
-- stg_produto (OBS2 = 'FL'), estado ATUAL do cadastro, colado em cada linha
-- mensal por int_venda_mensal (CONTEXTO.md §6.3, "coluna de CADASTRO num fato
-- mensal"). Todas as linhas do mesmo SKU carregam o MESMO valor — por isso
-- pegar a mais recente não inventa informação velha: só deixa de jogar fora a
-- única cópia que existe. Medido: 71 SKUs mudam 'N' -> 'S' e ZERO mudam
-- 'S' -> 'N'.
--
-- ⚠ LIMITE CONHECIDO, medido e NÃO corrigido aqui: SKU que não aparece em mês
-- NENHUM continua saindo 'N'. São 4.205 SKUs do fat_pedido marcados 'FL' no
-- cadastro que nunca entram em int_venda_mensal (a CTE `produtos_incluir` de lá
-- só admite quem está EM LINHA, e sem movimento não há linha por movimento).
-- Ler o campo direto do cadastro alcançaria os 4.205, mas é mudança de escopo
-- muito maior que a aprovada — fica registrada para o Diretor de Compras
-- decidir, não implementada por conta própria.
--
-- Q00..Q11 e V00..V05 são montados por AGREGAÇÃO CONDICIONAL sobre o offset
-- (sum(case when offset_mes = N then ... end)), nunca por pivot de nome de
-- coluna dinâmico.
--
-- MED02/03/04/06/09/12: o gabarito só computa cada média quando há meses
-- FECHADOS suficientes para ela (2/3/4/6/9/12 respectivamente). No Power
-- Query essa checagem (List.Count(NomesQ) >= N) é sobre uma lista FIXA de 12
-- nomes — na prática nunca dispara o nulo, porque NomesQ sempre tem 12
-- elementos independente do dado. Aqui reproduzimos a INTENÇÃO (guarda de
-- meses fechados disponíveis) de forma que ela realmente funcione, olhando
-- para o total de meses fechados da janela inteira (int_periodo_mensal.qtd_meses
-- - 1), não por SKU. Hoje 23 fechados (>= 12), então nenhuma das seis dispara
-- — mas a condição está reproduzida e é testável baixando
-- var('compras_meses_historico').
--
-- Revisão etapa 3, item A: MED02/03/04/06 originalmente NÃO tinham essa
-- guarda (só MED09/12 tinham) — com var('compras_meses_historico') baixo,
-- MED06 devolveria soma(q00..q05)/6 com q05..q0N implicitamente 0 (mês sem
-- dado ainda não existe, não é "vendeu zero"), subestimando a média em
-- silêncio e fazendo SUG_COBERTURA comprar a menos. Escolha: guardar as seis
-- médias com a mesma regra de MED09/12, em vez de só documentar um mínimo de
-- meses — mantém o comportamento uniforme entre todas as colunas MED* e não
-- exige que quem consome o model saiba de antemão qual é o mínimo seguro.
-- ─────────────────────────────────────────────────────────────────────────────

with venda_mensal as (
    select * from {{ ref('int_venda_mensal') }}
),

periodo as (
    select * from {{ ref('int_periodo_mensal') }}
),

mes_ref as (
    select max(mes) as mes_atual from venda_mensal
),

com_offset as (
    select
        v.*,
        round(months_between(r.mes_atual, v.mes)) - 1 as offset_mes
      from venda_mensal v
     cross join mes_ref r
),

-- Todo SKU que apareceu em qualquer mes (fechado ou atual) - CONTEXTO.md regra 9.
todos_codigos as (
    select distinct codigo_produto from venda_mensal
),

fechados as (
    select * from com_offset where offset_mes >= 0
),

pivot_q as (
    select
        codigo_produto,
        sum(case when offset_mes = 0  then quantidade_liquida end) as q00,
        sum(case when offset_mes = 1  then quantidade_liquida end) as q01,
        sum(case when offset_mes = 2  then quantidade_liquida end) as q02,
        sum(case when offset_mes = 3  then quantidade_liquida end) as q03,
        sum(case when offset_mes = 4  then quantidade_liquida end) as q04,
        sum(case when offset_mes = 5  then quantidade_liquida end) as q05,
        sum(case when offset_mes = 6  then quantidade_liquida end) as q06,
        sum(case when offset_mes = 7  then quantidade_liquida end) as q07,
        sum(case when offset_mes = 8  then quantidade_liquida end) as q08,
        sum(case when offset_mes = 9  then quantidade_liquida end) as q09,
        sum(case when offset_mes = 10 then quantidade_liquida end) as q10,
        sum(case when offset_mes = 11 then quantidade_liquida end) as q11
      from fechados
     where offset_mes <= 11
     group by codigo_produto
),

pivot_v as (
    select
        codigo_produto,
        sum(case when offset_mes = 0 then valor_liquido end) as v00,
        sum(case when offset_mes = 1 then valor_liquido end) as v01,
        sum(case when offset_mes = 2 then valor_liquido end) as v02,
        sum(case when offset_mes = 3 then valor_liquido end) as v03,
        sum(case when offset_mes = 4 then valor_liquido end) as v04,
        sum(case when offset_mes = 5 then valor_liquido end) as v05
      from fechados
     where offset_mes <= 5
     group by codigo_produto
),

-- TX_DEVOLUCAO_3M: unico campo BRUTO do modelo (CONTEXTO.md regra 1;
-- comentario "Dev3" do gabarito).
taxa_devolucao as (
    select
        codigo_produto,
        case
            when sum(quantidade_total) = 0 then 0
            else sum(quantidade_devolucao) / sum(quantidade_total)
        end as tx_devolucao_3m
      from fechados
     where offset_mes < 3
     group by codigo_produto
),

-- Mes corrente (offset -1): comentario "Atual"/"AtualRen" do gabarito.
atual as (
    select
        codigo_produto,
        quantidade_liquida            as qatual,
        valor_liquido                 as vatual,
        quantidade_clientes_atacado   as cli_atac_atual,
        quantidade_clientes_varejo    as cli_var_atual,
        dias_sem_estoque              as dias_sem_est_atual
      from com_offset
     where offset_mes = -1
),

-- MELHORIA A3 (ver cabecalho): FORA_DE_LINHA do registro MAIS RECENTE do SKU,
-- e nao so' do mes corrente. `order by mes desc` = mes corrente quando ele
-- existe; mes mais recente em que o SKU aparece quando nao existe.
fora_de_linha_recente as (
    select codigo_produto, fora_de_linha
      from (
            select
                codigo_produto,
                fora_de_linha,
                row_number() over (
                    partition by codigo_produto order by mes desc
                ) as rn
              from com_offset
           )
     where rn = 1
),

-- Ultimo mes fechado (offset 0): comentario "Mes0"/"Mes0Ren" do gabarito.
mes_00 as (
    select
        codigo_produto,
        quantidade_clientes_atacado as cli_atac_00,
        quantidade_clientes_varejo  as cli_var_00,
        dias_sem_estoque            as dias_sem_est_00
      from fechados
     where offset_mes = 0
),

-- Meses fechados disponiveis na janela INTEIRA (nao por SKU) - guarda de
-- MED09/MED12, ver cabecalho.
meses_fechados as (
    select qtd_meses - 1 as n_fechados from periodo
),

combinado as (
    select
        tc.codigo_produto,
        nvl(pq.q00, 0) as q00, nvl(pq.q01, 0) as q01, nvl(pq.q02, 0) as q02,
        nvl(pq.q03, 0) as q03, nvl(pq.q04, 0) as q04, nvl(pq.q05, 0) as q05,
        nvl(pq.q06, 0) as q06, nvl(pq.q07, 0) as q07, nvl(pq.q08, 0) as q08,
        nvl(pq.q09, 0) as q09, nvl(pq.q10, 0) as q10, nvl(pq.q11, 0) as q11,
        nvl(pv.v00, 0) as v00, nvl(pv.v01, 0) as v01, nvl(pv.v02, 0) as v02,
        nvl(pv.v03, 0) as v03, nvl(pv.v04, 0) as v04, nvl(pv.v05, 0) as v05,
        nvl(at.qatual, 0)              as qatual,
        nvl(at.vatual, 0)              as vatual,
        nvl(at.cli_atac_atual, 0)      as cli_atac_atual,
        nvl(at.cli_var_atual, 0)       as cli_var_atual,
        nvl(at.dias_sem_est_atual, 0)  as dias_sem_est_atual,
        nvl(fl.fora_de_linha, 'N')     as fora_de_linha,   -- MELHORIA A3
        nvl(td.tx_devolucao_3m, 0)     as tx_devolucao_3m,
        nvl(m0.cli_atac_00, 0)         as cli_atac_00,
        nvl(m0.cli_var_00, 0)          as cli_var_00,
        nvl(m0.dias_sem_est_00, 0)     as dias_sem_est_00,
        mf.n_fechados
      from todos_codigos tc
      left join pivot_q pq on pq.codigo_produto = tc.codigo_produto
      left join pivot_v pv on pv.codigo_produto = tc.codigo_produto
      left join atual at on at.codigo_produto = tc.codigo_produto
      left join fora_de_linha_recente fl on fl.codigo_produto = tc.codigo_produto
      left join taxa_devolucao td on td.codigo_produto = tc.codigo_produto
      left join mes_00 m0 on m0.codigo_produto = tc.codigo_produto
     cross join meses_fechados mf
),

final as (
    select
        codigo_produto,
        q00, q01, q02, q03, q04, q05, q06, q07, q08, q09, q10, q11,
        v00, v01, v02, v03, v04, v05,
        qatual, vatual, cli_atac_atual, cli_var_atual, dias_sem_est_atual, fora_de_linha,
        tx_devolucao_3m, cli_atac_00, cli_var_00, dias_sem_est_00,
        case when n_fechados >= 2
             then (q00 + q01) / 2
        end as med02,
        case when n_fechados >= 3
             then (q00 + q01 + q02) / 3
        end as med03,
        case when n_fechados >= 4
             then (q00 + q01 + q02 + q03) / 4
        end as med04,
        case when n_fechados >= 6
             then (q00 + q01 + q02 + q03 + q04 + q05) / 6
        end as med06,
        case when n_fechados >= 9
             then (q00+q01+q02+q03+q04+q05+q06+q07+q08) / 9
        end as med09,
        case when n_fechados >= 12
             then (q00+q01+q02+q03+q04+q05+q06+q07+q08+q09+q10+q11) / 12
        end as med12
      from combinado
)

select * from final
