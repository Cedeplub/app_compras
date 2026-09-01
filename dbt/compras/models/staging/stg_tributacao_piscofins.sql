with source as (
    select * from {{ source('cedep', 'pctribpiscofins') }}
),

renamed as (
    select
        CODTRIBPISCOFINS              as id_tributacao_piscofins,
        DESCRICAOTRIBPISCOFINS        as descricao_tributacao_piscofins
    from source
)

select * from renamed
