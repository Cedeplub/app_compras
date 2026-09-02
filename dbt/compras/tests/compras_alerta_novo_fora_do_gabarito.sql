-- Invariante que este teste previne: um alerta NOVO (OPORTUNIDADE_DE_GIRO,
-- MARGEM_ALTA, ou o próximo que vier) vazar para dentro da string `ALERTA`
-- (coluna D) e reprovar o aceite contra a planilha.
--
-- `ALERTA` é coluna CRÍTICA (CONTEXTO.md §6.1.1): ela é comparada TEXTO A TEXTO
-- com a aba `pedido` da MODELO_COMPRAS_CEDEP_v11.xlsx, e toda divergência tem
-- de ser ATRIBUÍVEL a uma decisão registrada. Os alertas criados em 02/09/2026
-- não têm coluna na planilha - se um deles entrar em D, cada SKU em que ele
-- disparar vira divergência não atribuível. Hoje seriam 2.179 linhas só de
-- MARGEM_ALTA, e a validação inteira do motor perde o sentido.
--
-- A separação está garantida por CONSTRUÇÃO: os dois nascem em
-- `int_produto_alerta_extra`, que a concatenação de D nem sequer referencia. Um
-- teste ainda assim, porque "está em outro arquivo" é uma proteção que se perde
-- no primeiro refactor que resolva "juntar os dois models de alerta".
--
-- A verificação: nenhum texto de alerta NOVO (ordem_exibicao > 14) pode ser
-- encontrado dentro da string ALERTA do mesmo SKU. O delimitador "; " nas duas
-- pontas evita casar por coincidência com um alerta que seja prefixo de outro.
-- A contagem de segmentos de ALERTA contra os checks do gabarito é verificada à
-- parte, em compras_alerta_componentes_completos.sql.

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

alerta as (
    select * from {{ ref('fat_alerta') }}
),

novo as (
    select codigo, tipo_alerta, texto_alerta
      from alerta
     where ordem_exibicao > 14
),

divergencia as (
    select n.codigo,
           n.tipo_alerta  as motivo,
           n.texto_alerta as detalhe
      from novo n
      join pedido p on p.codigo = n.codigo
     where instr('; ' || p.alerta || '; ',
                 '; ' || n.texto_alerta || '; ') > 0
)

select * from divergencia
