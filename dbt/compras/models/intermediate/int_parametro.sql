-- ─────────────────────────────────────────────────────────────────────────────
-- int_parametro — a aba `Parametros` da planilha v10, PIVOTADA em UMA linha.
--
-- Qual coluna Excel reproduz: nenhuma da aba `pedido` diretamente. Reproduz a
-- aba `Parametros!$B$n` que as formulas do `pedido` citam por endereco de
-- celula - Parametros!$B$2 (PIS/COFINS), $B$4 (COMISSAO), $B$5 (FATOR_PRAZO),
-- $B$10 (CORTE_ABC), $B$13/$B$14 (codigos de tributacao padrao), $B$16
-- (ALIQ_ICMS_INTERNA_BA), $B$17 (DIAS_SEM_ESTOQUE_ALERTA), $B$18
-- (TX_DEVOLUCAO_ALERTA), $B$19 (MEDIDA_PEDIDO), $B$20 (PALETE_LIMIAR),
-- $B$21/$B$22 (limiares de margem), $B$29 (PERC_NF_NORMAL_INGRAX).
--
-- POR QUE UMA LINHA SO': para que todo model de calculo faca `cross join
-- parametro` e leia a constante por NOME. Constante magica dentro de SQL e
-- defeito neste projeto - o proprio "Leia-me" da planilha registra em qual
-- formula cada numero estava chumbado, e a coluna OBS do seed preserva esse
-- registro. Grao: 1 linha, sempre (agregacao sem group by).
--
-- ⚠️ SO' ENTRAM OS PARAMETROS COM ATIVO = 'S'. Os 7 com ATIVO = 'N'
-- (MES_REF_ULT_FECHADO, ICMS_ST, DESC_INTERNO, FATOR_ST_TABELA,
-- FATOR_ST_CUSTO, MULT_ST_NF, COBERTURA_ALVO_MESES) estao no seed como
-- REGISTRO HISTORICO - a propria planilha declara que nao tem efeito nenhum,
-- e varios sao duplicata desatualizada de um parametro vivo (ICMS_ST duplica
-- ALIQ_ICMS_INTERNA_BA; COBERTURA_ALVO_MESES foi substituido pela coluna
-- COBERTURA_ALVO do seed_fornecedor, que e por fornecedor). Usar um deles em
-- calculo e erro. O filtro `where ATIVO = 'S'` e a garantia estrutural: um
-- parametro desativado nem sequer VIRA coluna aqui, entao um model que tentar
-- usa-lo quebra no compile, alto, em vez de calcular preco errado em silencio.
--
-- Consequencia direta: se algum dia um parametro for desativado no CSV, o
-- proximo build deste model devolve NULL naquela coluna. `tests/
-- compras_parametro_completo.sql` reprova nesse caso, em vez de deixar o NULL
-- se propagar (em Oracle, `custo / (1 - null)` = NULL, nao erro).
-- ─────────────────────────────────────────────────────────────────────────────

with parametro as (
    select * from {{ ref('seed_parametros') }}
),

ativo as (
    select
        PARAMETRO as parametro,
        VALOR     as valor
      from parametro
     where ATIVO = 'S'
),

final as (
    select
        -- margem/preco: os tres somatorios de aliquota das formulas de margem
        -- e de PV sugerido (Parametros!$B$2 e $B$4)
        {{ compras_parametro_num('PIS_COFINS') }}                as pis_cofins,
        {{ compras_parametro_num('COMISSAO') }}                  as comissao,

        -- fator "a prazo": a vista x fator (Parametros!$B$5 no atacado). O do
        -- varejo estava CHUMBADO na formula (1,086435) - CONTEXTO 6.1: mesmo
        -- numero, so muda onde a constante mora.
        {{ compras_parametro_num('FATOR_PRAZO') }}               as fator_prazo,
        {{ compras_parametro_num('FATOR_PRAZO_VAREJO') }}        as fator_prazo_varejo,

        -- curva ABC (AX): participacao acima disso e classe 'A' (Parametros!$B$10)
        {{ compras_parametro_num('CORTE_ABC') }}                 as corte_abc,

        -- fallback de tributacao quando o produto ainda nao esta na 8105
        -- (BJ/BK, Parametros!$B$13 e $B$14)
        {{ compras_parametro_num('COD_TRIB_ICMS_PADRAO') }}      as cod_trib_icms_padrao,
        {{ compras_parametro_num('COD_TRIB_PISCOFINS_PADRAO') }} as cod_trib_piscofins_padrao,

        -- base do ICMS-ST: custo x (1 + MVA) x aliquota interna (Parametros!$B$16)
        {{ compras_parametro_num('ALIQ_ICMS_INTERNA_BA') }}      as aliq_icms_interna_ba,

        -- Ingrax 80/20: % do valor que vem na NF normal (Parametros!$B$29)
        {{ compras_parametro_num('PERC_NF_NORMAL_INGRAX') }}     as perc_nf_normal_ingrax,

        -- limiares de alerta
        {{ compras_parametro_num('DIAS_SEM_ESTOQUE_ALERTA') }}   as dias_sem_estoque_alerta,
        {{ compras_parametro_num('TX_DEVOLUCAO_ALERTA') }}       as tx_devolucao_alerta,
        {{ compras_parametro_num('DIAS_ESTOQUE_PARADO') }}       as dias_estoque_parado,
        {{ compras_parametro_num('TEND_LIMIAR') }}               as tend_limiar,
        {{ compras_parametro_num('MARGEM_ALERTA_MIN') }}         as margem_alerta_min,
        {{ compras_parametro_num('MARGEM_CRITICA_MIN') }}        as margem_critica_min,
        {{ compras_parametro_num('CRED_IMPORTADO_LIMIAR') }}     as cred_importado_limiar,
        {{ compras_parametro_num('PALETE_LIMIAR') }}             as palete_limiar,

        -- limiares dos DOIS alertas NOVOS de fat_alerta (02/09/2026). Nao tem
        -- coluna na planilha - nascem da taxonomia decidida pelo Diretor de
        -- Compras (v2/DECISOES_DIRETOR.md item 1). Moram aqui pela mesma regra
        -- de sempre: constante em formula e defeito.
        {{ compras_parametro_num('OPORTUNIDADE_GIRO_MESES') }}   as oportunidade_giro_meses,
        {{ compras_parametro_num('MARGEM_ALTA_MIN') }}           as margem_alta_min,
        {{ compras_parametro_num('MARGEM_ALTA_MIN_VAREJO') }}    as margem_alta_min_varejo,

        -- fallbacks de departamento sem linha no seed_fornecedor (AB e AZ)
        {{ compras_parametro_num('N_MESES_PADRAO') }}            as n_meses_padrao,
        {{ compras_parametro_num('COBERTURA_ALVO_PADRAO') }}     as cobertura_alvo_padrao,

        -- decisao humana ausente em APP_DECISAO_PRECO (CN/DD)
        {{ compras_parametro_num('MARGEM_ALVO_PADRAO') }}        as margem_alvo_padrao,

        -- limiar visual de cobertura: a tela pinta de vermelho quando a
        -- cobertura cai abaixo de COBERTURA_ALVO x esta fracao. No prototipo
        -- .jsx era o literal 0,6 repetido em 3 lugares (PROTOTIPO.md 5/9).
        {{ compras_parametro_num('COBERTURA_CRITICA_FRACAO') }} as cobertura_critica_fracao,

        -- UNICO parametro de texto: 'LITROS' | 'PESO' | qualquer outro valor
        -- cai no ramo UNIDADE_MASTER da coluna BC (Parametros!$B$19)
        {{ compras_parametro_txt('MEDIDA_PEDIDO') }}             as medida_pedido
      from ativo
)

select * from final
