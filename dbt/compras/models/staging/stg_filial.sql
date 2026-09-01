with source as (
    select * from {{ source('cedep', 'pcfilial') }}
),

renamed as (
    select
        CODIGO      as id_filial,
        CGC         as cnpj
    from source
)

select * from renamed
