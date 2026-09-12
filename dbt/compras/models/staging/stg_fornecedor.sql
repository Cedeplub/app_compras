with source as (
    select * from {{ source('cedep', 'pcfornec') }}
),

renamed as (
    select
        CODFORNEC    as id_fornecedor,
        FORNECEDOR   as nome_fornecedor,
        -- Fornecedor legal da NF, não é o "FORNECEDOR" do modelo (que é o texto do departamento)
        ESTADO       as uf_origem
    from source
)

select * from renamed
