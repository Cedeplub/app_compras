-- Invariante que este teste previne: CHECK_TRIB (coluna CC) voltar a ser
-- FORMULA MORTA, ou passar a disparar para SKU que nao deveria.
--
-- Historico, porque o nome do arquivo mudou: ate 21/08/2026 este teste se
-- chamava `compras_check_trib_formula_morta` e provava o OPOSTO - que o alerta
-- NUNCA dispara. Era a verdade da planilha: a formula testava so' se o codigo
-- de tributacao estava VAZIO, e `nvl(cod_tributacao, COD_TRIB_ICMS_PADRAO)`
-- sempre preenche. 0 celulas de 8.772.
--
-- O Diretor de Compras decidiu ampliar a regra (PENDENCIAS_DIRETORIA.md item
-- 4; CONTEXTO.md 6.4): o alerta passa a disparar quando o codigo e' vazio OU
-- ZERO. Com isso ele cobre os 5 SKUs de PCTABTRIB com `codst = 0`, que saem
-- sem MODALIDADE, sem aliquota e com margem em branco - e que antes saiam sem
-- alerta nenhum. A premissa do teste inverteu junto: agora ele exige que o
-- alerta FUNCIONE.
--
-- Severity error (nao warn, como era antes): o alerta deixou de ser
-- decorativo. SKU sem tributacao mapeada sai do modelo com margem e preco em
-- branco; se o alerta parar de dispara-lo, o comprador nao tem como saber que
-- aquele item precisa de cadastro fiscal - e um preco em branco passa batido.
--
-- A verificacao e' uma BICONDICIONAL, os dois lados importam:
--   ramo 1 - deveria alertar e nao alertou (regra apagada / voltou a ser morta)
--   ramo 2 - alertou sem motivo (a condicao pegou SKU com tributacao valida,
--            o que encheria ALERTA de ruido e escondria os alertas reais)

with alerta as (
    select * from {{ ref('int_produto_alerta') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

juncao as (
    select
        f.codigo,
        f.cod_icms,
        f.modalidade,
        a.check_trib
      from fiscal f
      join alerta a
        on a.codigo = f.codigo
)

-- ramo 1: codigo vazio ou zero e SEM alerta
select
    j.codigo,
    'DEVERIA ALERTAR E NAO ALERTOU'   as motivo,
    to_char(j.cod_icms)               as cod_icms,
    j.modalidade
  from juncao j
 where (j.cod_icms is null or j.cod_icms = 0)
   and j.check_trib is null

union all

-- ramo 2: alerta disparado com codigo de tributacao valido
select
    j.codigo,
    'ALERTOU SEM MOTIVO'              as motivo,
    to_char(j.cod_icms)               as cod_icms,
    j.modalidade
  from juncao j
 where j.check_trib is not null
   and j.cod_icms is not null
   and j.cod_icms <> 0
