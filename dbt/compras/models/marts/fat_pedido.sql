-- ─────────────────────────────────────────────────────────────────────────────
-- fat_pedido — AS 122 COLUNAS DA ABA `pedido`, NA ORDEM EXATA DO GABARITO.
-- É o artefato que fecha o critério de aceite do projeto (CONTEXTO.md §7):
-- 122 colunas x 8.772 linhas comparadas célula a célula com a planilha v10 por
-- `validar/validar_pedido.py`, tolerância 0,01.
--
-- Qual coluna Excel reproduz: TODAS. Cada linha do select abaixo traz, no
-- comentário à direita, a letra da coluna e o cabeçalho da aba. A regra de
-- negócio de cada uma mora no model intermediate que a produz - aqui não há
-- cálculo nenhum, de propósito (ver seção "por que este model é burro").
--
-- Grão: 1 linha por SKU (codigo), o mesmo do cadastro. 8.776 hoje.
--
-- ── Por que este model é BURRO, e tem de continuar sendo ───────────────────
-- fat_pedido é só a junção dos dez models de produto por `codigo`. Nenhuma
-- expressão, nenhum `case`, nenhum `nvl`. O motivo é de auditoria: quando o
-- validador aponta divergência numa coluna, o defeito tem UM lugar possível -
-- o model que a calcula. Uma correção feita aqui, na junção, ficaria invisível
-- para quem lesse o model de origem e criaria duas verdades para a mesma
-- coluna. Se a conta está errada, conserta-se no intermediate.
--
-- ── Os nomes das colunas são CONTRATO com o validador ──────────────────────
-- `validar_pedido.py` casa cada coluna da planilha com a do banco pelo slug do
-- CABEÇALHO da aba (`_slug`: minúsculas, espaço/hífen/barra viram '_', '%'
-- vira 'pct'), com um resolvedor que ignora pontuação. Renomear coluna aqui
-- quebra o aceite em silêncio - a coluna some da comparação em vez de
-- reprovar. Três casos onde o nome daqui NÃO é o do intermediate, e por quê:
--   AR  TEND %   -> `tend_pct`  (o intermediate publica `tend_perc`, que não
--                   casa: 'tendperc' != 'tendpct')
--   AD/AE/AF     -> `vd_m_1/2/3` (o intermediate publica `vd_m1`; casam pelo
--                   resolvedor, que ignora o '_', mas o nome literal do
--                   cabeçalho é mantido aqui por ser a camada de contrato)
--   I            -> `nao_usado`, coluna VAZIA na planilha, mantida para que a
--                   contagem de 122 e a posição de todas as outras batam. O
--                   validador a ignora explicitamente (LETRAS_IGNORADAS).
--
-- ── ⚠ ONDE ESTE MODEL DIVERGE DO xlsx EM referencia/, DE PROPÓSITO ────────
-- O gabarito é a v11 (referencia/MODELO_COMPRAS_CEDEP_v11.xlsx). Divergir dela
-- nas colunas abaixo é ESPERADO - não é defeito de porte, e reverter qualquer
-- uma desfaz decisão de negócio já tomada. Duas origens:
--   (a) decisões do Diretor de Compras que ele ainda NÃO aplicou na planilha
--       (PENDENCIAS_DIRETORIA.md itens 3 e 4; CONTEXTO.md §6.0/§6.4);
--   (b) melhorias aprovadas em 21/08/2026 (MELHORIAS.md; CONTEXTO.md §6.0),
--       que valem porque a planilha passou a ser PONTO DE PARTIDA, não alvo de
--       réplica exata.
--   1. CH, CY, CO, DE - cenário "ST s/Valor" usa ICMS_SEM_RED (alíquota CHEIA)
--      no lugar de ICMS_SAIDA_EF; CP e DF mudam por consequência (fator de
--      prazo). ✅ JÁ CORRIGIDO NA v11 pelo Diretor - contra a v11 estas seis
--      colunas FECHAM. Ficam listadas porque divergem da v10 e porque a decisão
--      (PENDENCIAS item 1) é o que sustenta a fórmula. Substituição tributária
--      e redução de base são mecânicas separadas. Nenhum item em regime ST
--      muda; ~1.240 SKUs de margem e ~2.095 de preço sugerido, todos de
--      MODALIDADE = 'NORMAL'. Os cenários "Oficial" (CI, CQ, CR) e "Sem
--      Redução" (CJ, CZ, CS, CT, DG, DH) NÃO foram tocados.
--   2. BO (CRED_TOTAL) - a grafia do seed_credito virou 'CAR 80', com espaço,
--      para casar com o departamento da base. Os 41 SKUs desse departamento
--      deixam de cair no crédito empírico e passam a usar o tabelado.
--      ⚠ Alcance MEDIDO, menor do que a nota do Diretor previa: muda BO em 39
--      dos 41 (nos outros 2 o empírico já dava o valor tabelado) e NÃO muda
--      ICMS-ST, custo, margem, preço nem ALERTA em nenhum deles - porque BQ
--      (CRED_ICMS) lê DR, o crédito empírico, e não BO (ver item 2 das
--      pendências, decidido como INTENCIONAL). O único consumidor de BO é BS
--      (CHECK_IMPORTADO), e nos 41 o limiar não virou de lado.
--   3. CC (CHECK_TRIB) - deixa de ser fórmula morta: dispara com código de
--      tributação vazio OU zero, cobrindo os 5 SKUs de codst = 0. Esses 5
--      também divergem em D (ALERTA), por tabela.
--   4. MELHORIA A3 - AP (CHECK_FORA_DE_LINHA): FORA_DE_LINHA passa a vir do
--      registro MAIS RECENTE em que o SKU aparece, e não da linha do mês
--      corrente. 71 SKUs que estavam fora de linha e NÃO alertavam passam a
--      alertar (de 1 para 72). D (ALERTA) diverge nesses 71, por tabela.
--      Ver int_venda_mensal_pivot.
--   5. MELHORIA A4 - AV, CL, DB: o percentual dentro do texto do alerta ganha
--      uma casa decimal e vírgula ("5,5%") no lugar do inteiro de dois dígitos
--      que o Excel pt-BR imprime ("05%"). 2.180 células de texto, e D (ALERTA)
--      por tabela em todas elas. É melhoria de LEITURA: nenhum número de
--      cálculo muda. Ver macros/compras_texto_percentual.sql.
--   6. MELHORIA D1 - AQ (VD_ANT_3M): passa a herdar da sucessão com PESO_1 E
--      PESO_2, como as colunas irmãs AD/AE/AF e AG; a planilha só escreveu o
--      primeiro termo. Impacto MEDIDO hoje: ZERO células (nenhuma linha de
--      seed_sucessao tem ANTIGO_2, e todas estão ATIVO='NAO'). AR e AT, que
--      derivam de AQ, também não mudam hoje.
--
-- E o que este model continua NÃO consertando, de propósito:
--   - BQ (CRED_ICMS) lê o crédito EMPÍRICO (DR), não a tabela dCredito (BO).
--     Decidido em 21/08/2026 como INTENCIONAL (PENDENCIAS item 2, PDF §8.5): o
--     Winthor não expõe a tributação de entrada/saída por item, e a diferença
--     custo x valor é o proxy que alimenta o cálculo real. Nada a mudar.
--   - PENDENCIAS_DIRETORIA.md item 5 (PEDIDO_UNIDADES com fator corrente x
--     congelado) continua ABERTO e reproduzido como a planilha faz. Enquanto
--     houver item aberto ali, ele é citado em toda entrega.
--
-- ── O que muda entre dois builds sem nada ter mudado no dado ───────────────
-- Três famílias de coluna, e a distinção importa na hora de ler o relatório do
-- validador (CONTEXTO.md §6.1.1 e §6.3):
--   VOLÁTEIS - Q/T/U/V/W, AM/AN, AC, AP e o que delas deriva: leem estoque ao
--     vivo e o mês corrente. Divergir contra a foto da planilha é esperado.
--   DECISÃO HUMANA - BA (PEDIDO), CN/DD (margem alvo), CU/DI (preço final) e
--     o fecho delas, incluindo X e Y. Vêm das APP_* por left join, hoje
--     vazias. Nulo aqui é o estado CORRETO, não dado faltando - e nunca é
--     preenchido com uma sugestão calculada (CONTEXTO.md regra 10).
--   ESTRUTURAIS - todo o resto. Divergência aqui é defeito de verdade.
-- ─────────────────────────────────────────────────────────────────────────────

with base as (
    select * from {{ ref('int_produto_base') }}
),

demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

classe_abc as (
    select * from {{ ref('int_produto_classe_abc') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

custo as (
    select * from {{ ref('int_produto_custo') }}
),

margem as (
    select * from {{ ref('int_produto_margem') }}
),

preco_sugerido as (
    select * from {{ ref('int_produto_preco_sugerido') }}
),

pedido as (
    select * from {{ ref('int_produto_pedido') }}
),

sucessao as (
    select * from {{ ref('int_produto_sucessao') }}
),

alerta as (
    select * from {{ ref('int_produto_alerta') }}
),

-- Dez models, dez INNER JOIN por `codigo`. Inner e nao left de proposito: os
-- dez tem a mesma espinha (int_produto_base) e o mesmo grao, entao um left
-- join esconderia uma quebra de grao a montante em vez de derruba-la aqui.
-- `tests/compras_fat_pedido_grao_unico.sql` fecha o cerco pelo outro lado.
final as (
    select
        b.codigo,                                   -- A  | CODIGO
        b.cod_fab,                                  -- B  | COD_FAB
        b.descricao,                                -- C  | DESCRICAO
        al.alerta,                                  -- D  | ALERTA
        b.status,                                   -- E  | STATUS
        b.fornecedor,                               -- F  | FORNECEDOR
        b.comprador,                                -- G  | COMPRADOR
        b.embalagem,                                -- H  | EMBALAGEM
        cast(null as varchar2(1)) as nao_usado,     -- I  | (nao usado)
        b.embal_compra,                             -- J  | EMBAL_COMPRA
        b.fator_exibicao,                           -- K  | FATOR_EXIBICAO
        b.l_por_unidade,                            -- L  | L_POR_UNIDADE
        b.peso_unitario_kg,                         -- M  | PESO_UNITARIO_KG
        b.qt_palete,                                -- N  | QT_PALETE
        ma.nivel_base_margem,                       -- O  | NIVEL_BASE_MARGEM
        ma.nivel_margem,                            -- P  | NIVEL_MARGEM
        d.est_disp,                                 -- Q  | EST_DISP
        d.qt_bloqueada,                             -- R  | QT_BLOQUEADA
        d.qt_avaria,                                -- S  | QT_AVARIA
        d.qt_reservada,                             -- T  | QT_RESERVADA
        d.pendente,                                 -- U  | PENDENTE
        d.est_pend,                                 -- V  | EST+PEND
        d.est_fabrica,                              -- W  | EST_FABRICA
        al.check_fabrica,                           -- X  | CHECK_FABRICA
        al.check_inativo,                           -- Y  | CHECK_INATIVO
        d.dt_ult_ent,                               -- Z  | DT_ULT_ENT
        d.qt_ult_ent,                               -- AA | QT_ULT_ENT
        d.n_meses,                                  -- AB | N_MESES
        d.vd_mes_atual,                             -- AC | VD MES ATUAL
        d.vd_m1 as vd_m_1,                          -- AD | VD M-1
        d.vd_m2 as vd_m_2,                          -- AE | VD M-2
        d.vd_m3 as vd_m_3,                          -- AF | VD M-3
        d.media_janela,                             -- AG | MEDIA_JANELA
        d.media_l,                                  -- AH | MEDIA_L
        d.qt_cli_atacado,                           -- AI | QT_CLI_ATACADO
        d.qt_cli_varejo,                            -- AJ | QT_CLI_VAREJO
        d.dias_sem_estoque,                         -- AK | DIAS_SEM_ESTOQUE
        al.check_ruptura,                           -- AL | CHECK_RUPTURA
        d.dt_ult_saida,                             -- AM | DT_ULT_SAIDA
        d.dias_sem_venda,                           -- AN | DIAS_SEM_VENDA
        al.check_estoque_parado,                    -- AO | CHECK_ESTOQUE_PARADO
        al.check_fora_de_linha,                     -- AP | CHECK_FORA_DE_LINHA
        d.vd_ant_3m,                                -- AQ | VD_ANT_3M
        d.tend_perc as tend_pct,                    -- AR | TEND %
        d.tend,                                     -- AS | TEND
        d.var_pv,                                   -- AT | VAR_PV
        d.tx_devolucao_3m,                          -- AU | TX_DEVOLUCAO_3M
        al.check_devolucao_alta,                    -- AV | CHECK_DEVOLUCAO_ALTA
        d.meses_est,                                -- AW | MESES_EST
        cl.classe,                                  -- AX | CLASSE
        al.check_litragem,                          -- AY | CHECK_LITRAGEM
        d.sug_cobertura,                            -- AZ | SUG_COBERTURA
        pe.pedido,                                  -- BA | PEDIDO
        pe.pedido_unidades,                         -- BB | PEDIDO_UNIDADES
        pe.pedido_na_medida,                        -- BC | PEDIDO_NA_MEDIDA
        pe.valor_pedido,                            -- BD | VALOR_PEDIDO
        pe.sug_palete,                              -- BE | SUG_PALETE
        pe.meses_est_ped,                           -- BF | MESES_EST+PED
        pe.valor_estoque,                           -- BG | VALOR_ESTOQUE
        fi.vl_ent_unit,                             -- BH | VL_ENT_UNIT
        fi.custo_ult_ent,                           -- BI | CUSTO_ULT_ENT
        fi.cod_icms,                                -- BJ | COD_ICMS
        fi.cod_piscof,                              -- BK | COD_PISCOF
        fi.modalidade,                              -- BL | MODALIDADE
        fi.mva,                                     -- BM | MVA
        fi.uf_origem,                               -- BN | UF_ORIGEM
        fi.cred_total,                              -- BO | CRED_TOTAL
        fi.aliq_icms_origem,                        -- BP | ALIQ_ICMS_ORIGEM
        fi.cred_icms,                               -- BQ | CRED_ICMS
        fi.cred_piscof,                             -- BR | CRED_PISCOF
        fi.check_importado,                         -- BS | CHECK_IMPORTADO
        cu.icms_st_s_valor,                         -- BT | ICMS_ST_s/VALOR
        cu.icms_st_s_custo,                         -- BU | ICMS_ST_s/CUSTO
        cu.custo_tot_s_valor,                       -- BV | CUSTO_TOT_s/VALOR
        cu.custo_tot_oficial,                       -- BW | CUSTO_TOT_OFICIAL
        cu.custo_adicional_imagem,                  -- BX | CUSTO_ADICIONAL_IMAGEM
        cu.custo_tot_gerencial,                     -- BY | CUSTO_TOT_GERENCIAL
        fi.piscof_ef,                               -- BZ | PISCOF_EF
        fi.icms_saida_ef,                           -- CA | ICMS_SAIDA_EF
        fi.icms_sem_red,                            -- CB | ICMS_SEM_RED
        al.check_trib,                              -- CC | CHECK_TRIB
        al.check_mva,                               -- CD | CHECK_MVA
        al.check_custo,                             -- CE | CHECK_CUSTO
        ma.pv_atacado,                              -- CF | PV_ATACADO
        ma.mkp_atacado,                             -- CG | MKP_ATACADO
        ma.margem_st_s_valor,                       -- CH | MARGEM_ST_s/VALOR
        ma.margem_oficial,                          -- CI | MARGEM_OFICIAL
        ma.margem_sem_red,                          -- CJ | MARGEM_SEM_RED
        ma.gap_filial_pp,                           -- CK | GAP_FILIAL_pp
        al.check_margem_instavel,                   -- CL | CHECK_MARGEM_INSTAVEL
        ma.dif_mc_pp,                               -- CM | DIF_MC_pp
        pr.margem_alvo,                             -- CN | MARGEM_ALVO
        pr.pv_sug_st_s_valor_av,                    -- CO | PV_SUG_ST_s/VALOR_AV
        pr.pv_sug_st_s_valor_ap,                    -- CP | PV_SUG_ST_s/VALOR_AP
        pr.pv_sug_oficial_av,                       -- CQ | PV_SUG_OFICIAL_AV
        pr.pv_sug_oficial_ap,                       -- CR | PV_SUG_OFICIAL_AP
        pr.pv_sug_sem_red_av,                       -- CS | PV_SUG_SEM_RED_AV
        pr.pv_sug_sem_red_ap,                       -- CT | PV_SUG_SEM_RED_AP
        pr.alt_pv_at_av,                            -- CU | ALT_PV_AT_AV
        pr.alt_pv_at_ap,                            -- CV | ALT_PV_AT_AP
        ma.pv_varejo,                               -- CW | PV_VAREJO
        ma.mkp_varejo,                              -- CX | MKP_VAREJO
        ma.margem_st_s_valor_varejo,                -- CY | MARGEM_ST_s/VALOR_VAREJO
        ma.margem_sem_red_varejo,                   -- CZ | MARGEM_SEM_RED_VAREJO
        ma.gap_filial_varejo_pp,                    -- DA | GAP_FILIAL_VAREJO_pp
        al.check_margem_instavel_varejo,            -- DB | CHECK_MARGEM_INSTAVEL_VAREJO
        ma.dif_mc_varejo_pp,                        -- DC | DIF_MC_VAREJO_pp
        pr.margem_alvo_varejo,                      -- DD | MARGEM_ALVO_VAREJO
        pr.pv_sug_st_s_valor_var_av,                -- DE | PV_SUG_ST_s/VALOR_VAR_AV
        pr.pv_sug_st_s_valor_var_ap,                -- DF | PV_SUG_ST_s/VALOR_VAR_AP
        pr.pv_sug_sem_red_var_av,                   -- DG | PV_SUG_SEM_RED_VAR_AV
        pr.pv_sug_sem_red_var_ap,                   -- DH | PV_SUG_SEM_RED_VAR_AP
        pr.alt_pv_var_av,                           -- DI | ALT_PV_VAR_AV
        pr.alt_pv_var_ap,                           -- DJ | ALT_PV_VAR_AP
        su.ant_1,                                   -- DK | ANT_1
        su.peso_1,                                  -- DL | PESO_1
        su.ant_2,                                   -- DM | ANT_2
        su.peso_2,                                  -- DN | PESO_2
        al.check_sucessao,                          -- DO | CHECK_SUCESSAO
        ma.nivel_base_margem_varejo,                -- DP | NIVEL_BASE_MARGEM_VAREJO
        ma.nivel_margem_varejo,                     -- DQ | NIVEL_MARGEM_VAREJO
        fi.cred_total_empirico                      -- DR | CRED_TOTAL_EMPIRICO
      from base           b
      join demanda        d  on d.codigo  = b.codigo
      join classe_abc     cl on cl.codigo = b.codigo
      join fiscal         fi on fi.codigo = b.codigo
      join custo          cu on cu.codigo = b.codigo
      join margem         ma on ma.codigo = b.codigo
      join preco_sugerido pr on pr.codigo = b.codigo
      join pedido         pe on pe.codigo = b.codigo
      join sucessao       su on su.codigo = b.codigo
      join alerta         al on al.codigo = b.codigo
)

select * from final
