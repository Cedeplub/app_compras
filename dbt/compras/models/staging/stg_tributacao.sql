with source as (
    select * from {{ source('cedep', 'pctabtrib') }}
),

renamed as (
    select
        CODPROD              as id_produto,
        CODFILIALNF          as id_filial_nf,
        UFDESTINO            as uf_destino,
        CODST                as id_tributacao,
        CODTRIBPISCOFINS     as id_tributacao_piscofins
    from source
)

select * from renamed
