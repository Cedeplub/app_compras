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
        -- O MESMO custo, com o ICMS-ST retirado pelo proprio WinThor. Quando
        -- os dois diferem, o ST da nota ESTA dentro de CUSTOULTENT - e somar
        -- um ST calculado em cima contaria duas vezes (ver o bloco "ST JA
        -- EMBUTIDO" em int_produto_custo.sql). E' a fonte respondendo a
        -- pergunta, em vez de a gente inferir por data ou por razao de custo.
        CUSTOULTENTSEMST as custo_ultima_entrada_sem_st,
        VALORULTENT     as valor_ultima_entrada,
        QTGIRODIA       as giro_diario
    from source
)

select * from renamed
