-- Previne: o agrupamento por upper(EMBALAGEM) de int_produto_base escolher em
-- SILÊNCIO entre duas litragens diferentes.
--
-- Contexto (CONTEXTO.md 6.2): o MATCH do Excel ignora caixa, então o join da
-- embalagem PRECISA de upper() - 158 SKUs só casam assim. Mas o seed tem 10
-- pares de linhas que diferem só na caixa (`10X1`/`10x1`, `6X4 LTS`/`6x4 LTS`,
-- `1X1`/`1x1`...), e um join direto com upper() daria fan-out em 4.105 SKUs.
-- A solução é agrupar por upper() e pegar min(LITROS_POR_UNIDADE) - o que só é
-- equivalente ao "primeira ocorrência" do MATCH porque hoje os 10 pares têm
-- litragem IDÊNTICA.
--
-- Se alguém editar o CSV e as duas linhas passarem a divergir, min() vira uma
-- escolha arbitrária que muda L_POR_UNIDADE, muda o universo da curva ABC e,
-- pela regra 5, muda a CLASSE de TODOS os SKUs. Este teste reprova o build
-- nesse caso, em vez de deixar a escolha acontecer sem ninguém ver.

with embalagem as (
    select * from {{ ref('seed_embalagem') }}
),

conflito as (
    select
        upper(EMBALAGEM)                  as chave_embalagem,
        count(distinct LITROS_POR_UNIDADE) as litragens_distintas,
        min(LITROS_POR_UNIDADE)           as menor,
        max(LITROS_POR_UNIDADE)           as maior
      from embalagem
     group by upper(EMBALAGEM)
    having count(distinct LITROS_POR_UNIDADE) > 1
)

select * from conflito
