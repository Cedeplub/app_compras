-- Testa que a COBERTURA PROJETADA do modelo (BF, MESES_EST_PED) soma parcelas
-- na MESMA unidade, e que pedido Fechado não entra nela.
--
-- Origem: feedback do Diretor de Compras em 09/10/2026, item 4. Ele mediu 895
-- itens com a cobertura errada, 108 com mais de 12 meses a mais, e conferiu o
-- SKU 2808 à mão: 67,7 meses onde o certo são 6,9.
--
-- As duas falhas que este teste previne, e as duas já aconteceram:
--
--   1. MISTURA DE UNIDADE. EST_PEND chega dividido por FATOR_EXIBICAO
--      (int_produto_demanda.sql:138,142,201); PEDIDO_UNIDADES (BB) está em
--      unidade REAL. Somar os dois infla a cobertura pelo fator: num item de
--      caixa 24, 60 caixas viravam 1.440 e a cobertura multiplicava por 24.
--      É a mesma regra 6 do CONTEXTO.md que a Etapa 18 removeu da TELA —
--      e que continuava viva aqui, no modelo, porque a Etapa 18
--      deliberadamente não tocou nesta coluna (ver §3.3 daquele documento).
--
--   2. PEDIDO FECHADO CONTADO DUAS VEZES. Um pedido Fechado já virou pedido no
--      WinThor e já está dentro do PENDENTE (PCEST.QTPEDIDA, que alimenta
--      EST_PEND). Somá-lo de novo conta a mesma compra duas vezes. No SKU
--      2808, o pedido 261 (Fechado, 50 caixas) somava 1.200 unidades que já
--      estavam no pendente.
--
-- O primeiro ramo é a identidade: BF tem de ser exatamente
-- `(EST_PEND + unidades_abertas / FATOR_EXIBICAO) / MEDIA_JANELA`. Ele falha
-- tanto se alguém voltar a usar BB quanto se alguém "simplificar" o divisor.
--
-- O segundo ramo é o mais importante, porque é o que uma refatoração
-- descuidada quebraria sem mudar a aritmética: prova que, em todo SKU que tem
-- pedido Fechado, a parcela aberta é MENOR que o total. Se as duas forem
-- iguais num SKU com Fechado, o filtro de status sumiu.
--
-- ⚠ ESTE TESTE DECLARA UM DESVIO DA PLANILHA. A V11 faz `($V2+$BB2)/$AG2`, com
-- a mistura de unidades e com todos os status. A comparação célula a célula de
-- validar/validar_pedido.py passa a divergir em MESES_EST_PED nos SKUs com
-- pedido salvo. Divergência DELIBERADA, decidida com o usuário em 09/10/2026:
-- a planilha é que está errada nessa coluna.
--
-- Tolerância de 0,0001 mês no primeiro ramo: é identidade aritmética, não
-- comparação de medidas — a folga existe só para o arredondamento do NUMBER.

with pedido as (
    select * from {{ ref('int_produto_pedido') }}
),

demanda as (
    select * from {{ ref('int_produto_demanda') }}
),

base as (
    select * from {{ ref('int_produto_base') }}
),

decisao as (
    select * from {{ ref('stg_decisao_pedido') }}
),

-- Os SKUs que têm pelo menos um item em pedido Fechado. A existência de um
-- Fechado é o que torna `unidades > unidades_abertas` obrigatório.
com_fechado as (
    select distinct i.ID_PRODUTO as id_produto
      from {{ source('compras_app', 'app_pedido_item') }} i
      join {{ source('compras_app', 'app_pedido') }} c
        on c.ID_PEDIDO = i.ID_PEDIDO
     where c.STATUS = 'Fechado'
)

select
    p.codigo,
    'BF nao reproduz (est_pend + abertas/fator) / media' as motivo
  from pedido p
  join demanda d on d.codigo = p.codigo
  join base    b on b.codigo = p.codigo
  left join decisao dp on dp.id_produto = p.codigo
 where d.media_janela <> 0
   and p.meses_est_ped is not null
   and abs(p.meses_est_ped
           - (d.est_pend + nvl(dp.unidades_abertas, 0) / nullif(b.fator_exibicao, 0))
             / d.media_janela) > 0.0001

union all

select
    cf.id_produto as codigo,
    'SKU com pedido Fechado, mas a parcela aberta e igual ao total' as motivo
  from com_fechado cf
  join decisao dp on dp.id_produto = cf.id_produto
 where dp.unidades_abertas >= dp.unidades
