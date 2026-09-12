-- ─────────────────────────────────────────────────────────────────────────────
-- int_venda_diaria — a espinha da tela Monitoramento (v2 Etapa 10). Grão:
-- dia × produto, SEMPRE líquido (faturado − devolvido, CONTEXTO.md regra 1),
-- soma de int_faturamento_diario com int_devolucao_diaria - mesmo desenho de
-- int_venda_mensal, mas SEM a regra "todo SKU que apareceu em qualquer mês"
-- (CONTEXTO.md regra 9): aquela regra existe para sustentar a completude do
-- CADASTRO na aba pedido (produto sem venda ainda precisa aparecer com zero).
-- Aqui o consumidor é um painel de MOVIMENTO - dia sem venda de um produto não
-- é informação, é ausência de linha, e forçar 1 linha por produto por dia
-- multiplicaria a tabela por ~8.700 sem necessidade nenhuma.
--
-- VALOR_LIQUIDO usa devolucao.valor_devolucao (não valor_devolucao_liq) -
-- mesma escolha de int_venda_mensal.final.valor_liquido, para os dois grãos
-- ficarem comparáveis linha a linha quando somados por mês (ver
-- tests/compras_venda_diaria_bate_mensal.sql).
--
-- PESO_LIQUIDO_KG / LITROS_LIQUIDO: quantidade_liquida × fator ATUAL do
-- cadastro (int_produto_base.peso_unitario_kg / l_por_unidade). É APROXIMAÇÃO
-- deliberada, não uma medida histórica: o WinThor não versiona peso/litragem
-- por movimento, só o cadastro vigente. Se a embalagem de um produto mudou no
-- meio da janela, dias antigos herdam o fator ATUAL, não o de quando a venda
-- aconteceu - o mesmo compromisso que compras_pedido já assume para peso/
-- litragem em outros lugares do modelo. Câmbio de embalagem é raro e o desvio
-- fica concentrado nos poucos SKUs que trocaram, não espalhado no total.
-- ─────────────────────────────────────────────────────────────────────────────

with faturamento as (
    select * from {{ ref('int_faturamento_diario') }}
),

devolucao as (
    select * from {{ ref('int_devolucao_diaria') }}
),

produto as (
    select * from {{ ref('stg_produto') }}
),

departamento as (
    select * from {{ ref('stg_departamento') }}
),

secao as (
    select * from {{ ref('stg_secao') }}
),

fator as (
    select codigo, peso_unitario_kg, l_por_unidade from {{ ref('int_produto_base') }}
),

chaves as (
    select dia, id_produto from faturamento
    union
    select dia, id_produto from devolucao
),

final as (
    select
        k.dia,
        k.id_produto                                                    as codigo_produto,
        p.descricao_produto                                             as produto,
        p.status,
        p.id_departamento                                               as codepto,
        dep.descricao_departamento                                      as departamento,
        p.id_secao                                                      as codsec,
        sec.descricao_secao                                             as secao,
        nvl(f.quantidade_total, 0)                                      as quantidade_total,
        nvl(f.valor_total, 0)                                           as valor_total,
        nvl(d.quantidade_devolucao, 0)                                  as quantidade_devolucao,
        nvl(d.valor_devolucao, 0)                                       as valor_devolucao,
        nvl(f.quantidade_total, 0) - nvl(d.quantidade_devolucao, 0)     as quantidade_liquida,
        nvl(f.valor_total, 0) - nvl(d.valor_devolucao, 0)               as valor_liquido,
        (nvl(f.quantidade_total, 0) - nvl(d.quantidade_devolucao, 0))
            * nvl(ft.peso_unitario_kg, 0)                               as peso_liquido_kg,
        (nvl(f.quantidade_total, 0) - nvl(d.quantidade_devolucao, 0))
            * nvl(ft.l_por_unidade, 0)                                  as litros_liquido,
        nvl(f.quantidade_clientes_atacado, 0)                           as quantidade_clientes_atacado,
        nvl(f.quantidade_clientes_varejo, 0)                            as quantidade_clientes_varejo
      from chaves k
      left join faturamento f
        on f.dia = k.dia and f.id_produto = k.id_produto
      left join devolucao d
        on d.dia = k.dia and d.id_produto = k.id_produto
      left join produto p
        on p.id_produto = k.id_produto
      left join departamento dep
        on dep.id_departamento = p.id_departamento
      left join secao sec
        on sec.id_secao = p.id_secao
      left join fator ft
        on ft.codigo = k.id_produto
)

select * from final
