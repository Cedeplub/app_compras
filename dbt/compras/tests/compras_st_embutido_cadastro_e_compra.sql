-- Testa a REGRA FINAL do ST embutido, nos DOIS sentidos.
--
-- Origem: regra fechada pelo Diretor de Compras em 09/10/2026, depois de ele
-- conferir no servidor de teste e REPROVAR a versao que tinha uma terceira
-- condicao de UF. Soma-se o ICMS-ST quando, e somente quando, as duas valem:
--
--   1. cadastro = ST_SUBSTITUTO;
--   2. ultima COMPRA a partir de ST_BENEFICIO_INICIO (01/10/2022, Decreto
--      7.799). Sem compra nenhuma, nao soma.
--
-- ⚠ "ultima COMPRA", nao PCEST.DTULTENT. O WinThor grava em DTULTENT qualquer
-- entrada, inclusive transferencia entre filiais e bonificacao. Era dai que
-- vinha o defeito que ele reprovou: a UF da "ultima entrada" era a da filial
-- que transferiu, na BA, e 215 itens perderam o ST por isso.
--
-- A regra em si mora em `macros/compras_st_ja_na_entrada.sql`, escrita uma vez
-- so'. Este teste NAO a reescreve: ele afirma o EFEITO dela sobre
-- ICMS_ST_BRUTO, que e' o numero que de fato entra no valor gerencial. A
-- diferenca importa — uma copia da condicao aqui provaria que duas copias
-- concordam, e passaria junto com ela no dia em que as duas estivessem erradas.
--
-- ── OS DOIS RAMOS, e por que os dois ────────────────────────────────────────
--
--   1. SOMOU SEM DIREITO. Pega o afrouxamento: um `case` que perdeu o
--      guarda-corpo, uma condicao trocada por OR, a data lida da coluna
--      errada. Hoje cobre 1.274 ativos fora da modalidade, 171 com ultima
--      compra anterior ao Decreto e 90 sem compra nenhuma.
--
--   2. DEIXOU DE SOMAR TENDO DIREITO. Este e' o ramo que falta na maioria dos
--      testes de regra restritiva, e e' o mais importante: sem ele, "nunca
--      somar" passaria no ramo 1 com louvor, e o valor gerencial cairia em
--      ~2.840 ativos sem nenhum teste reclamar. Zerar a regra e tao defeito
--      quanto afrouxa-la, e no mesmo silencio.
--
-- ⚠ O ramo 2 exclui MVA nula e nota zerada. Nao e' folga: BT/BU/ICMS_ST_BRUTO
-- saem NULL nesses casos por reproducao do `IF(OR($BM2="",$BH2=0),"",...)` da
-- planilha (ver o cabecalho de int_produto_custo). A ausencia ali e' decisao
-- da planilha, nao da regra do ST — cobra-la aqui faria este teste reprovar
-- por um motivo que nao e' o seu.
--
-- ⚠ Le a data de `int_parametro`, nunca escrita no SQL. Um teste com
-- 01/10/2022 chumbado passaria a reprovar no dia em que a diretoria mudasse o
-- parametro, e a culpa pareceria do model.
--
-- Medido em 09/10/2026 (4.553 ativos): 0 violacoes nos dois ramos.
-- Particao dos 3.279 ST substituto: 3.018 somam, 171 tem compra anterior ao
-- Decreto e 90 nao tem compra nenhuma.

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

par as (
    select * from {{ ref('int_parametro') }}
),

-- `tem_direito` e a leitura das duas condicoes a partir das colunas que o
-- model EXPOE (modalidade, dt_ult_compra) — nao da macro. E' o mais perto que
-- um teste pode chegar de ler o enunciado em vez da implementacao.
--
-- ⚠ `uf_entrada` continua existindo no model e NAO entra aqui, de proposito:
-- ela descreve a ultima ENTRADA (para o aviso "nao e compra" da Precificacao)
-- e foi provada inadequada como condicao de ST. Se alguem a trouxer de volta
-- para a regra, este teste nao vai acusar - mas o cabecalho do model explica
-- por que nao se deve.
avaliado as (
    select
        c.codigo,
        nvl(c.icms_st_bruto, 0)                      as st_somado,
        f.mva,
        f.vl_ent_unit,
        case when f.modalidade = 'ST_SUBSTITUTO'
              and c.dt_ult_compra is not null
              and c.dt_ult_compra >= p.st_beneficio_inicio
             then 1 else 0
        end                                          as tem_direito
      from custo c
      join fiscal f on f.codigo = c.codigo
     cross join par p
)

select
    codigo,
    'somou ICMS-ST sem cadastro ST substituto ou sem compra depois do Decreto' as motivo
  from avaliado
 where tem_direito = 0
   and st_somado > 0

union all

select
    codigo,
    'e ST substituto com compra depois do Decreto, tem MVA e nota, e nao somou' as motivo
  from avaliado
 where tem_direito = 1
   and nvl(mva, 0) > 0
   and nvl(vl_ent_unit, 0) > 0
   and st_somado = 0
