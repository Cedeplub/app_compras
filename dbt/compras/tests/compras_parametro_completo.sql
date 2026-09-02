-- Previne: parâmetro desativado (ATIVO='N') ou renomeado no seed_parametros
-- fazer int_parametro devolver NULL naquela coluna, e o NULL se propagar em
-- silêncio. Em Oracle, `custo / (1 - null)` não dá erro: dá NULL, e a linha sai
-- da planilha sem preço em vez de reprovar o build. Também pega o caso oposto,
-- de o pivô devolver zero linhas (seed vazio) ou mais de uma.
--
-- Cada coluna aqui é citada por endereço de célula em alguma fórmula da aba
-- `pedido` (ver o cabeçalho de int_parametro.sql). Se um parâmetro deixar de
-- ser necessário, tire a coluna do model E daqui - não deixe o teste passar
-- por acaso.

with parametro as (
    select * from {{ ref('int_parametro') }}
),

contagem as (
    select count(*) as n_linhas from parametro
),

faltando as (
    select 'PIS_COFINS'                as parametro from parametro where pis_cofins                is null
    union all select 'COMISSAO'                     from parametro where comissao                  is null
    union all select 'FATOR_PRAZO'                  from parametro where fator_prazo               is null
    union all select 'FATOR_PRAZO_VAREJO'           from parametro where fator_prazo_varejo        is null
    union all select 'CORTE_ABC'                    from parametro where corte_abc                 is null
    union all select 'COD_TRIB_ICMS_PADRAO'         from parametro where cod_trib_icms_padrao      is null
    union all select 'COD_TRIB_PISCOFINS_PADRAO'    from parametro where cod_trib_piscofins_padrao is null
    union all select 'ALIQ_ICMS_INTERNA_BA'         from parametro where aliq_icms_interna_ba      is null
    union all select 'PERC_NF_NORMAL_INGRAX'        from parametro where perc_nf_normal_ingrax     is null
    union all select 'DIAS_SEM_ESTOQUE_ALERTA'      from parametro where dias_sem_estoque_alerta   is null
    union all select 'TX_DEVOLUCAO_ALERTA'          from parametro where tx_devolucao_alerta       is null
    union all select 'DIAS_ESTOQUE_PARADO'          from parametro where dias_estoque_parado       is null
    union all select 'TEND_LIMIAR'                  from parametro where tend_limiar               is null
    union all select 'MARGEM_ALERTA_MIN'            from parametro where margem_alerta_min         is null
    union all select 'MARGEM_CRITICA_MIN'           from parametro where margem_critica_min        is null
    union all select 'CRED_IMPORTADO_LIMIAR'        from parametro where cred_importado_limiar     is null
    union all select 'PALETE_LIMIAR'                from parametro where palete_limiar             is null
    union all select 'N_MESES_PADRAO'               from parametro where n_meses_padrao            is null
    union all select 'COBERTURA_ALVO_PADRAO'        from parametro where cobertura_alvo_padrao     is null
    union all select 'MARGEM_ALVO_PADRAO'           from parametro where margem_alvo_padrao        is null
    union all select 'MEDIDA_PEDIDO'                from parametro where medida_pedido             is null
    -- COBERTURA_CRITICA_FRACAO entrou em 01/09/2026 e nao foi listada aqui na
    -- epoca; incluida em 02/09/2026 junto com os tres limiares da taxonomia
    -- nova de alertas (OPORTUNIDADE_DE_GIRO e MARGEM_ALTA).
    union all select 'COBERTURA_CRITICA_FRACAO'      from parametro where cobertura_critica_fracao  is null
    union all select 'OPORTUNIDADE_GIRO_MESES'       from parametro where oportunidade_giro_meses   is null
    union all select 'MARGEM_ALTA_MIN'               from parametro where margem_alta_min           is null
    union all select 'MARGEM_ALTA_MIN_VAREJO'        from parametro where margem_alta_min_varejo    is null
    union all select 'GRAO: int_parametro tem que ter exatamente 1 linha'
                from contagem where n_linhas <> 1
)

select * from faltando
