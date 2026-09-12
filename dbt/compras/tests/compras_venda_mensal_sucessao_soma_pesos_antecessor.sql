{{ config(severity = 'warn') }}

-- Aviso (severity warn, nao error): se a soma dos PESO_1/PESO_2 que
-- reivindicam o MESMO antecessor (com ATIVO='SIM') ultrapassar 1, os
-- sucessores juntos estao herdando mais de 100% do historico daquele
-- antecessor - a planilha tinha a coluna SOMA_PESOS_DO_ANTIGO_1 (aba
-- dSucessao) so para mostrar isso ao humano, e essa checagem se perdeu na
-- virada para seed_sucessao.csv.
--
-- Nao mexe na aritmetica do model: o Excel tambem soma sem checar (e' fiel
-- reproduzir isso), este teste so RECOLOCA o aviso. Hoje (25 linhas, todas
-- ATIVO='NAO') o WHERE ATIVO='SIM' zera o resultado e o teste passa vazio -
-- mas o dado ja mostra o risco: o produto 7095 e' reivindicado por 4
-- sucessores (8316, 8437, 8438, 8464) com PESO_1=1 cada - se as quatro linhas
-- forem ativadas de uma vez, 7095 seria herdado 4x (400% da demanda). Mesma
-- forma para 2096 (3 sucessores) e 9/6575/6719/7091 (2 sucessores cada).

with sucessao as (
    select * from {{ ref('seed_sucessao') }} where ATIVO = 'SIM'
),

reivindicacoes as (
    select ANTIGO_1 as antecessor, nvl(PESO_1, 0) as peso
      from sucessao
     where ANTIGO_1 is not null

    union all

    select ANTIGO_2 as antecessor, nvl(PESO_2, 0) as peso
      from sucessao
     where ANTIGO_2 is not null
),

soma_por_antecessor as (
    select
        antecessor,
        sum(peso) as soma_pesos,
        count(*)  as qtd_sucessores
      from reivindicacoes
     group by antecessor
)

select *
  from soma_por_antecessor
 where soma_pesos > 1
