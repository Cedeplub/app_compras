with source as (
    select * from {{ source('cedep', 'pcprodut') }}
),

renamed as (
    select
        CODPROD     as id_produto,
        CODFAB      as cod_fabrica,
        DESCRICAO   as descricao_produto,
        UNIDADE     as unidade,
        EMBALAGEM   as embalagem,
        QTUNITCX    as embal_compra,
        QTUNIT      as embal_venda,
        CODFORNEC   as id_fornecedor,
        CODEPTO     as id_departamento,
        CODSEC      as id_secao,
        -- PCPRODUT.CODFILIAL: usado APENAS na condicao de join de query.py
        -- (p.codfilial = e.codfilial OR p.codfilial = '99' OR p.codfilial IS NULL).
        -- Hoje e NULL nas 8.783 linhas do cadastro, o que torna a condicao um no-op -
        -- mas a coluna existe na origem e o join original a usa, entao ela e exposta
        -- aqui por fidelidade literal (CONTEXTO.md, int_cadastro_estoque).
        CODFILIAL   as id_filial_produto,
        NBM         as ncm,
        CODNCMEX    as ncm_excecao,
        PESOLIQ     as peso_liquido,
        PESOBRUTO   as peso_bruto,
        DTEXCLUSAO  as data_exclusao,
        -- situacao do produto: PCPRODUT.OBS2 = 'FL' marca fora de linha.
        -- OBS2 e VARCHAR2(2) e o valor gravado para produto ativo sao DOIS ESPACOS,
        -- nao NULL (so 16 produtos tem NULL de fato) - por isso o TRIM.
        case when upper(trim(OBS2)) = 'FL' then 'Inativo' else 'Ativo' end as status,
        case when upper(trim(OBS2)) = 'FL' then 'S'       else 'N'     end as fora_de_linha
    from source
)

-- Sem WHERE de proposito, e a razao NAO e que o filtro seja sempre indevido:
-- `dtexclusao is null` tem uso DIFERENTE em cada relatorio (ver CONTEXTO.md secao 6,
-- regra 11). No relatorio de estoque e condicao fixa e global; no mensal aparece so
-- dentro de `produtos_incluir`, e aplica-lo globalmente apagaria produto excluido que
-- teve movimento. O staging alimenta os dois, entao nao tem como escolher - quem aplica
-- o corte e a camada intermediate, que sabe qual uso e o dela.
select * from renamed
