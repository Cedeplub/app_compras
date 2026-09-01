with source as (
    select * from {{ source('cedep', 'pcmovcomple') }}
),

renamed as (
    select
        NUMTRANSITEM       as id_transacao_item,
        VLSUBTOTITEM       as valor_subtotal_item,
        BONIFIC            as bonificacao,
        VLSTTRANSFCD       as valor_st_transferencia_cd,
        VLFECP             as valor_fecp,
        VLFECPTRANSFCD     as valor_fecp_transferencia_cd
    from source
)

select * from renamed
