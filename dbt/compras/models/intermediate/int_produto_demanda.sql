-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_demanda — colunas Q a AW da aba `pedido` (menos as de alerta),
-- mais AZ. Estoque, venda, tendência e sugestão de cobertura.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna, com a
-- marca DIVIDE / NÃO DIVIDE por $K2 (FATOR_EXIBICAO) - ver seção própria abaixo:
--   Q  EST_DISP           dCadastroTI!$W  / $K2        DIVIDE
--   R  QT_BLOQUEADA       dCadastroTI!$T               NÃO divide
--   S  QT_AVARIA          dCadastroTI!$U               NÃO divide
--   T  QT_RESERVADA       dCadastroTI!$V               NÃO divide
--   U  PENDENTE           dCadastroTI!$S  / $K2        DIVIDE
--   V  EST+PEND           $Q2 + $U2                    (já dividido nas parcelas)
--   W  EST_FABRICA        fEstFabrica!$C por $B2 / $K2 DIVIDE, "" se não achar
--   X  CHECK_FABRICA      alerta - leva seguinte
--   Y  CHECK_INATIVO      alerta - leva seguinte
--   Z  DT_ULT_ENT         dCadastroTI!$X               data
--   AA QT_ULT_ENT         dCadastroTI!$Y  / $K2        DIVIDE
--   AB N_MESES            dFornecedor!$B por $F2       NÃO divide
--   AC VD MES ATUAL       fVendaMes!$T (QATUAL) / $K2  DIVIDE
--   AD VD M-1             fVendaMes!$B (Q00)    / $K2  DIVIDE
--   AE VD M-2             fVendaMes!$C (Q01)    / $K2  DIVIDE
--   AF VD M-3             fVendaMes!$D (Q02)    / $K2  DIVIDE
--   AG MEDIA_JANELA       fVendaMes!$AD:$AI     / $K2  DIVIDE
--   AH MEDIA_L            $AG2 * $K2 * $L2             (desfaz a divisão!)
--   AI QT_CLI_ATACADO     fVendaMes!$AA (CLI_ATAC_00)  NÃO divide
--   AJ QT_CLI_VAREJO      fVendaMes!$AB (CLI_VAR_00)   NÃO divide
--   AK DIAS_SEM_ESTOQUE   fVendaMes!$AC (DIAS_SEM_EST_00) NÃO divide
--   AL CHECK_RUPTURA      alerta - leva seguinte
--   AM DT_ULT_SAIDA       dCadastroTI!$AE              data
--   AN DIAS_SEM_VENDA     TODAY() - $AM2               "" se não há data
--   AO CHECK_ESTOQUE_PARADO / AP CHECK_FORA_DE_LINHA   alertas - leva seguinte
--   AQ VD_ANT_3M          fVendaMes!$E+$F+$G /3 / $K2  DIVIDE (o /3 já veio pronto)
--   AR TEND %             ($AD+$AE+$AF)/3/$AQ2 - 1     "" se $AQ2 = 0
--   AS TEND               ALTA / QUEDA / ESTAVEL / SEM BASE
--   AT VAR_PV             razão de preço médio recente x antigo
--   AU TX_DEVOLUCAO_3M    fVendaMes!$Z                 NÃO divide
--   AV CHECK_DEVOLUCAO_ALTA / AY CHECK_LITRAGEM        alertas - leva seguinte
--   AW MESES_EST          $V2 / $AG2                   "" se $AG2 = 0
--   AX CLASSE             int_produto_classe_abc (model próprio)
--   AZ SUG_COBERTURA      MAX(0, ROUND($AG2*cobertura - $V2, 0))
-- (mapa das letras de dCadastroTI e de fVendaMes: docs/gabarito_powerquery.m,
-- passos `Selecionado` e `OrdemFinal`.)
--
-- Grão: 1 linha por SKU. Espinha = int_produto_base (= o cadastro inteiro).
-- 4.860 dos 8.776 SKUs não têm nenhuma linha de venda; o left join com
-- nvl(...,0) reproduz o IFERROR(...,0) do Excel, que trata "código ausente em
-- fVendaMes" exatamente como "vendeu zero".
--
-- ── Por que $K2 aparece em umas colunas e não em outras ─────────────────────
-- CONTEXTO.md regra 6. FATOR_EXIBICAO converte UNIDADE para CAIXA MASTER na
-- EXIBIÇÃO. A planilha divide o que o comprador lê "em caixas" (disponível,
-- pendente, última entrada, todas as vendas, estoque de fábrica) e NÃO divide
-- o que ele lê em outra unidade: bloqueada/avaria/reservada continuam em
-- unidades, contagem de clientes e dias são contagens, taxa de devolução é
-- adimensional. Não há regra geral para deduzir - foi conferido linha a linha
-- contra o gabarito, e a tabela acima é o resultado dessa conferência.
-- AH (MEDIA_L) é o caso invertido: multiplica de volta por $K2 para voltar a
-- unidades antes de multiplicar pela litragem UNITÁRIA.
--
-- ── AB | N_MESES ESCOLHE qual média usar ────────────────────────────────────
-- AG faz INDEX(fVendaMes!$AD:$AI, ..., MATCH($AB2,{2;3;4;6;9;12},0)): o número
-- de meses do fornecedor é um SELETOR de coluna, 2->MED02 ... 12->MED12. Valor
-- FORA dessa lista faz o MATCH devolver #N/A, o INDEX propagar o erro e o
-- IFERROR externo devolver 0 - a média inteira vira ZERO, e por AX isso vira
-- classe 'S/VEND'. O `else 0` do case reproduz isso de propósito. Medido hoje:
-- os 59 departamentos do seed_fornecedor usam 2, 3, 4, 6 ou 12 - nenhum valor
-- fora da lista, e o fallback N_MESES_PADRAO também está nela (3).
--
-- ── O que já vem pronto de int_venda_mensal_sucessao ────────────────────────
-- A herança de produto descontinuado (colunas DK/DL/DM/DN) já está aplicada lá:
-- QATUAL/Q00..Q11/MED* e `vd_ant_3m` herdam TODOS com os DOIS pesos. ⚠ Na
-- planilha AQ (VD_ANT_3M) herdava só com PESO_1 - assimetria fechada pela
-- MELHORIA D1 (MELHORIAS.md; CONTEXTO.md §6.0), com impacto ZERO hoje. Deste
-- lado sobra só a divisão por $K2, que é decisão de exibição da aba `pedido`.
--
-- ── AT | VAR_PV: por que os $K2 se cancelam ─────────────────────────────────
-- É a razão entre dois preços médios: (V00+V01+V02)/(AD+AE+AF) contra
-- (V03+V04+V05)/($AQ2*3). Os VALORES (V*) não são divididos por $K2 e as
-- QUANTIDADES (AD/AE/AF, AQ) são - o fator sai na divisão, então a razão final
-- independe dele. A fórmula fica literal mesmo assim, para conferir com o
-- gabarito sem raciocínio intermediário. V00..V05 são os do PRÓPRIO SKU: a
-- fórmula do Excel não aplica herança de sucessão no valor, só na quantidade.
-- Os `nullif` reproduzem o IFERROR(...,"") externo - qualquer um dos três
-- denominadores zerado devolve vazio, não erro e não zero.
--
-- ── AN | DIAS_SEM_VENDA depende de TODAY() ──────────────────────────────────
-- É a fórmula: TODAY() - $AM2. Logo o valor MUDA entre dois builds em dias
-- diferentes, e o alerta AO (CHECK_ESTOQUE_PARADO, > DIAS_ESTOQUE_PARADO) pode
-- passar a disparar sem que nada tenha mudado no dado. É o comportamento da
-- planilha, que também recalcula ao abrir. Comparação contra o original tem que
-- ser feita no MESMO dia (CONTEXTO.md 6.3).
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

cadastro as (
    select * from {{ ref('int_cadastro_estoque') }}
),

venda as (
    select * from {{ ref('int_venda_mensal_sucessao') }}
),

fornecedor as (
    select * from {{ ref('seed_fornecedor') }}
),

est_fabrica as (
    select * from {{ ref('seed_est_fabrica') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- AB e a cobertura de AZ dependem de $F2 (o texto do departamento), nao do
-- codigo do fornecedor legal - ver cabecalho de int_produto_base.
regra_fornecedor as (
    select
        b.codigo,
        b.fornecedor,
        b.fator_exibicao,
        b.l_por_unidade,
        nvl(f.MESES_MEDIA,    p.n_meses_padrao)        as n_meses,
        nvl(f.COBERTURA_ALVO, p.cobertura_alvo_padrao) as cobertura_alvo
      from base b
      cross join parametro p
      left join fornecedor f
        on upper(f.FORNECEDOR) = upper(b.fornecedor)
),

-- Q..AA: posicao de estoque, direto do cadastro.
estoque as (
    select
        r.codigo,
        nvl(c.qtdisp, 0)      / r.fator_exibicao as est_disp,
        nvl(c.qtbloqueada, 0)                    as qt_bloqueada,
        nvl(c.qtavaria, 0)                       as qt_avaria,
        nvl(c.qtreserv, 0)                       as qt_reservada,
        nvl(c.qtpedida, 0)    / r.fator_exibicao as pendente,
        ef.DISPONIVEL         / r.fator_exibicao as est_fabrica,
        c.dt_ult_ent,
        nvl(c.qt_ult_ent, 0)  / r.fator_exibicao as qt_ult_ent,
        c.dt_ult_saida
      from regra_fornecedor r
      join cadastro c
        on c.codprod = r.codigo
      left join est_fabrica ef
        on upper(ef.COD_FAB) = upper(c.codfab)
),

-- AC..AQ: venda, ja com a heranca de sucessao aplicada a montante.
demanda as (
    select
        r.codigo,
        nvl(v.qatual, 0) / r.fator_exibicao as vd_mes_atual,
        nvl(v.q00, 0)    / r.fator_exibicao as vd_m1,
        nvl(v.q01, 0)    / r.fator_exibicao as vd_m2,
        nvl(v.q02, 0)    / r.fator_exibicao as vd_m3,
        -- AG: N_MESES seleciona a coluna de media; fora da lista -> 0
        case r.n_meses
             when 2  then nvl(v.med02, 0)
             when 3  then nvl(v.med03, 0)
             when 4  then nvl(v.med04, 0)
             when 6  then nvl(v.med06, 0)
             when 9  then nvl(v.med09, 0)
             when 12 then nvl(v.med12, 0)
             else 0
        end / r.fator_exibicao                 as media_janela,
        nvl(v.cli_atac_00, 0)                  as qt_cli_atacado,
        nvl(v.cli_var_00, 0)                   as qt_cli_varejo,
        nvl(v.dias_sem_est_00, 0)              as dias_sem_estoque,
        nvl(v.vd_ant_3m, 0) / r.fator_exibicao as vd_ant_3m,
        nvl(v.tx_devolucao_3m, 0)              as tx_devolucao_3m,
        nvl(v.v00, 0)                          as v00,
        nvl(v.v01, 0)                          as v01,
        nvl(v.v02, 0)                          as v02,
        nvl(v.v03, 0)                          as v03,
        nvl(v.v04, 0)                          as v04,
        nvl(v.v05, 0)                          as v05
      from regra_fornecedor r
      left join venda v
        on v.codigo_produto = r.codigo
),

-- Colunas que dependem das anteriores na MESMA linha (V, AH, AN, AR..AW, AZ).
derivado as (
    select
        r.codigo,
        r.fator_exibicao,
        r.l_por_unidade,
        r.n_meses,
        r.cobertura_alvo,
        e.est_disp,
        e.qt_bloqueada,
        e.qt_avaria,
        e.qt_reservada,
        e.pendente,
        e.est_disp + e.pendente                             as est_pend,
        e.est_fabrica,
        e.dt_ult_ent,
        e.qt_ult_ent,
        e.dt_ult_saida,
        d.vd_mes_atual,
        d.vd_m1,
        d.vd_m2,
        d.vd_m3,
        d.media_janela,
        d.media_janela * r.fator_exibicao * r.l_por_unidade as media_l,
        d.qt_cli_atacado,
        d.qt_cli_varejo,
        d.dias_sem_estoque,
        d.vd_ant_3m,
        d.tx_devolucao_3m,
        d.v00, d.v01, d.v02, d.v03, d.v04, d.v05,
        p.tend_limiar
      from regra_fornecedor r
      join estoque e on e.codigo = r.codigo
      join demanda d on d.codigo = r.codigo
     cross join parametro p
),

final as (
    select
        d.codigo,
        d.est_disp,
        d.qt_bloqueada,
        d.qt_avaria,
        d.qt_reservada,
        d.pendente,
        d.est_pend,
        d.est_fabrica,
        d.dt_ult_ent,
        d.qt_ult_ent,
        d.n_meses,
        d.vd_mes_atual,
        d.vd_m1,
        d.vd_m2,
        d.vd_m3,
        d.media_janela,
        d.media_l,
        d.qt_cli_atacado,
        d.qt_cli_varejo,
        d.dias_sem_estoque,
        d.dt_ult_saida,
        -- AN: IF($AM2="","",TODAY()-$AM2). dt_ult_saida ja vem sem hora.
        case when d.dt_ult_saida is not null
             then trunc(sysdate) - d.dt_ult_saida
        end                                            as dias_sem_venda,
        d.vd_ant_3m,
        -- AR: IF($AQ2=0,"",($AD2+$AE2+$AF2)/3/$AQ2-1)
        case when d.vd_ant_3m <> 0
             then (d.vd_m1 + d.vd_m2 + d.vd_m3) / 3 / d.vd_ant_3m - 1
        end                                            as tend_perc,
        -- AS: limiar do int_parametro (TEND_LIMIAR), nao 0,15 chumbado
        case when d.vd_ant_3m = 0
             then 'SEM BASE'
             when (d.vd_m1 + d.vd_m2 + d.vd_m3) / 3 / d.vd_ant_3m - 1 > d.tend_limiar
             then 'ALTA'
             when (d.vd_m1 + d.vd_m2 + d.vd_m3) / 3 / d.vd_ant_3m - 1 < -1 * d.tend_limiar
             then 'QUEDA'
             else 'ESTAVEL'
        end                                            as tend,
        -- AT: os nullif reproduzem o IFERROR(...,"") - ver cabecalho
          (d.v00 + d.v01 + d.v02) / nullif(d.vd_m1 + d.vd_m2 + d.vd_m3, 0)
        / nullif((d.v03 + d.v04 + d.v05) / nullif(d.vd_ant_3m * 3, 0), 0)
        - 1                                            as var_pv,
        d.tx_devolucao_3m,
        -- AW: IF($AG2=0,"",$V2/$AG2)
        case when d.media_janela <> 0
             then d.est_pend / d.media_janela
        end                                            as meses_est,
        -- AZ: MAX(0, ROUND($AG2 * cobertura - $V2, 0)). ROUND do Excel e do
        -- Oracle sao os dois "metade para longe do zero" - mesmo resultado.
        greatest(0, round(d.media_janela * d.cobertura_alvo - d.est_pend, 0)) as sug_cobertura
      from derivado d
)

select * from final
