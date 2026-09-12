-- Invariante que este teste previne: a taxonomia decidida pelo Diretor de
-- Compras em 02/09/2026 (v2/DECISOES_DIRETOR.md item 1) sair do lugar sem que
-- ninguém perceba.
--
-- `categoria` e `pontua` são duas colunas de duas letras que decidem, sozinhas,
-- (a) em QUAL TELA o alerta aparece e (b) se ele empurra o SKU para o topo da
-- fila. Um tipo novo que entre em fat_alerta sem ser classificado cai no `else`
-- e vira 'DECISAO'/'S' em silêncio - passa a poluir a tela de Alertas e a somar
-- peso que o Diretor nunca deu. O accepted_values do schema.yml pega valor fora
-- do domínio; ele NÃO pega tipo classificado no lado errado, que é o que este
-- teste faz.
--
-- As três regras, exatamente como decididas:
--   1 - CADASTRO é, e é só, IMPORTADO, TRIB, MVA, SUCESSAO, LITRAGEM, FABRICA
--   2 - pontua = 'S' é, e é só, os NOVE tipos com peso na tabela do Diretor:
--       RUPTURA 5, SEM_GIRO 4, MARGEM_BAIXA 4, MARGEM_BAIXA_VAREJO 4, CUSTO 4,
--       BAIXO_GIRO 3, OPORTUNIDADE_DE_GIRO 3, DEVOLUCAO 2, MARGEM_ALTA 1
--   3 - FORA_DE_LINHA é o único DECISAO que não pontua (é o badge visual), e
--       nenhum CADASTRO pontua

with alerta as (
    select distinct tipo_alerta, categoria, pontua
      from {{ ref('fat_alerta') }}
),

divergencia as (
    -- regra 1
    select tipo_alerta, categoria, pontua,
           'CATEGORIA ERRADA PARA O TIPO' as motivo
      from alerta
     where categoria <> case when tipo_alerta in ('IMPORTADO', 'TRIB', 'MVA',
                                                  'SUCESSAO', 'LITRAGEM',
                                                  'FABRICA')
                             then 'CADASTRO' else 'DECISAO' end

    union all

    -- regra 2
    select tipo_alerta, categoria, pontua,
           'PONTUA ERRADO PARA O TIPO'
      from alerta
     where pontua <> case when tipo_alerta in ('RUPTURA', 'SEM_GIRO',
                                               'MARGEM_BAIXA',
                                               'MARGEM_BAIXA_VAREJO', 'CUSTO',
                                               'BAIXO_GIRO',
                                               'OPORTUNIDADE_DE_GIRO',
                                               'DEVOLUCAO', 'MARGEM_ALTA')
                          then 'S' else 'N' end

    union all

    -- regra 3
    select tipo_alerta, categoria, pontua,
           'CADASTRO NAO PODE PONTUAR'
      from alerta
     where categoria = 'CADASTRO' and pontua = 'S'
)

select * from divergencia
