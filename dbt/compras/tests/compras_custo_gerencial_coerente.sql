-- Testa a identidade BY = BW + BX (CUSTO_TOT_GERENCIAL = CUSTO_TOT_OFICIAL +
-- CUSTO_ADICIONAL_IMAGEM) e que o ajuste de imagem só existe para a INGRAX.
--
-- Falha que ele previne: o ajuste Ingrax (80/20) escorregar para dentro da base
-- OFICIAL, ou o custo gerencial deixar de somá-lo. CUSTO_TOT_GERENCIAL é uma
-- das colunas com exigência de ZERO divergência no aceite, e é a base de custo
-- de todas as margens e de todos os preços sugeridos - errar aqui muda preço de
-- venda real (PDF §8.4, CONTEXTO.md regra 2). O segundo ramo pega o caso
-- inverso: ajuste aparecendo em fornecedor que não é INGRAX.

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

base as (
    select * from {{ ref('int_produto_base') }}
)

select
    c.codigo,
    b.fornecedor,
    c.custo_tot_oficial,
    c.custo_adicional_imagem,
    c.custo_tot_gerencial
  from custo c
  join base b
    on b.codigo = c.codigo
 where -- a identidade tem que valer sempre que o custo oficial existir
       (    c.custo_tot_oficial is not null
        and abs(c.custo_tot_gerencial
                - (c.custo_tot_oficial + c.custo_adicional_imagem)) > 0.0000001)
    -- custo oficial vazio propaga: o gerencial também tem que ficar vazio
    or (c.custo_tot_oficial is null and c.custo_tot_gerencial is not null)
    -- o ajuste de imagem só existe para a INGRAX
    or (c.custo_adicional_imagem <> 0 and upper(b.fornecedor) <> 'INGRAX')
    or (c.custo_adicional_imagem is null)
