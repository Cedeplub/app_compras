with source as (
    select * from {{ source('cedep', 'pcsecao') }}
),

renamed as (
    select
        CODSEC       as id_secao,
        DESCRICAO    as descricao_secao,
        CODEPTO      as id_departamento
    from source
)

select * from renamed
