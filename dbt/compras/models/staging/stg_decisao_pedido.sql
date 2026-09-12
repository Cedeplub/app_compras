with source as (
    select * from {{ source('compras_app', 'app_decisao_pedido') }}
),

renamed as (
    select
        ID_PRODUTO          as id_produto,
        -- Quantidade como o comprador digitou, na unidade de EXIBICAO.
        PEDIDO              as pedido,
        -- Fator de exibicao congelado no instante da decisao. unidades = pedido x
        -- fator. E snapshot de proposito: recalcular a partir do cadastro atual
        -- mudaria retroativamente o significado da decisao se o fornecedor virasse
        -- MASTER (gabarito K/BB, regra 6 do CONTEXTO).
        FATOR_EXIBICAO      as fator_exibicao,
        ATUALIZADO_EM       as atualizado_em,
        ATUALIZADO_POR      as atualizado_por
    from source
)

select * from renamed
