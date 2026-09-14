-- Testa a MELHORIA A5 (REGRAS.md §6.1 item 5; §6.4): onde EXISTE decisão
-- gravada em APP_PEDIDO_ITEM,
-- PEDIDO_UNIDADES (BB) tem de bater com a soma de QUANTIDADE x FATOR_EXIBICAO
-- **dos itens daquela decisão** — cada um com o SEU fator CONGELADO —, nunca
-- com o fator corrente do cadastro (coluna K).
--
-- ⚠ Desde 12/09/2026 a fonte é APP_PEDIDO_ITEM, de grão PEDIDO x PRODUTO, e a
-- soma em unidade real é feita em `stg_decisao_pedido` (coluna `unidades`).
-- Por isso o braço 1 compara BB com `d.unidades`, e NÃO com
-- `d.pedido * d.fator_exibicao`: o segundo só é igual ao primeiro quando o SKU
-- está num pedido só. O que o teste exige separadamente é a invariante de
-- REEXIBIÇÃO — `BA x fator = BB` —, que é o que a tela usa para mostrar o
-- número de volta ao comprador.
--
-- Falha que ele previne: alguém voltar BB para `$BA2 * $K2`, como está na
-- planilha, e a quantidade em unidades de uma decisão já tomada passar a
-- mudar sozinha na atualização diária de cadastro. Quem se move junto é o
-- VALOR_PEDIDO (BD) e a cobertura MESES_EST+PED (BF): o comprador veria o
-- dinheiro do pedido dele mudar sem ter redigitado nada.
--
-- Também verifica o LADO DE FORA da regra, que é onde o erro simétrico mora:
-- SEM decisão não existe fator congelado, e BB tem de usar o corrente. Um
-- `nvl` mal colocado, ou um join que trouxesse fator de outro SKU, faria o
-- pedido zero virar não-zero ou o fator sumir.
--
-- ⚠ Até 12/09/2026 APP_DECISAO_PEDIDO estava com 4 linhas e o primeiro braço
-- quase não tinha o que medir. Com a fonte nova ele cobre os 66 SKUs dos
-- pedidos da v2 já no primeiro build. A regra foi exercitada de ponta a ponta
-- em 24/08/2026 com decisões de teste gravadas e apagadas (REGRAS.md, A5).
--
-- Tolerância 1e-9: pedido e fator são NUMBER com escala, mas a comparação é
-- de ponto flutuante depois da multiplicação.

with pedido as (
    select * from {{ ref('int_produto_pedido') }}
),

decisao as (
    select * from {{ ref('stg_decisao_pedido') }}
)

-- 1) COM decisão: BB = soma das unidades REAIS dos itens, e BA reexpresso no
--    fator congelado do item mais recente tem de voltar a BB.
select
    p.codigo,
    'COM_DECISAO_NAO_USOU_O_CONGELADO' as falha,
    p.pedido,
    p.fator_exibicao_pedido            as fator_usado,
    d.fator_exibicao                   as fator_congelado,
    p.pedido_unidades,
    d.unidades                         as pedido_unidades_esperado
  from pedido p
  join decisao d
    on d.id_produto = p.codigo
 where abs(p.pedido_unidades - d.unidades) > 1e-9
    or abs(p.pedido * p.fator_exibicao_pedido - d.unidades) > 1e-9
    or p.fator_exibicao_pedido <> d.fator_exibicao
    or p.pedido <> d.pedido

union all

-- 2) SEM decisão: não há congelado, vale o corrente (K) — e o pedido é zero.
select
    p.codigo,
    'SEM_DECISAO_NAO_USOU_O_CORRENTE' as falha,
    p.pedido,
    p.fator_exibicao_pedido           as fator_usado,
    b.fator_exibicao                  as fator_congelado,
    p.pedido_unidades,
    b.fator_exibicao * 0              as pedido_unidades_esperado
  from pedido p
  join {{ ref('int_produto_base') }} b
    on b.codigo = p.codigo
  left join decisao d
    on d.id_produto = p.codigo
 where d.id_produto is null
   and (   p.fator_exibicao_pedido <> b.fator_exibicao
        or p.pedido <> 0
        or p.pedido_unidades <> 0)
