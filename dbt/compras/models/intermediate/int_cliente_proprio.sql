-- ─────────────────────────────────────────────────────────────────────────────
-- Origem: CTE `clientes_proprios`, relatorios_compras/query_mensal.py
-- (conferido também contra app_relatorios/relatorios/compras_mensal.py).
--
-- "Clientes" que são a própria empresa: transferência entre filiais entra na
-- base como pedido de venda para um cliente cujo CNPJ é o de uma filial. Isso
-- não é faturamento. A detecção cruza a raiz do CNPJ (8 primeiros dígitos) de
-- pcclient com a de pcfilial - sem CNPJ fixo no código, filial nova entra
-- sozinha na lista.
--
-- Usado por int_faturamento_mensal (exclui da venda) e int_devolucao_mensal
-- (exclui retorno de transferência, que não é devolução de venda).
-- ─────────────────────────────────────────────────────────────────────────────

with cliente as (
    select * from {{ ref('stg_cliente') }}
),

filial as (
    select * from {{ ref('stg_filial') }}
),

final as (
    select c.id_cliente
      from cliente c
     where substr(replace(replace(replace(c.cnpj, '.', ''), '/', ''), '-', ''), 1, 8) in (
               select substr(replace(replace(replace(f.cnpj, '.', ''), '/', ''), '-', ''), 1, 8)
                 from filial f
                where f.cnpj is not null
           )
)

select * from final
