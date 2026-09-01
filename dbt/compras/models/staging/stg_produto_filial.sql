with source as (
    select * from {{ source('cedep', 'pcprodfilial') }}
),

renamed as (
    select
        CODPROD       as id_produto,
        CODFILIAL     as id_filial,
        QTTOTPAL      as quantidade_palete
    from source
)

select * from renamed
