-- Testa a MELHORIA A5 (REGRAS.md §6.1 item 5; §6.4): onde EXISTE decisão
-- gravada em APP_PEDIDO_ITEM, PEDIDO_UNIDADES (BB) tem de bater com a soma de
-- QUANTIDADE x FATOR_EXIBICAO **dos itens daquela decisão** — cada um com o SEU
-- fator CONGELADO —, nunca com o fator corrente do cadastro (coluna K).
--
-- ── ⚠ POR QUE A EXPECTATIVA É LIDA DIRETO DA TABELA DE ORIGEM ────────────────
-- Até 14/09/2026 os dois braços comparavam `int_produto_pedido` contra
-- `stg_decisao_pedido`. Isso NÃO provava a regra: `int_produto_pedido` copia a
-- coluna (`nvl(dp.unidades, 0) as pedido_unidades`), então trocar as DUAS
-- ocorrências de `sum(quantidade * fator_exibicao)` do staging por
-- `sum(quantidade)` deixava `unidades`, `pedido` e `pedido * fator` coerentes
-- ENTRE SI — e o teste passava. Ele só quebrava com injeção parcial, numa linha
-- só. Era teste de consistência interna, não de regra.
--
-- Por isso a expectativa agora é recalculada aqui, DENTRO do teste, a partir de
-- `APP_PEDIDO_ITEM` — fonte independente e fora da cadeia testada, onde
-- QUANTIDADE e FATOR_EXIBICAO estão na MESMA linha, congelados no instante da
-- decisão. A duplicação da fórmula é deliberada: é ela que faz do teste um
-- oráculo. Se o staging e este arquivo divergirem, um dos dois está errado — e
-- é exatamente isso que se quer ouvir.
--
-- ── ⚠ COBERTURA DEPENDE DE DADO, E ISSO É DECISÃO CONSCIENTE ────────────────
-- Com `APP_PEDIDO_ITEM` vazia o braço 1 não tem o que comparar e passa vazio.
-- Ele NÃO exige dado de propósito: "nenhum pedido gravado" é estado legítimo do
-- sistema (é o estado de hoje, 14/09/2026), e reprovar o build diário por causa
-- disso seria pior que o risco que se quer cobrir. Quem avisa que a cobertura
-- está zerada é o teste irmão `compras_pedido_item_sem_cobertura`, com
-- severidade `warn`: o build segue, mas a falta de cobertura aparece no log em
-- vez de passar por verde silencioso. A prova de que ESTE teste sabe reprovar
-- foi feita com um pedido de teste gravado e apagado (14/09/2026, SKU 6641,
-- fator 12 — mesmo método de 24/08/2026, REGRAS.md A5).
--
-- Falha que ele previne: alguém voltar BB para `$BA2 * $K2`, como está na
-- planilha, ou somar QUANTIDADE sem o fator (§9.2 regra 2: somar caixa com
-- unidade), e a quantidade em unidades de uma decisão já tomada passar a mudar
-- sozinha na atualização diária de cadastro. Quem se move junto é o VALOR_PEDIDO
-- (BD) e a cobertura MESES_EST+PED (BF): o comprador veria o dinheiro do pedido
-- dele mudar sem ter redigitado nada.
--
-- Também verifica o LADO DE FORA da regra, que é onde o erro simétrico mora:
-- SEM decisão não existe fator congelado, e BB tem de usar o corrente. Um
-- `nvl` mal colocado, ou um join que trouxesse fator de outro SKU, faria o
-- pedido zero virar não-zero ou o fator sumir.
--
-- Tolerância 1e-9: quantidade e fator são NUMBER com escala, mas a comparação é
-- de ponto flutuante depois da multiplicação.

with pedido as (
    select * from {{ ref('int_produto_pedido') }}
),

-- A FONTE INDEPENDENTE: a tabela da aplicação, sem passar por model nenhum.
item as (
    select
        ID_PEDIDO       as id_pedido,
        ID_PRODUTO      as id_produto,
        QUANTIDADE      as quantidade,
        FATOR_EXIBICAO  as fator_exibicao,
        CRIADO_EM       as criado_em
      from {{ source('compras_app', 'app_pedido_item') }}
),

item_marcado as (
    select
        i.*,
        row_number() over (
            partition by i.id_produto
            order by i.criado_em desc, i.id_pedido desc
        ) as ordem_recencia
      from item i
),

-- O oráculo: unidade REAL por SKU e o fator congelado do item mais recente,
-- ambos calculados a partir da linha gravada, nunca do staging.
esperado as (
    select
        id_produto,
        sum(quantidade * fator_exibicao)                          as unidades_esperadas,
        max(case when ordem_recencia = 1 then fator_exibicao end) as fator_congelado
      from item_marcado
     group by id_produto
)

-- 1) COM decisão: BB = soma das unidades REAIS gravadas; o fator de exibição é
--    o congelado do item mais recente; e BA reexpresso nele volta a BB.
select
    p.codigo,
    'COM_DECISAO_NAO_USOU_O_CONGELADO' as falha,
    p.pedido,
    p.fator_exibicao_pedido            as fator_usado,
    e.fator_congelado,
    p.pedido_unidades,
    e.unidades_esperadas               as pedido_unidades_esperado
  from pedido p
  join esperado e
    on e.id_produto = p.codigo
 where abs(p.pedido_unidades - e.unidades_esperadas) > 1e-9
    or abs(p.pedido * p.fator_exibicao_pedido - e.unidades_esperadas) > 1e-9
    or p.fator_exibicao_pedido <> e.fator_congelado

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
  left join esperado e
    on e.id_produto = p.codigo
 where e.id_produto is null
   and (   p.fator_exibicao_pedido <> b.fator_exibicao
        or p.pedido <> 0
        or p.pedido_unidades <> 0)
