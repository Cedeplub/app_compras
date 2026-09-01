-- Testa que ALT_PV_AT_AV/_AP e ALT_PV_VAR_AV/_AP ficam NULOS para todo SKU que
-- não tem linha em APP_DECISAO_PRECO.
--
-- Falha que ele previne: o preço final ser preenchido automaticamente com uma
-- das sugestões calculadas. É o único ponto do modelo em que uma PESSOA decide
-- o número (PDF §9.3, CONTEXTO.md regra 10); preencher sozinho apagaria a
-- distinção entre "a máquina sugere" e "o Diretor decidiu" - e o preço iria
-- para a equipe comercial sem ninguém ter respondido por ele.
-- O teste não compara com as sugestões de propósito: o Diretor PODE digitar
-- exatamente o valor sugerido, e isso é decisão dele, não defeito.

with preco as (
    select * from {{ ref('int_produto_preco_sugerido') }}
),

decisao as (
    select * from {{ ref('stg_decisao_preco') }}
)

select
    p.codigo,
    p.alt_pv_at_av,
    p.alt_pv_at_ap,
    p.alt_pv_var_av,
    p.alt_pv_var_ap
  from preco p
  left join decisao d
    on d.id_produto = p.codigo
 where d.id_produto is null
   and (   p.alt_pv_at_av  is not null
        or p.alt_pv_at_ap  is not null
        or p.alt_pv_var_av is not null
        or p.alt_pv_var_ap is not null)
