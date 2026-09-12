with source as (
    select * from {{ source('cedep', 'pchistest') }}
),

renamed as (
    select
        CODPROD         as id_produto,
        CODFILIAL       as id_filial,
        DATA            as data,
        QTESTGER        as quantidade_gerencial
    from source
)

select * from renamed
