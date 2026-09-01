-- ─────────────────────────────────────────────────────────────────────────────
-- compras_pedido — CONTRATO com o dashboard (Etapa 6). Tabela física
-- COMPRAS_PEDIDO. Projeção PURA de fat_pedido: as mesmas 122 colunas, na
-- mesma ordem, cada uma só com o alias trocado para o cabeçalho da aba
-- `pedido` em MAIÚSCULA (identificador Oracle não-aspado já é maiúsculo -
-- escrever assim aqui é convenção de legibilidade: sinaliza "isto é
-- contrato público"). Sem cálculo, sem case, sem nvl, sem join: se um número
-- está errado, o defeito mora em fat_pedido ou a montante dele, nunca aqui.
--
-- Qual coluna Excel reproduz: TODAS, A a DR. Ver o comentário à direita de
-- cada linha, herdado literalmente de fat_pedido.sql.
--
-- Grão: 1 linha por SKU (CODIGO), o mesmo de fat_pedido.
--
-- ── Por que NÃO tem ATUALIZADO_EM / ATUALIZADO_POR das tabelas APP_* ───────
-- Decisão deliberada, não esquecimento. O dashboard lê as APP_* (decisão de
-- pedido, de margem alvo, de preço) AO VIVO. Uma cópia desses metadados aqui
-- só se atualizaria no próximo `dbt run`, e a tela passaria a ter DUAS
-- respostas possíveis para "quem decidiu e quando" - uma viva (nas APP_*) e
-- uma velha (aqui). O que dessas tabelas É NÚMERO de cálculo (PEDIDO,
-- MARGEM_ALVO, ALT_PV_*) já entrou no intermediate por left join e chega
-- aqui dentro de fat_pedido - não se junta stg_decisao_* de novo nesta
-- camada.
-- ─────────────────────────────────────────────────────────────────────────────

select
    codigo                          as CODIGO,                          -- A  | CODIGO
    cod_fab                         as COD_FAB,                         -- B  | COD_FAB
    descricao                       as DESCRICAO,                       -- C  | DESCRICAO
    alerta                          as ALERTA,                          -- D  | ALERTA
    status                          as STATUS,                          -- E  | STATUS
    fornecedor                      as FORNECEDOR,                      -- F  | FORNECEDOR
    comprador                       as COMPRADOR,                       -- G  | COMPRADOR
    embalagem                       as EMBALAGEM,                       -- H  | EMBALAGEM
    nao_usado                       as NAO_USADO,                       -- I  | (nao usado)
    embal_compra                    as EMBAL_COMPRA,                    -- J  | EMBAL_COMPRA
    fator_exibicao                  as FATOR_EXIBICAO,                  -- K  | FATOR_EXIBICAO
    l_por_unidade                   as L_POR_UNIDADE,                   -- L  | L_POR_UNIDADE
    peso_unitario_kg                as PESO_UNITARIO_KG,                -- M  | PESO_UNITARIO_KG
    qt_palete                       as QT_PALETE,                       -- N  | QT_PALETE
    nivel_base_margem               as NIVEL_BASE_MARGEM,               -- O  | NIVEL_BASE_MARGEM
    nivel_margem                    as NIVEL_MARGEM,                    -- P  | NIVEL_MARGEM
    est_disp                        as EST_DISP,                        -- Q  | EST_DISP
    qt_bloqueada                    as QT_BLOQUEADA,                    -- R  | QT_BLOQUEADA
    qt_avaria                       as QT_AVARIA,                       -- S  | QT_AVARIA
    qt_reservada                    as QT_RESERVADA,                    -- T  | QT_RESERVADA
    pendente                        as PENDENTE,                        -- U  | PENDENTE
    est_pend                        as EST_PEND,                        -- V  | EST+PEND
    est_fabrica                     as EST_FABRICA,                     -- W  | EST_FABRICA
    check_fabrica                   as CHECK_FABRICA,                   -- X  | CHECK_FABRICA
    check_inativo                   as CHECK_INATIVO,                   -- Y  | CHECK_INATIVO
    dt_ult_ent                      as DT_ULT_ENT,                      -- Z  | DT_ULT_ENT
    qt_ult_ent                      as QT_ULT_ENT,                      -- AA | QT_ULT_ENT
    n_meses                         as N_MESES,                         -- AB | N_MESES
    vd_mes_atual                    as VD_MES_ATUAL,                    -- AC | VD MES ATUAL
    vd_m_1                          as VD_M_1,                          -- AD | VD M-1
    vd_m_2                          as VD_M_2,                          -- AE | VD M-2
    vd_m_3                          as VD_M_3,                          -- AF | VD M-3
    media_janela                    as MEDIA_JANELA,                    -- AG | MEDIA_JANELA
    media_l                         as MEDIA_L,                         -- AH | MEDIA_L
    qt_cli_atacado                  as QT_CLI_ATACADO,                  -- AI | QT_CLI_ATACADO
    qt_cli_varejo                   as QT_CLI_VAREJO,                   -- AJ | QT_CLI_VAREJO
    dias_sem_estoque                as DIAS_SEM_ESTOQUE,                -- AK | DIAS_SEM_ESTOQUE
    check_ruptura                   as CHECK_RUPTURA,                   -- AL | CHECK_RUPTURA
    dt_ult_saida                    as DT_ULT_SAIDA,                    -- AM | DT_ULT_SAIDA
    dias_sem_venda                  as DIAS_SEM_VENDA,                  -- AN | DIAS_SEM_VENDA
    check_estoque_parado            as CHECK_ESTOQUE_PARADO,            -- AO | CHECK_ESTOQUE_PARADO
    check_fora_de_linha             as CHECK_FORA_DE_LINHA,             -- AP | CHECK_FORA_DE_LINHA
    vd_ant_3m                       as VD_ANT_3M,                       -- AQ | VD_ANT_3M
    tend_pct                        as TEND_PCT,                        -- AR | TEND %
    tend                            as TEND,                            -- AS | TEND
    var_pv                          as VAR_PV,                          -- AT | VAR_PV
    tx_devolucao_3m                 as TX_DEVOLUCAO_3M,                 -- AU | TX_DEVOLUCAO_3M
    check_devolucao_alta            as CHECK_DEVOLUCAO_ALTA,            -- AV | CHECK_DEVOLUCAO_ALTA
    meses_est                       as MESES_EST,                       -- AW | MESES_EST
    classe                          as CLASSE,                          -- AX | CLASSE
    check_litragem                  as CHECK_LITRAGEM,                  -- AY | CHECK_LITRAGEM
    sug_cobertura                   as SUG_COBERTURA,                   -- AZ | SUG_COBERTURA
    pedido                          as PEDIDO,                          -- BA | PEDIDO
    pedido_unidades                 as PEDIDO_UNIDADES,                 -- BB | PEDIDO_UNIDADES
    pedido_na_medida                as PEDIDO_NA_MEDIDA,                -- BC | PEDIDO_NA_MEDIDA
    valor_pedido                    as VALOR_PEDIDO,                    -- BD | VALOR_PEDIDO
    sug_palete                      as SUG_PALETE,                      -- BE | SUG_PALETE
    meses_est_ped                   as MESES_EST_PED,                   -- BF | MESES_EST+PED
    valor_estoque                   as VALOR_ESTOQUE,                   -- BG | VALOR_ESTOQUE
    vl_ent_unit                     as VL_ENT_UNIT,                     -- BH | VL_ENT_UNIT
    custo_ult_ent                   as CUSTO_ULT_ENT,                   -- BI | CUSTO_ULT_ENT
    cod_icms                        as COD_ICMS,                        -- BJ | COD_ICMS
    cod_piscof                      as COD_PISCOF,                      -- BK | COD_PISCOF
    modalidade                      as MODALIDADE,                      -- BL | MODALIDADE
    mva                             as MVA,                             -- BM | MVA
    uf_origem                       as UF_ORIGEM,                       -- BN | UF_ORIGEM
    cred_total                      as CRED_TOTAL,                      -- BO | CRED_TOTAL
    aliq_icms_origem                as ALIQ_ICMS_ORIGEM,                -- BP | ALIQ_ICMS_ORIGEM
    cred_icms                       as CRED_ICMS,                       -- BQ | CRED_ICMS
    cred_piscof                     as CRED_PISCOF,                     -- BR | CRED_PISCOF
    check_importado                 as CHECK_IMPORTADO,                 -- BS | CHECK_IMPORTADO
    icms_st_s_valor                 as ICMS_ST_S_VALOR,                 -- BT | ICMS_ST_s/VALOR
    icms_st_s_custo                 as ICMS_ST_S_CUSTO,                 -- BU | ICMS_ST_s/CUSTO
    custo_tot_s_valor               as CUSTO_TOT_S_VALOR,               -- BV | CUSTO_TOT_s/VALOR
    custo_tot_oficial               as CUSTO_TOT_OFICIAL,               -- BW | CUSTO_TOT_OFICIAL
    custo_adicional_imagem          as CUSTO_ADICIONAL_IMAGEM,          -- BX | CUSTO_ADICIONAL_IMAGEM
    custo_tot_gerencial             as CUSTO_TOT_GERENCIAL,             -- BY | CUSTO_TOT_GERENCIAL
    piscof_ef                       as PISCOF_EF,                       -- BZ | PISCOF_EF
    icms_saida_ef                   as ICMS_SAIDA_EF,                   -- CA | ICMS_SAIDA_EF
    icms_sem_red                    as ICMS_SEM_RED,                    -- CB | ICMS_SEM_RED
    check_trib                      as CHECK_TRIB,                      -- CC | CHECK_TRIB
    check_mva                       as CHECK_MVA,                       -- CD | CHECK_MVA
    check_custo                     as CHECK_CUSTO,                     -- CE | CHECK_CUSTO
    pv_atacado                      as PV_ATACADO,                      -- CF | PV_ATACADO
    mkp_atacado                     as MKP_ATACADO,                     -- CG | MKP_ATACADO
    margem_st_s_valor               as MARGEM_ST_S_VALOR,               -- CH | MARGEM_ST_s/VALOR
    margem_oficial                  as MARGEM_OFICIAL,                  -- CI | MARGEM_OFICIAL
    margem_sem_red                  as MARGEM_SEM_RED,                  -- CJ | MARGEM_SEM_RED
    gap_filial_pp                   as GAP_FILIAL_PP,                   -- CK | GAP_FILIAL_pp
    check_margem_instavel           as CHECK_MARGEM_INSTAVEL,           -- CL | CHECK_MARGEM_INSTAVEL
    dif_mc_pp                       as DIF_MC_PP,                       -- CM | DIF_MC_pp
    margem_alvo                     as MARGEM_ALVO,                     -- CN | MARGEM_ALVO
    pv_sug_st_s_valor_av            as PV_SUG_ST_S_VALOR_AV,            -- CO | PV_SUG_ST_s/VALOR_AV
    pv_sug_st_s_valor_ap            as PV_SUG_ST_S_VALOR_AP,            -- CP | PV_SUG_ST_s/VALOR_AP
    pv_sug_oficial_av               as PV_SUG_OFICIAL_AV,               -- CQ | PV_SUG_OFICIAL_AV
    pv_sug_oficial_ap               as PV_SUG_OFICIAL_AP,               -- CR | PV_SUG_OFICIAL_AP
    pv_sug_sem_red_av               as PV_SUG_SEM_RED_AV,               -- CS | PV_SUG_SEM_RED_AV
    pv_sug_sem_red_ap               as PV_SUG_SEM_RED_AP,               -- CT | PV_SUG_SEM_RED_AP
    alt_pv_at_av                    as ALT_PV_AT_AV,                    -- CU | ALT_PV_AT_AV
    alt_pv_at_ap                    as ALT_PV_AT_AP,                    -- CV | ALT_PV_AT_AP
    pv_varejo                       as PV_VAREJO,                       -- CW | PV_VAREJO
    mkp_varejo                      as MKP_VAREJO,                      -- CX | MKP_VAREJO
    margem_st_s_valor_varejo        as MARGEM_ST_S_VALOR_VAREJO,        -- CY | MARGEM_ST_s/VALOR_VAREJO
    margem_sem_red_varejo           as MARGEM_SEM_RED_VAREJO,           -- CZ | MARGEM_SEM_RED_VAREJO
    gap_filial_varejo_pp            as GAP_FILIAL_VAREJO_PP,            -- DA | GAP_FILIAL_VAREJO_pp
    check_margem_instavel_varejo    as CHECK_MARGEM_INSTAVEL_VAREJO,    -- DB | CHECK_MARGEM_INSTAVEL_VAREJO
    dif_mc_varejo_pp                as DIF_MC_VAREJO_PP,                -- DC | DIF_MC_VAREJO_pp
    margem_alvo_varejo              as MARGEM_ALVO_VAREJO,              -- DD | MARGEM_ALVO_VAREJO
    pv_sug_st_s_valor_var_av        as PV_SUG_ST_S_VALOR_VAR_AV,        -- DE | PV_SUG_ST_s/VALOR_VAR_AV
    pv_sug_st_s_valor_var_ap        as PV_SUG_ST_S_VALOR_VAR_AP,        -- DF | PV_SUG_ST_s/VALOR_VAR_AP
    pv_sug_sem_red_var_av           as PV_SUG_SEM_RED_VAR_AV,           -- DG | PV_SUG_SEM_RED_VAR_AV
    pv_sug_sem_red_var_ap           as PV_SUG_SEM_RED_VAR_AP,           -- DH | PV_SUG_SEM_RED_VAR_AP
    alt_pv_var_av                   as ALT_PV_VAR_AV,                   -- DI | ALT_PV_VAR_AV
    alt_pv_var_ap                   as ALT_PV_VAR_AP,                   -- DJ | ALT_PV_VAR_AP
    ant_1                           as ANT_1,                           -- DK | ANT_1
    peso_1                          as PESO_1,                          -- DL | PESO_1
    ant_2                           as ANT_2,                           -- DM | ANT_2
    peso_2                          as PESO_2,                          -- DN | PESO_2
    check_sucessao                  as CHECK_SUCESSAO,                  -- DO | CHECK_SUCESSAO
    nivel_base_margem_varejo        as NIVEL_BASE_MARGEM_VAREJO,        -- DP | NIVEL_BASE_MARGEM_VAREJO
    nivel_margem_varejo             as NIVEL_MARGEM_VAREJO,             -- DQ | NIVEL_MARGEM_VAREJO
    cred_total_empirico             as CRED_TOTAL_EMPIRICO              -- DR | CRED_TOTAL_EMPIRICO
  from {{ ref('fat_pedido') }}
