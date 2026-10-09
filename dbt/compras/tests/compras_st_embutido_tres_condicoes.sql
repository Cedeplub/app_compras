-- Testa a REGRA DAS TRES CONDICOES do ST embutido, nos DOIS sentidos.
--
-- Origem: regra fechada pelo Diretor de Compras em 09/10/2026 — soma-se o
-- ICMS-ST ao custo/valor gerencial quando, e somente quando, as tres valem
-- juntas:
--
--   1. cadastro = ST_SUBSTITUTO;
--   2. ultima entrada a partir de ST_BENEFICIO_INICIO (01/10/2022, Decreto
--      7.799);
--   3. fornecedor da entrada de FORA do estado de destino.
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
--      guarda-corpo, uma condicao trocada por OR, a data lida errada. Hoje
--      cobre 1.274 ativos fora da modalidade, 231 com entrada anterior ao
--      Decreto, 683 comprados dentro da BA e 119 sem data ou sem UF.
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

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
),

par as (
    select * from {{ ref('int_parametro') }}
),

-- `tem_direito` e a leitura das tres condicoes a partir das colunas que o
-- model EXPOE (modalidade, dt_ult_ent, uf_entrada) — nao da macro. E' o mais
-- perto que um teste pode chegar de ler o enunciado em vez da implementacao.
avaliado as (
    select
        c.codigo,
        nvl(c.icms_st_bruto, 0)                      as st_somado,
        f.mva,
        f.vl_ent_unit,
        case when f.modalidade  = 'ST_SUBSTITUTO'
              and c.dt_ult_ent is not null
              and c.dt_ult_ent >= p.st_beneficio_inicio
              and c.uf_entrada is not null
              and c.uf_entrada <> '{{ var("compras_uf_destino", "BA") }}'
             then 1 else 0
        end                                          as tem_direito
      from custo c
      join fiscal f on f.codigo = c.codigo
     cross join par p
)

select
    codigo,
    'somou ICMS-ST sem passar nas tres condicoes' as motivo
  from avaliado
 where tem_direito = 0
   and st_somado > 0

union all

select
    codigo,
    'passa nas tres condicoes, tem MVA e nota, e nao somou ICMS-ST' as motivo
  from avaliado
 where tem_direito = 1
   and nvl(mva, 0) > 0
   and nvl(vl_ent_unit, 0) > 0
   and st_somado = 0
