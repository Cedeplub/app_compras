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
-- O teste compara a CONTAGEM de checks ativos com a contagem de segmentos
-- separados por "; " em ALERTA, e exige que cada texto ativo esteja contido na
-- string. Não testa a ORDEM - essa é verificada contra a planilha pelo
-- validar/validar_pedido.py, que compara a string inteira; aqui o alvo é a
-- COMPLETUDE, que nenhum outro teste pega.
--
-- ⚠ MUDOU EM 02/09/2026, e a mudança é o ponto: a lista de 14 checks é lida
-- direto de `int_produto_alerta`, não mais de `fat_alerta`. Antes as duas
-- tabelas tinham a MESMA taxonomia e uma servia de espelho da outra; desde a
-- taxonomia decidida pelo Diretor (v2/DECISOES_DIRETOR.md item 1) elas
-- divergem de propósito - `fat_alerta` renomeia dois tipos, parte PARADO em
-- dois, remove INATIVO e acrescenta dois alertas que a planilha não tem.
-- Continuar lendo de lá faria este teste reprovar por causa da TELA, não do
-- GABARITO, que é o que ele existe para proteger. A fidelidade do despivot
-- passou a ter teste próprio: compras_fat_alerta_espelha_checks.sql.
--
-- ⚠ O contains usa "; " || texto || "; " nas pontas para não casar por
-- coincidência com um alerta que seja prefixo de outro ("ALERTA DE MARGEM" é
-- prefixo de si mesmo em CL e DB, que diferem só no meio da frase).

with pedido as (
    select * from {{ ref('fat_pedido') }}
),

check_sku as (
    select * from {{ ref('int_produto_alerta') }}
),

-- Os 14 checks do gabarito, despivotados AQUI - listagem independente da de
-- fat_alerta, de proposito: e' ela que pega a omissao de um `case when` na
-- concatenacao de D.
alerta as (
    select codigo, 'CHECK_FABRICA'                as tipo_alerta, check_fabrica                as texto_alerta from check_sku
     union all select codigo, 'CHECK_INATIVO',                    check_inativo                from check_sku
     union all select codigo, 'CHECK_RUPTURA',                    check_ruptura                from check_sku
     union all select codigo, 'CHECK_DEVOLUCAO_ALTA',             check_devolucao_alta         from check_sku
     union all select codigo, 'CHECK_ESTOQUE_PARADO',             check_estoque_parado         from check_sku
     union all select codigo, 'CHECK_FORA_DE_LINHA',              check_fora_de_linha          from check_sku
     union all select codigo, 'CHECK_LITRAGEM',                   check_litragem               from check_sku
     union all select codigo, 'CHECK_IMPORTADO',                  check_importado              from check_sku
     union all select codigo, 'CHECK_TRIB',                       check_trib                   from check_sku
     union all select codigo, 'CHECK_MVA',                        check_mva                    from check_sku
     union all select codigo, 'CHECK_CUSTO',                      check_custo                  from check_sku
     union all select codigo, 'CHECK_MARGEM_INSTAVEL',            check_margem_instavel        from check_sku
     union all select codigo, 'CHECK_SUCESSAO',                   check_sucessao               from check_sku
     union all select codigo, 'CHECK_MARGEM_INSTAVEL_VAREJO',     check_margem_instavel_varejo from check_sku
),

ativo as (
    select * from alerta where texto_alerta is not null
),

-- Quantos checks ATIVOS cada SKU tem.
ativos as (
    select
        codigo,
        count(*) as qtd_ativos
      from ativo
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
      from ativo a
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
