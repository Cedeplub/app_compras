-- Invariante que este teste previne: `fat_alerta` PERDER ou INVENTAR um alerta
-- da planilha ao traduzir os CHECK_* para a taxonomia da tela.
--
-- Desde 02/09/2026 (v2/DECISOES_DIRETOR.md item 1) `fat_alerta` não é mais um
-- espelho literal de `int_produto_alerta`: renomeia dois tipos, PARTE
-- CHECK_ESTOQUE_PARADO em SEM_GIRO/BAIXO_GIRO, remove INATIVO e acrescenta dois
-- alertas que não existem na planilha. Cada uma dessas quatro operações é uma
-- chance de o número da tela deixar de bater com o gabarito - e nenhuma delas
-- quebra nada visivelmente: a tela continua abrindo, com um alerta a menos.
--
-- O que se exige, para as linhas que VÊM da planilha (ordem_exibicao <= 14):
--   ramo 1 - todo CHECK_* ativo, exceto CHECK_INATIVO, tem exatamente UMA linha
--            em fat_alerta com o mesmo texto;
--   ramo 2 - toda linha de fat_alerta com ordem <= 14 tem um CHECK_* ativo de
--            texto igual por trás;
--   ramo 3 - CHECK_INATIVO ativo NÃO pode virar linha (foi retirado da
--            taxonomia; hoje ele é 100% vazio porque depende de PEDIDO, mas no
--            dia em que houver decisão gravada em APP_DECISAO_PEDIDO ele passa
--            a ter valor e o ramo deixa de ser decorativo).
--
-- ⚠ A comparação é por (codigo, texto), não por (codigo, tipo): SEM_GIRO e
-- BAIXO_GIRO compartilham o texto de CHECK_ESTOQUE_PARADO de propósito, então
-- comparar por tipo exigiria uma tabela de-para aqui e o teste só provaria que
-- a tabela concorda consigo mesma.

with check_sku as (
    select * from {{ ref('int_produto_alerta') }}
),

alerta as (
    select * from {{ ref('fat_alerta') }}
),

-- Os 13 checks que VIRAM linha (os 14 menos CHECK_INATIVO), despivotados aqui
-- de forma independente da listagem de fat_alerta.
esperado as (
    select codigo, check_fabrica                as texto from check_sku where check_fabrica                is not null
     union all select codigo, check_ruptura                from check_sku where check_ruptura                is not null
     union all select codigo, check_devolucao_alta         from check_sku where check_devolucao_alta         is not null
     union all select codigo, check_estoque_parado         from check_sku where check_estoque_parado         is not null
     union all select codigo, check_fora_de_linha          from check_sku where check_fora_de_linha          is not null
     union all select codigo, check_litragem               from check_sku where check_litragem               is not null
     union all select codigo, check_importado              from check_sku where check_importado              is not null
     union all select codigo, check_trib                   from check_sku where check_trib                   is not null
     union all select codigo, check_mva                    from check_sku where check_mva                    is not null
     union all select codigo, check_custo                  from check_sku where check_custo                  is not null
     union all select codigo, check_margem_instavel        from check_sku where check_margem_instavel        is not null
     union all select codigo, check_sucessao               from check_sku where check_sucessao               is not null
     union all select codigo, check_margem_instavel_varejo from check_sku where check_margem_instavel_varejo is not null
),

obtido as (
    select codigo, texto_alerta as texto
      from alerta
     where ordem_exibicao <= 14
),

divergencia as (
    -- ramo 1: check ativo que nao virou linha
    select e.codigo, 'CHECK ATIVO SEM LINHA EM FAT_ALERTA' as motivo, e.texto
      from esperado e
     where not exists (select 1 from obtido o
                        where o.codigo = e.codigo and o.texto = e.texto)

    union all

    -- ramo 2: linha de fat_alerta sem check ativo por tras
    select o.codigo, 'LINHA EM FAT_ALERTA SEM CHECK ATIVO', o.texto
      from obtido o
     where not exists (select 1 from esperado e
                        where e.codigo = o.codigo and e.texto = o.texto)

    union all

    -- ramo 3: CHECK_INATIVO voltou a virar linha
    select c.codigo, 'CHECK_INATIVO VIROU LINHA - foi RETIRADO da taxonomia',
           c.check_inativo
      from check_sku c
      join alerta a
        on a.codigo = c.codigo
       and a.texto_alerta = c.check_inativo
     where c.check_inativo is not null
)

select * from divergencia
