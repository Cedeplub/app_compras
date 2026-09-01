-- Previne o bug real da regra 5 (CONTEXTO.md; PDF §12): o denominador da curva
-- ABC deixar de ser o total do build corrente.
--
-- Se `total_universo` virar constante, tabela travada ou total do OUTRO
-- universo, a soma das participações dentro do universo deixa de dar 1 - e a
-- CLASSE de todos os SKUs sai errada sem nenhum erro aparecer. Somar 1 é a
-- assinatura de "cada linha foi dividida pelo total das linhas do seu próprio
-- universo, medido agora".
--
-- Também pega universo vazando para o outro (uma linha classificada em
-- COM_LITRAGEM entrando no total de SEM_LITRAGEM faria as duas somas errarem).
--
-- Tolerância 1e-9: é aritmética de NUMBER do Oracle sobre ~8.800 divisões, não
-- tem por que divergir mais que isso. Universo com total zero (ninguém vendeu)
-- soma 0 legitimamente e fica de fora do teste.

with classe as (
    select * from {{ ref('int_produto_classe_abc') }}
),

soma as (
    select
        universo,
        max(total_universo)   as total_universo,
        sum(participacao)     as soma_participacao,
        count(*)              as n_skus
      from classe
     group by universo
)

select *
  from soma
 where total_universo <> 0
   and abs(soma_participacao - 1) > 1e-9
