with source as (
    select * from {{ source('cedep', 'pcdepto') }}
),

renamed as (
    select
        CODEPTO    as id_departamento,
        DESCRICAO  as descricao_departamento
    from source
)

select * from renamed
