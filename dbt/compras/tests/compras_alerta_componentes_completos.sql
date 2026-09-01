-- Testa que a coluna ALERTA (D) contém EXATAMENTE os checks ativos do SKU -
-- nem a mais, nem a menos.
--
-- Falha que ele previne: ALERTA concatena 14 colunas na ORDEM DO EXCEL
-- (X, Y, AL, AV, AO, AP, AY, BS, CC, CD, CE, CL, DO, DB - não a das letras,
-- não a alfabética). Uma expressão tão repetitiva é o lugar clássico para
-- alguém esquecer um `case when` num refactor ou colar dois iguais. O alerta
-- perdido não aparece em lugar nenhum: a coluna continua preenchida, plausível,
-- e o comprador simplesmente nunca fica sabendo de uma margem crítica.
--
-- O teste compara a CONTAGEM de checks ativos (via fat_alerta, que despivota os
-- mesmos 14) com a contagem de segmentos separados por "; " em ALERTA, e exige
-- que cada texto ativo esteja contido na string. Não testa a ORDEM - essa é
-- verificada contra a planilha pelo validar/validar_pedido.py, que compara a
-- string inteira; aqui o alvo é a COMPLETUDE, que nenhum outro teste pega.
--
-- ⚠ O contains usa "; " || texto || "; " nas pontas para não casar por
-- coincidência com um alerta que seja prefixo de outro ("ALERTA DE MARGEM" é
-- prefixo de si mesmo em CL e DB, que diferem só no meio da frase).

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

alerta as (
    select * from {{ ref('fat_alerta') }}
),

-- Quantos checks ATIVOS cada SKU tem, pela tabela despivotada.
ativos as (
    select
        codigo,
        count(*) as qtd_ativos
      from alerta
     group by codigo
),

-- Quantos SEGMENTOS a string de ALERTA tem: separadores + 1.
segmentos as (
    select
        p.codigo,
        p.alerta,
        case when p.alerta is null
             then 0
             else (length(p.alerta) - length(replace(p.alerta, '; ', ''))) / 2 + 1
        end                                                as qtd_segmentos
      from pedido p
),

-- Todo texto ativo tem de aparecer DENTRO da string, delimitado.
faltando as (
    select
        a.codigo,
        a.tipo_alerta
      from alerta a
      join pedido p
        on p.codigo = a.codigo
     where instr('; ' || p.alerta || '; ', '; ' || a.texto_alerta || '; ') = 0
),

divergencia as (
    select
        s.codigo,
        s.qtd_segmentos,
        nvl(v.qtd_ativos, 0) as qtd_ativos,
        s.alerta
      from segmentos s
      left join ativos v
        on v.codigo = s.codigo
     where s.qtd_segmentos <> nvl(v.qtd_ativos, 0)

    union all

    select
        f.codigo,
        -1                   as qtd_segmentos,
        -1                   as qtd_ativos,
        f.tipo_alerta        as alerta
      from faltando f
)

select * from divergencia
