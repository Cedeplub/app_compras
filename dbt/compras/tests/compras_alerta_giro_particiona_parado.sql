-- Invariante que este teste previne: a divisão de PARADO em SEM_GIRO e
-- BAIXO_GIRO deixar de ser uma PARTIÇÃO - ou seja, um SKU parado cair nos DOIS
-- tipos, ou em NENHUM.
--
-- Por que isso é real e não teórico: a condição escrita em fat_alerta é
-- `media_janela = 0 and vd_mes_atual = 0` de um lado e o COMPLEMENTO
-- (`not (...)`) do outro. A tentação óbvia, na próxima manutenção, é escrever o
-- segundo ramo como `media_janela > 0 or vd_mes_atual > 0`, que PARECE o
-- complemento e não é: quantidade neste modelo é LÍQUIDA (faturado - devolvido,
-- CONTEXTO.md regra 1) e pode ser NEGATIVA. Medido em 02/09/2026: 1 SKU dos 460
-- em CHECK_ESTOQUE_PARADO tem venda líquida negativa e sumiria dos dois ramos -
-- um alerta de estoque parado desaparecendo em silêncio da tela do comprador.
--
-- Os três ramos:
--   1 - SKU com CHECK_ESTOQUE_PARADO ativo e nenhuma linha de giro
--   2 - SKU com as DUAS linhas (SEM_GIRO e BAIXO_GIRO) ao mesmo tempo
--   3 - linha de giro sem CHECK_ESTOQUE_PARADO por trás (alerta inventado)

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

giro as (
    select codigo, tipo_alerta
      from {{ ref('fat_alerta') }}
     where tipo_alerta in ('SEM_GIRO', 'BAIXO_GIRO')
),

por_sku as (
    select
        codigo,
        count(*)                                                     as qtd,
        sum(case when tipo_alerta = 'SEM_GIRO'   then 1 else 0 end)  as qtd_sem,
        sum(case when tipo_alerta = 'BAIXO_GIRO' then 1 else 0 end)  as qtd_baixo
      from giro
     group by codigo
),

divergencia as (
    -- ramo 1
    select p.codigo, 'PARADO SEM LINHA DE GIRO' as motivo, 0 as qtd
      from pedido p
     where p.check_estoque_parado is not null
       and not exists (select 1 from por_sku s where s.codigo = p.codigo)

    union all

    -- ramo 2
    select s.codigo, 'SEM_GIRO E BAIXO_GIRO NO MESMO SKU', s.qtd
      from por_sku s
     where s.qtd_sem > 0 and s.qtd_baixo > 0

    union all

    -- ramo 3
    select s.codigo, 'LINHA DE GIRO SEM CHECK_ESTOQUE_PARADO', s.qtd
      from por_sku s
      join pedido p on p.codigo = s.codigo
     where p.check_estoque_parado is null
)

select * from divergencia
