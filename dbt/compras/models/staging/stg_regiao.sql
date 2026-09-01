with source as (
    select * from {{ source('cedep', 'pcregiao') }}
),

renamed as (
    select
        NUMREGIAO       as id_regiao,
        -- A região vem do PEDIDO (pcpedc.numregiao); pcclient.numregiaocli está incorreto na base
        REGIAO          as nome_regiao
    from source
)

select * from renamed
