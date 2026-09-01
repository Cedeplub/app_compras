-- Testa que ICMS-ST só é diferente de zero quando MODALIDADE = 'ST_SUBSTITUTO'.
--
-- Falha que ele previne: calcular ICMS-ST para item cujo imposto já foi
-- recolhido antes na cadeia (ST_RECOLHIDO) ou que sequer está no regime
-- (NORMAL), ou para os SKUs sem modalidade (codst = 0, CONTEXTO.md §6.2).
-- Seria imposto recolhido a mais embutido no custo e no preço - PDF §8.1.
-- O ramo de baixo pega o simétrico: ST_SUBSTITUTO com MVA e valor de entrada
-- presentes NÃO pode sair vazio, porque vazio apaga a cadeia de preço inteira.

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
)

select
    f.codigo,
    f.modalidade,
    f.mva,
    f.vl_ent_unit,
    c.icms_st_s_valor,
    c.icms_st_s_custo
  from fiscal f
  join custo c
    on c.codigo = f.codigo
 where (    (f.modalidade is null or f.modalidade <> 'ST_SUBSTITUTO')
        and (nvl(c.icms_st_s_valor, -1) <> 0 or nvl(c.icms_st_s_custo, -1) <> 0))
    or (    f.modalidade = 'ST_SUBSTITUTO'
        and f.mva is not null
        and f.vl_ent_unit <> 0
        and (c.icms_st_s_valor is null or c.icms_st_s_custo is null))
