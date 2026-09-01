{{ config(severity = 'warn') }}

-- Aviso (severity warn, nao error): lista o BURACO RESIDUAL que CHECK_TRIB
-- ainda nao cobre - SKU cujo COD_ICMS esta PREENCHIDO e e' DIFERENTE DE ZERO,
-- mas nao tem linha no seed_icms. Ele sai sem MODALIDADE, sem aliquota e com
-- margem em branco, e a condicao decidida em 21/08/2026 ("vazio ou zero") nao
-- o pega, porque o codigo dele nao e' nenhum dos dois.
--
-- Hoje o resultado e' VAZIO: os unicos SKUs sem modalidade sao os 5 de
-- `codst = 0`, e esses o alerta ja pega (ver
-- tests/compras_check_trib_pega_codigo_zero.sql). Este teste existe para o dia
-- em que aparecer um codigo novo em PCTABTRIB sem correspondencia no seed -
-- ai a lista deixa de ser vazia e o build avisa, em vez de o SKU sumir do
-- radar com preco em branco.
--
-- warn e nao error de proposito: ampliar de novo o criterio do alerta e'
-- decisao de negocio do Diretor de Compras, nao defeito de porte. O teste
-- torna o caso VISIVEL a cada build; quem decide o que fazer com ele e' quem
-- responde pelo fiscal (PDF secao 14).

with alerta as (
    select * from {{ ref('int_produto_alerta') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
)

select
    f.codigo,
    'SEM MODALIDADE E FORA DO CRITERIO DE CHECK_TRIB' as motivo,
    to_char(f.cod_icms)                               as cod_icms
  from fiscal f
  join alerta a
    on a.codigo = f.codigo
 where f.modalidade is null
   and a.check_trib is null
