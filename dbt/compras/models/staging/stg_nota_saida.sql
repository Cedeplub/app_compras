with source as (
    select * from {{ source('cedep', 'pcnfsaid') }}
),

renamed as (
    select
        NUMTRANSVENDA       as id_transacao_venda,
        CODFILIAL           as id_filial,
        CONDVENDA           as condicao_venda,
        TIPOVENDA           as tipo_venda,
        CODFISCAL           as codigo_fiscal,
        DTSAIDA             as data_saida,
        DTCANCEL            as data_cancelamento
    from source
)

select * from renamed
