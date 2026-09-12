with source as (
    select * from {{ source('cedep', 'pctabpr') }}
),

renamed as (
    select
        CODPROD       as id_produto,
        -- 1 = varejo, 2 = atacado
        NUMREGIAO     as id_regiao,
        PVENDA        as preco_venda
    from source
)

select * from renamed
