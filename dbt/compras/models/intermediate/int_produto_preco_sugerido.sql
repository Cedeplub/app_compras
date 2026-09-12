-- ─────────────────────────────────────────────────────────────────────────────
-- int_produto_preco_sugerido — colunas CN a CV e DD a DJ da aba `pedido`.
-- A margem-alvo, os dez precos sugeridos e o campo de DECISAO HUMANA.
--
-- Gabarito: docs/gabarito_pedido_formulas.txt. Mapa coluna a coluna:
--   CN MARGEM_ALVO                 digitada (APP_DECISAO_PRECO), padrao 20%
--   CO PV_SUG_ST_s/VALOR_AV        ($BV2+$BX2) / (1-CB-BZ-comissao-CN)
--   CP PV_SUG_ST_s/VALOR_AP        $CO2 * FATOR_PRAZO
--   CQ PV_SUG_OFICIAL_AV           $BY2       / (1-CA-BZ-comissao-CN)
--   CR PV_SUG_OFICIAL_AP           $CQ2 * FATOR_PRAZO
--   CS PV_SUG_SEM_RED_AV           $BY2       / (1-CB-BZ-comissao-CN)
--   CT PV_SUG_SEM_RED_AP           $CS2 * FATOR_PRAZO
--   CU ALT_PV_AT_AV                DIGITADA - sem formula, fica NULA
--   CV ALT_PV_AT_AP                $CU2 * FATOR_PRAZO
--   DD MARGEM_ALVO_VAREJO          digitada, padrao 20% (INDEPENDENTE de CN)
--   DE PV_SUG_ST_s/VALOR_VAR_AV    ($BV2+$BX2) / (1-CB-BZ-comissao-DD)
--   DF PV_SUG_ST_s/VALOR_VAR_AP    $DE2 * FATOR_PRAZO_VAREJO
--   DG PV_SUG_SEM_RED_VAR_AV       $BY2       / (1-CB-BZ-comissao-DD)
--   DH PV_SUG_SEM_RED_VAR_AP       $DG2 * FATOR_PRAZO_VAREJO
--   DI ALT_PV_VAR_AV               DIGITADA - sem formula, fica NULA
--   DJ ALT_PV_VAR_AP               $DI2 * FATOR_PRAZO_VAREJO
--
-- Grao: 1 linha por SKU. Espinha = int_produto_custo (= o cadastro inteiro).
--
-- ── A formula: a de margem, invertida ──────────────────────────────────────
-- PDF 9.2. Partindo de margem = (PV - PV x (aliq+piscof+comissao) - custo)/PV
-- e resolvendo para PV com margem = MARGEM_ALVO:
--     pv_sug = custo / (1 - aliq_icms - piscof - comissao - margem_alvo)
-- Os cenarios sao os MESMOS de int_produto_margem, e diferem nas MESMAS duas
-- escolhas - qual aliquota e qual base de custo:
--     ST s/Valor  -> CB (cheia)       e ($BV2 + $BX2)
--     Oficial     -> CA (com reducao) e $BY2
--     Sem Reducao -> CB (cheia)       e $BY2
--
-- ── ⚠ DIVERGENCIA DELIBERADA DO ARQUIVO EM referencia/ (CO e DE) ───────────
-- Decidido pelo Diretor de Compras em 21/08/2026 (PENDENCIAS_DIRETORIA.md,
-- item 1; CONTEXTO.md 6.4). O cenario "ST s/Valor" usava $CA2 = ICMS_SAIDA_EF
-- (aliquota COM reducao de base). Era ERRO NA PLANILHA: substituicao
-- tributaria e beneficio de reducao de base sao mecanicas separadas. CO e DE
-- passam a usar $CB2 = ICMS_SEM_RED; CP e DF mudam por consequencia, sem
-- alteracao propria (derivam pelo fator de prazo). "Oficial" (CQ/CR) e "Sem
-- Reducao" (CS/CT, DG/DH) NAO mudam.
-- O xlsx em referencia/ e' a versao ANTERIOR a correcao: nestas 4 colunas o
-- modelo diverge dele DE PROPOSITO. Efeito medido: ~2.095 SKUs de preco
-- sugerido, todos de MODALIDADE = 'NORMAL' - nenhum item em regime ST muda,
-- porque para eles CA e CB ja eram identicas. Fora do ST, CO passa a ser
-- identica a CS e DE identica a DG.
-- Seis precos no atacado (3 cenarios x a vista/a prazo) e QUATRO no varejo:
-- nao existe "Oficial" no varejo porque a reducao de base nao se aplica a ele
-- (PDF 8.2 / 9.4, CONTEXTO.md regra 3). O ajuste Ingrax ($BX2) entra em todos
-- os dez, via BY ou somado a BV - e' custo gerencial, e preco se decide sobre
-- custo gerencial (PDF 8.4).
--
-- ── Dois fatores de prazo, dois parametros ─────────────────────────────────
-- a prazo = a vista x fator. Atacado 1,0317 (Parametros!$B$5); varejo
-- 1,086435, que na planilha esta CHUMBADO dentro das formulas DF/DH/DJ.
-- CONTEXTO.md 6.1: aqui ele mora no seed como FATOR_PRAZO_VAREJO. Mesmo
-- numero, so' muda onde a constante vive - o aceite celula a celula continua
-- fechando. Aplicar o fator do atacado no varejo (ou vice-versa) erraria ~5,3%
-- em todo preco a prazo, em silencio.
--
-- ── DUAS margens-alvo, independentes ───────────────────────────────────────
-- CN alimenta CO/CQ/CS; DD alimenta DE/DG. Sao colunas digitadas SEPARADAS na
-- planilha, e vem separadas de APP_DECISAO_PRECO. Usar CN nos dois lados
-- erraria todo SKU cujo Diretor tenha decidido metas diferentes por canal -
-- exatamente o caso de uso da coluna. O padrao de 20% (MARGEM_ALVO_PADRAO, do
-- int_parametro) e' aplicado AQUI, nao na tabela APP_*: linha ausente e
-- MARGEM_ALVO nula significam a mesma coisa, "sem decisao humana".
--
-- ── ⚠ ALT_PV_AT_AV e ALT_PV_VAR_AV: o ponto de decisao HUMANA ─────────────
-- PDF 9.3 e CONTEXTO.md regra 10. CU e DI sao as UNICAS colunas de preco sem
-- formula na planilha inteira: o Diretor de Compras olha os seis (ou quatro)
-- precos sugeridos e DIGITA o preco que de fato vai para a equipe comercial -
-- podendo arredondar ou divergir de todas as sugestoes. Elas vem de
-- APP_DECISAO_PRECO por LEFT JOIN e ficam NULAS enquanto nao houver decisao.
-- NUNCA, em nenhuma condicao, preencher com uma das sugestoes calculadas:
-- isso apagaria a distincao entre "a maquina sugere" e "a pessoa decidiu", que
-- e' o unico ponto do modelo onde alguem responde pelo numero. Hoje
-- APP_DECISAO_PRECO esta vazia e as duas colunas saem 100% nulas - e' o
-- estado correto, nao um dado faltando.
-- CV e DJ derivam do valor DIGITADO (`IF($CU2="","",...)`), entao tambem ficam
-- nulas enquanto CU/DI estiverem nulas. Nao ha "preco a prazo sem preco a
-- vista".
--
-- ── O "" do Excel e a divisao pelo denominador ─────────────────────────────
-- Cada preco a vista e' `IF(OR(<custo>="",<aliquota>="",$BZ2=""),"",
-- IFERROR(<custo>/<denominador>,""))`. Duas camadas, com papeis diferentes:
--   o IF externo apaga o preco quando falta insumo (mesmas portas das margens
--     - ver int_produto_margem; note que CO testa BW E BV, e CQ/CS testam so'
--     BW, exatamente como no gabarito);
--   o IFERROR interno cobre UMA coisa so': denominador = 0 (aliquotas +
--     comissao + margem alvo somando exatamente 1). Denominador NEGATIVO nao
--     e' erro no Excel - devolve preco negativo, e e' assim que ele sinaliza
--     "essa margem-alvo e' inalcancavel com essa carga tributaria". Por isso
--     aqui e' `nullif(denominador, 0)` e NAO um `case when denominador <= 0`:
--     o segundo apagaria uma informacao que a planilha mostra.
-- Os `* fator` a prazo tambem tem IFERROR na planilha, que so' existe para o
-- caso "a vista vazio" (""*1,0317 = #VALOR!). Em Oracle, NULL * x ja e' NULL.
-- ─────────────────────────────────────────────────────────────────────────────

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

-- O dbt LE as APP_* e nunca escreve nelas (CONTEXTO.md secao 2). Consequencia
-- que precisa estar clara: decisao gravada no dashboard so' aparece aqui
-- depois do proximo `dbt run`.
decisao as (
    select * from {{ ref('stg_decisao_preco') }}
),

parametro as (
    select * from {{ ref('int_parametro') }}
),

-- CN e DD resolvidos antes: as duas margens-alvo entram em cinco denominadores
-- diferentes, e o fallback de 20% tem que ser o mesmo em todos eles.
entrada as (
    select
        c.codigo,
        c.custo_tot_s_valor,                               -- BV
        c.custo_tot_oficial,                               -- BW
        c.custo_adicional_imagem,                          -- BX
        c.custo_tot_gerencial,                             -- BY
        f.icms_saida_ef,                                   -- CA (com reducao)
        f.icms_sem_red,                                    -- CB (cheia)
        f.piscof_ef,                                       -- BZ
        -- CN / DD: left join + nvl. Linha ausente e valor nulo significam a
        -- mesma coisa - "sem decisao humana" -, e as duas caem no padrao.
        nvl(d.margem_alvo,        par.margem_alvo_padrao)  as margem_alvo,
        nvl(d.margem_alvo_varejo, par.margem_alvo_padrao)  as margem_alvo_varejo,
        -- CU / DI: SEM nvl, SEM fallback, SEM sugestao no lugar. Nulo aqui e'
        -- a informacao "ninguem decidiu ainda" - ver cabecalho.
        d.alt_pv_at_av,
        d.alt_pv_var_av,
        par.comissao,
        par.fator_prazo,
        par.fator_prazo_varejo
      from custo c
      join fiscal f
        on f.codigo = c.codigo
      left join decisao d
        on d.id_produto = c.codigo
     cross join parametro par
),

-- Os cinco precos A VISTA. Os cinco a prazo saem deles por multiplicacao, na
-- CTE seguinte - se fossem calculados de novo a partir do custo, um ajuste
-- futuro poderia deixar o par a vista/a prazo incoerente.
a_vista as (
    select
        e.*,
        -- CO | atacado, ST s/Valor: aliquota CHEIA (correcao do Diretor de
        -- 21/08/2026 - ver cabecalho; era ICMS_SAIDA_EF), custo s/valor MAIS o
        -- ajuste Ingrax
        case when e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
              and e.custo_tot_s_valor is not null
             then (e.custo_tot_s_valor + e.custo_adicional_imagem)
                  / nullif(1 - e.icms_sem_red - e.piscof_ef
                             - e.comissao - e.margem_alvo, 0)
        end                                                as pv_sug_st_s_valor_av,
        -- CQ | atacado, Oficial: aliquota com reducao, custo gerencial
        case when e.custo_tot_oficial is not null
              and e.icms_saida_ef     is not null
              and e.piscof_ef         is not null
             then e.custo_tot_gerencial
                  / nullif(1 - e.icms_saida_ef - e.piscof_ef
                             - e.comissao - e.margem_alvo, 0)
        end                                                as pv_sug_oficial_av,
        -- CS | atacado, Sem Reducao: aliquota cheia, custo gerencial
        case when e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
             then e.custo_tot_gerencial
                  / nullif(1 - e.icms_sem_red - e.piscof_ef
                             - e.comissao - e.margem_alvo, 0)
        end                                                as pv_sug_sem_red_av,
        -- DE | varejo, ST s/Valor - aliquota CHEIA (correcao do Diretor de
        -- 21/08/2026 - ver cabecalho; era ICMS_SAIDA_EF) e MARGEM_ALVO_VAREJO
        -- no denominador
        case when e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
              and e.custo_tot_s_valor is not null
             then (e.custo_tot_s_valor + e.custo_adicional_imagem)
                  / nullif(1 - e.icms_sem_red - e.piscof_ef
                             - e.comissao - e.margem_alvo_varejo, 0)
        end                                                as pv_sug_st_s_valor_var_av,
        -- DG | varejo, Sem Reducao - o cenario que o varejo de fato paga
        case when e.custo_tot_oficial is not null
              and e.icms_sem_red      is not null
              and e.piscof_ef         is not null
             then e.custo_tot_gerencial
                  / nullif(1 - e.icms_sem_red - e.piscof_ef
                             - e.comissao - e.margem_alvo_varejo, 0)
        end                                                as pv_sug_sem_red_var_av
      from entrada e
),

final as (
    select
        v.codigo,
        v.margem_alvo,
        v.pv_sug_st_s_valor_av,
        v.pv_sug_st_s_valor_av * v.fator_prazo             as pv_sug_st_s_valor_ap,  -- CP
        v.pv_sug_oficial_av,
        v.pv_sug_oficial_av    * v.fator_prazo             as pv_sug_oficial_ap,     -- CR
        v.pv_sug_sem_red_av,
        v.pv_sug_sem_red_av    * v.fator_prazo             as pv_sug_sem_red_ap,     -- CT
        -- CU: decisao humana. Nulo enquanto ninguem decidir.
        v.alt_pv_at_av,
        -- CV: derivada do valor DIGITADO, nunca de uma sugestao
        v.alt_pv_at_av         * v.fator_prazo             as alt_pv_at_ap,
        v.margem_alvo_varejo,
        v.pv_sug_st_s_valor_var_av,
        -- DF/DH/DJ: FATOR_PRAZO_VAREJO, o parametro - nao 1,086435 chumbado
        v.pv_sug_st_s_valor_var_av * v.fator_prazo_varejo  as pv_sug_st_s_valor_var_ap,
        v.pv_sug_sem_red_var_av,
        v.pv_sug_sem_red_var_av    * v.fator_prazo_varejo  as pv_sug_sem_red_var_ap,
        -- DI: a segunda decisao humana
        v.alt_pv_var_av,
        v.alt_pv_var_av            * v.fator_prazo_varejo  as alt_pv_var_ap
      from a_vista v
)

select * from final
