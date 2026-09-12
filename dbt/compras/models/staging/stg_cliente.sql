with source as (
    select * from {{ source('cedep', 'pcclient') }}
),

renamed as (
    select
        CODCLI          as id_cliente,
        CGCENT          as cnpj
    from source
)

select * from renamed
