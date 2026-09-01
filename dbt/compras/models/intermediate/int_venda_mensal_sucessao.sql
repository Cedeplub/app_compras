-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: seed_sucessao (aba dSucessao) + docs/gabarito_pedido_formulas.txt,
-- colunas DK (ANT_1), DL (PESO_1), DM (ANT_2), DN (PESO_2) e as colunas que
-- consultam fVendaMes com essa herança: AC (VD MES ATUAL -> QATUAL), AD/AE/AF
-- (VD M-1/M-2/M-3 -> Q00/Q01/Q02), AG (MEDIA_JANELA -> MED02..MED12) e AQ
-- (VD_ANT_3M -> Q03/Q04/Q05, ver seção própria abaixo). Revisão etapa 3: a
-- versão anterior deste cabeçalho dizia que AC/AD/AE/AF/AG eram "as únicas
-- colunas que herdam histórico" — é FALSO, AQ também herda, e ficou de fora
-- só porque ninguém tinha ido conferir a fórmula de AQ contra o gabarito.
-- V00..V05, VATUAL, CLI_*, DIAS_SEM_EST*, FORA_DE_LINHA e TX_DEVOLUCAO_3M
-- continuam sendo as que passam direto do próprio SKU, sem herança nenhuma.
--
-- Grão: 1 linha por SKU (codigo_produto) - mesmo grão de int_venda_mensal_pivot.
--
-- ⚠️ Nada é aplicado enquanto ATIVO não for 'SIM' (gabarito_pedido_formulas.txt:
-- "IF(...<>'SIM',0,...)" nas colunas DK/DM, e PESO fica 0 se o ANTIGO for 0).
-- Hoje as 25 linhas de seed_sucessao estão com ATIVO='NAO', então o resultado
-- deste model tem que ser IDÊNTICO a int_venda_mensal_pivot linha a linha -
-- ver tests/compras_venda_mensal_sucessao_identico_sem_ativo.sql.
--
-- valor_final = valor_proprio + PESO_1 x valor_de(ANTIGO_1) + PESO_2 x valor_de(ANTIGO_2)
--
-- Aplicado a QATUAL e Q00..Q11. MED02..MED12 NÃO são herdadas somando as
-- médias dos antecessores diretamente - são RECALCULADAS a partir dos Q00..Q11
-- já herdados. Isso é algebricamente idêntico a herdar a média (MEDxx é uma
-- soma de Qs dividida por uma constante, e a herança é linear:
-- MEDxx(Q' = Qp + peso*Qa) = MEDxx(Qp) + peso*MEDxx(Qa)), e evita duplicar a
-- guarda de "N meses fechados disponíveis" de int_venda_mensal_pivot (essa
-- guarda é GLOBAL - mesmo n_fechados vale para o produto novo e para os
-- antecessores - então recalcular depois de herdar dá exatamente o mesmo
-- resultado que herdar a média já pronta). Revisão etapa 3, item A: a mesma
-- guarda agora cobre MED02/03/04/06, não só MED09/12 - ver o cabeçalho de
-- int_venda_mensal_pivot para o motivo.
--
-- ── ⚠ VD_ANT_3M (coluna AQ) | MELHORIA D1: a assimetria foi FECHADA ───────
-- Registro: MELHORIAS.md item D1, aprovado em 21/08/2026; CONTEXTO.md §6.0.
-- Divergência DELIBERADA da planilha — não reverter.
--
-- O QUE A PLANILHA FAZ. gabarito_pedido_formulas.txt, coluna AQ:
--   F=(INDEX(fVendaMes!$E:$E,MATCH($A2,fVendaMes!$A:$A,0))
--      +INDEX(fVendaMes!$F:$F,MATCH($A2,fVendaMes!$A:$A,0))
--      +INDEX(fVendaMes!$G:$G,MATCH($A2,fVendaMes!$A:$A,0))
--      +$DL2*(INDEX(fVendaMes!$E:$E,MATCH($DK2,fVendaMes!$A:$A,0))
--             +INDEX(fVendaMes!$F:$F,MATCH($DK2,fVendaMes!$A:$A,0))
--             +INDEX(fVendaMes!$G:$G,MATCH($DK2,fVendaMes!$A:$A,0))))
--      /3/$K2
-- fVendaMes!$E/$F/$G = Q03/Q04/Q05 pelo OrdemFinal do .m. Só existe o termo
-- $DL2 (PESO_1): NÃO há termo $DN2 (PESO_2) nem referência a $DM2 (ANTIGO_2).
--
-- POR QUE ISSO É DESCUIDO, E NÃO REGRA. As colunas irmãs, que leem o MESMO
-- fVendaMes com a MESMA sucessão, somam os DOIS antecessores com os DOIS
-- pesos: AD/AE/AF (Q00/Q01/Q02) e AG (MED02..MED12). Só AQ para no primeiro.
-- Não existe leitura de negócio em que o segundo antecessor conte para a
-- média da janela e para os três últimos meses, mas não conte para os três
-- meses anteriores a eles — é a mesma demanda herdada, olhada mais atrás.
--
-- O QUE PASSAMOS A FAZER. vd_ant_3m herda com PESO_1 **e** PESO_2, como as
-- colunas irmãs. A CTE `vd_ant` ganhou o segundo termo, simétrico ao primeiro.
--
-- IMPACTO MEDIDO HOJE: ZERO. Nenhuma das 25 linhas de seed_sucessao tem
-- ANTIGO_2 preenchido e todas estão com ATIVO='NAO' — o segundo termo é 0 em
-- 100% das linhas, e o resultado é idêntico ao da planilha. A mudança vale
-- para o dia em que alguém cadastrar um segundo antecessor: sem ela, AQ
-- contaminaria TEND (AR) e VAR_PV (AT) com metade da herança.
-- Verificado em 21/08/2026 com uma linha de sucessão ativada temporariamente
-- (dois antecessores, pesos 1 e 0,5): a fórmula nova somou os dois termos, a
-- antiga só o primeiro, e o CSV/seed foram revertidos ao estado original.
--
-- Q03/Q04/Q05 continuam NÃO carregando essa herança dentro de Q00..Q11 — a
-- separação entre `herdado` e `vd_ant` permanece pelo motivo original: as
-- duas colunas têm consumidores diferentes e uma coluna intermediária única
-- serviria mal aos dois. O que mudou é só o CONTEÚDO de `vd_ant`, não a
-- arquitetura. (Nota: hoje, com os dois pesos dos dois lados, `vd_ant` é
-- algebricamente igual a (h.q03+h.q04+h.q05)/3; a CTE separada fica de pé
-- porque a origem da leitura continua sendo `pivot` e porque é ali que a
-- fórmula de AQ está reproduzida linha a linha.)
--
-- Duas divisões da fórmula do Excel NÃO estão aqui, de propósito:
--   - "/$K2" (FATOR_EXIBICAO): é conversão de unidade de exibição, decisão
--     da Etapa 4 (aba `pedido`), não do dado consolidado por SKU.
--   - "/3" (média dos 3 meses): esta SIM fica aqui, porque "vd_ant_3m" já é
--     por definição uma média mensal do histórico do antecessor - faz parte
--     do significado da coluna, não da exibição. Decisão: manter a média
--     (dividir por 3) e deixar só a divisão por FATOR_EXIBICAO para a Etapa 4.
--
-- ── CODIGO_NOVO duplicado — diferença de comportamento medida, não corrigida ──
-- Se um dia seed_sucessao tiver duas linhas com o mesmo CODIGO_NOVO, o Excel
-- (MATCH) pegaria silenciosamente a primeira ocorrência; aqui o join dá
-- fan-out (2 linhas para o mesmo codigo_produto) e reprova o teste `unique`
-- do seed (CODIGO_NOVO) antes mesmo de chegar neste model. Falhar alto é
-- melhor que herdar errado em silêncio, mas é uma diferença de comportamento
-- real entre planilha e dbt, e fica registrada aqui.
-- ─────────────────────────────────────────────────────────────────────────────

with pivot as (
    select * from {{ ref('int_venda_mensal_pivot') }}
),

periodo as (
    select * from {{ ref('int_periodo_mensal') }}
),

sucessao as (
    select * from {{ ref('seed_sucessao') }}
),

-- DK/DL/DM/DN do gabarito_pedido_formulas.txt: nada e aplicado se ATIVO <> 'SIM'.
regra as (
    select
        CODIGO_NOVO                                        as codigo_produto,
        case when ATIVO = 'SIM' then ANTIGO_1 end          as antigo_1,
        case when ATIVO = 'SIM' then nvl(PESO_1, 0) else 0 end as peso_1,
        case when ATIVO = 'SIM' then ANTIGO_2 end          as antigo_2,
        case when ATIVO = 'SIM' then nvl(PESO_2, 0) else 0 end as peso_2
      from sucessao
),

ant1 as (
    select
        r.codigo_produto,
        r.peso_1,
        p.qatual, p.q00, p.q01, p.q02, p.q03, p.q04, p.q05,
        p.q06, p.q07, p.q08, p.q09, p.q10, p.q11
      from regra r
      join pivot p on p.codigo_produto = r.antigo_1
     where r.antigo_1 is not null
),

ant2 as (
    select
        r.codigo_produto,
        r.peso_2,
        p.qatual, p.q00, p.q01, p.q02, p.q03, p.q04, p.q05,
        p.q06, p.q07, p.q08, p.q09, p.q10, p.q11
      from regra r
      join pivot p on p.codigo_produto = r.antigo_2
     where r.antigo_2 is not null
),

herdado as (
    select
        p.codigo_produto,
        p.qatual + nvl(a1.peso_1, 0) * nvl(a1.qatual, 0) + nvl(a2.peso_2, 0) * nvl(a2.qatual, 0) as qatual,
        p.q00 + nvl(a1.peso_1, 0) * nvl(a1.q00, 0) + nvl(a2.peso_2, 0) * nvl(a2.q00, 0) as q00,
        p.q01 + nvl(a1.peso_1, 0) * nvl(a1.q01, 0) + nvl(a2.peso_2, 0) * nvl(a2.q01, 0) as q01,
        p.q02 + nvl(a1.peso_1, 0) * nvl(a1.q02, 0) + nvl(a2.peso_2, 0) * nvl(a2.q02, 0) as q02,
        p.q03 + nvl(a1.peso_1, 0) * nvl(a1.q03, 0) + nvl(a2.peso_2, 0) * nvl(a2.q03, 0) as q03,
        p.q04 + nvl(a1.peso_1, 0) * nvl(a1.q04, 0) + nvl(a2.peso_2, 0) * nvl(a2.q04, 0) as q04,
        p.q05 + nvl(a1.peso_1, 0) * nvl(a1.q05, 0) + nvl(a2.peso_2, 0) * nvl(a2.q05, 0) as q05,
        p.q06 + nvl(a1.peso_1, 0) * nvl(a1.q06, 0) + nvl(a2.peso_2, 0) * nvl(a2.q06, 0) as q06,
        p.q07 + nvl(a1.peso_1, 0) * nvl(a1.q07, 0) + nvl(a2.peso_2, 0) * nvl(a2.q07, 0) as q07,
        p.q08 + nvl(a1.peso_1, 0) * nvl(a1.q08, 0) + nvl(a2.peso_2, 0) * nvl(a2.q08, 0) as q08,
        p.q09 + nvl(a1.peso_1, 0) * nvl(a1.q09, 0) + nvl(a2.peso_2, 0) * nvl(a2.q09, 0) as q09,
        p.q10 + nvl(a1.peso_1, 0) * nvl(a1.q10, 0) + nvl(a2.peso_2, 0) * nvl(a2.q10, 0) as q10,
        p.q11 + nvl(a1.peso_1, 0) * nvl(a1.q11, 0) + nvl(a2.peso_2, 0) * nvl(a2.q11, 0) as q11
      from pivot p
      left join ant1 a1 on a1.codigo_produto = p.codigo_produto
      left join ant2 a2 on a2.codigo_produto = p.codigo_produto
),

-- Mesma guarda global de int_venda_mensal_pivot (ver cabeçalho de lá).
meses_fechados as (
    select qtd_meses - 1 as n_fechados from periodo
),

-- AQ (VD_ANT_3M): MELHORIA D1 - heranca SIMETRICA, PESO_1 * antecessor_1 E
-- PESO_2 * antecessor_2, como AD/AE/AF e AG. A planilha so' escreveu o
-- primeiro termo; o segundo esta aqui de proposito - ver secao propria no
-- cabecalho. Lida a partir de Q03/Q04/Q05 do PROPRIO pivot (nao de `herdado`).
-- Sem "/$K2" (FATOR_EXIBICAO e' da Etapa 4); com "/3" (a media faz parte do
-- significado da coluna).
vd_ant as (
    select
        p.codigo_produto,
        (
            p.q03 + p.q04 + p.q05
            + nvl(a1.peso_1, 0) * (nvl(a1.q03, 0) + nvl(a1.q04, 0) + nvl(a1.q05, 0))
            + nvl(a2.peso_2, 0) * (nvl(a2.q03, 0) + nvl(a2.q04, 0) + nvl(a2.q05, 0))
        ) / 3 as vd_ant_3m
      from pivot p
      left join ant1 a1 on a1.codigo_produto = p.codigo_produto
      left join ant2 a2 on a2.codigo_produto = p.codigo_produto
),

final as (
    select
        p.codigo_produto,
        h.q00, h.q01, h.q02, h.q03, h.q04, h.q05,
        h.q06, h.q07, h.q08, h.q09, h.q10, h.q11,
        p.v00, p.v01, p.v02, p.v03, p.v04, p.v05,
        h.qatual,
        p.vatual, p.cli_atac_atual, p.cli_var_atual, p.dias_sem_est_atual, p.fora_de_linha,
        p.tx_devolucao_3m, p.cli_atac_00, p.cli_var_00, p.dias_sem_est_00,
        va.vd_ant_3m,
        case when mf.n_fechados >= 2
             then (h.q00 + h.q01) / 2
        end as med02,
        case when mf.n_fechados >= 3
             then (h.q00 + h.q01 + h.q02) / 3
        end as med03,
        case when mf.n_fechados >= 4
             then (h.q00 + h.q01 + h.q02 + h.q03) / 4
        end as med04,
        case when mf.n_fechados >= 6
             then (h.q00 + h.q01 + h.q02 + h.q03 + h.q04 + h.q05) / 6
        end as med06,
        case when mf.n_fechados >= 9
             then (h.q00+h.q01+h.q02+h.q03+h.q04+h.q05+h.q06+h.q07+h.q08) / 9
        end as med09,
        case when mf.n_fechados >= 12
             then (h.q00+h.q01+h.q02+h.q03+h.q04+h.q05+h.q06+h.q07+h.q08+h.q09+h.q10+h.q11) / 12
        end as med12
      from pivot p
      join herdado h on h.codigo_produto = p.codigo_produto
      join vd_ant va on va.codigo_produto = p.codigo_produto
     cross join meses_fechados mf
)

select * from final
