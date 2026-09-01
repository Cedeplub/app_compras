with source as (
    select * from {{ source('cedep', 'pcnfent') }}
),

renamed as (
    select
        NUMTRANSENT         as id_transacao_entrada,
        -- ATENCAO: em nota de entrada por DEVOLUCAO DE CLIENTE (tipodescarga 6/7/T),
        -- CODFORNEC guarda o CODCLI do CLIENTE que devolveu - nao um fornecedor.
        -- Medido em 2026: das 5.241 notas de devolucao, 5.241 (100%) casam com
        -- PCCLIENT.CODCLI e 1.779 (34%) casam TAMBEM com PCFORNEC.CODFORNEC, por
        -- coincidencia numerica de codigo. Um join com stg_fornecedor "funciona" em
        -- um terco das linhas e joga devolucao em fornecedor aleatorio.
        -- Por isso o nome aqui e id_cliente_devolucao, e nao id_fornecedor:
        -- query_mensal.py apelida esta coluna AS id_cliente e a compara contra
        -- clientes_proprios, que sai de PCCLIENT.
        CODFORNEC           as id_cliente_devolucao,
        CODFILIAL           as id_filial,
        DTENT               as data_entrada,
        DTCANCEL            as data_cancelamento,
        TIPODESCARGA        as tipo_descarga,
        CODFISCAL           as codigo_fiscal,
        TIPOMOVGARANTIA     as tipo_movimento_garantia,
        OBS                 as observacao
    from source
)

select * from renamed
