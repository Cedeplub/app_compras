with source as (
    select * from {{ source('cedep', 'pcestcom') }}
),

renamed as (
    select
        NUMTRANSENT         as id_transacao_entrada,
        NUMTRANSVENDA       as id_transacao_venda
    from source
)

select * from renamed
