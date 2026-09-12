with source as (
    select * from {{ source('cedep', 'pctribut') }}
),

renamed as (
    select
        CODST      as id_tributacao,
        MENSAGEM   as descricao_tributacao
    from source
)

select * from renamed
