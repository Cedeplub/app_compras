with source as (
    select * from {{ source('cedep', 'pcmov') }}
),

renamed as (
    select
        NUMTRANSVENDA       as id_transacao_venda,
        NUMTRANSITEM        as id_transacao_item,
        NUMTRANSENT         as id_transacao_entrada,
        CODPROD             as id_produto,
        CODCLI              as id_cliente,
        CODFILIAL           as id_filial,
        NUMREGIAO           as id_regiao,
        QT                  as quantidade,
        -- Quantidade contratada, usada quando condvenda = 7 (venda futura)
        QTCONT              as quantidade_contratada,
        PUNIT               as preco_unitario,
        PUNITCONT           as preco_unitario_contratado,
        VLFRETE             as valor_frete,
        VLOUTRASDESP        as valor_outras_despesas,
        VLFRETE_RATEIO      as valor_frete_rateio,
        VLOUTROS            as valor_outros,
        VLREPASSE           as valor_repasse,
        ST                  as valor_st,
        CUSTOFIN            as custo_financeiro,
        DTMOV               as data_movimento,
        DTCANCEL            as data_cancelamento,
        CODOPER             as codigo_operacao,
        TIPOMERC            as tipo_mercadoria
    from source
)

select * from renamed
