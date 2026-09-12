with source as (
    select * from {{ source('compras_app', 'app_decisao_preco') }}
),

renamed as (
    select
        ID_PRODUTO          as id_produto,
        -- DUAS margens alvo, uma por canal, cada uma alimentando sua propria cadeia
        -- de preco sugerido (gabarito: CN = atacado, DD = varejo). Aplicar a do
        -- atacado no varejo erra em silencio todo SKU com margens diferentes.
        -- NULL = sem decisao humana; o padrao de 20% e aplicado no model, nao aqui.
        MARGEM_ALVO         as margem_alvo,
        MARGEM_ALVO_VAREJO  as margem_alvo_varejo,
        -- Preco final decidido, a vista. NUNCA preenchido automaticamente com uma
        -- das sugestoes calculadas (gabarito: CU e DI sao as unicas colunas de
        -- preco sem formula). A variacao a prazo e calculada a partir daqui.
        ALT_PV_AT_AV        as alt_pv_at_av,
        ALT_PV_VAR_AV       as alt_pv_var_av,
        ATUALIZADO_EM       as atualizado_em,
        ATUALIZADO_POR      as atualizado_por
    from source
)

select * from renamed
