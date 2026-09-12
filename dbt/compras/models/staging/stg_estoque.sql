with source as (
    select * from {{ source('cedep', 'pcest') }}
),

renamed as (
    select
        CODPROD         as id_produto,
        CODFILIAL       as id_filial,
        QTEST           as quantidade_estoque,
        QTESTGER        as quantidade_gerencial,
        QTPEDIDA        as quantidade_pedida,
        QTBLOQUEADA     as quantidade_bloqueada,
        -- É a quantidade de avaria; a "Qt. Bloqueada" do relatório é qtbloqueada - qtindeniz
        QTINDENIZ       as quantidade_avaria,
        QTRESERV        as quantidade_reservada,
        QTINDUSTRIA     as quantidade_industria,
        DTULTENT        as data_ultima_entrada,
        QTULTENT        as quantidade_ultima_entrada,
        DTULTSAIDA      as data_ultima_saida,
        CUSTOULTENT     as custo_ultima_entrada,
        VALORULTENT     as valor_ultima_entrada,
        QTGIRODIA       as giro_diario
    from source
)

select * from renamed
