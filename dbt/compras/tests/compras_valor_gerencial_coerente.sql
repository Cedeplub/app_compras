-- Testa as duas identidades que definem o VALOR GERENCIAL, e a relação dele
-- com o CUSTO GERENCIAL.
--
-- Origem: documento "Valor Gerencial e Custo Gerencial" do Diretor de Compras
-- (6ª versão), validado por ele na tela de /precificacao em 29/09/2026 sobre 9
-- produtos cobrindo as 3 modalidades × 2 tratamentos de PIS/COFINS.
--
-- Falha que ele previne: o valor gerencial é o espelho BRUTO do custo
-- gerencial — mesma estrutura, sem os termos de crédito. É fácil alguém
-- "unificar" os dois cálculos num refactor e, ao fazê-lo, subtrair o crédito
-- de ICMS do lado bruto (ou multiplicar o adicional por (1 - piscof_ef)). O
-- número continuaria plausível na tela e estaria errado — exatamente o modo de
-- falha que este projeto mais teme.
--
-- Os três ramos:
--
--   1. VALOR_TOT_GERENCIAL = VL_ENT_UNIT + ICMS_ST_BRUTO + VALOR_ADICIONAL_IMAGEM.
--      A soma, como o compras_custo_gerencial_coerente cobra BY = BW + BX.
--
--   2. ICMS_ST_BRUTO >= ICMS_ST_s_VALOR, sempre. As duas têm a MESMA base
--      (vl_ent_unit × (1+mva) × alíquota); a líquida subtrai
--      vl_ent_unit × cred_icms, que nunca é negativo. Se o bruto ficar MENOR
--      que o líquido, alguém trocou a base ou aplicou o crédito no lado
--      errado. Idem para o adicional de imagem: o bruto é o líquido dividido
--      por (1 - piscof_ef), logo bruto >= líquido.
--
--   3. O adicional de imagem existe nos DOIS lados ou em NENHUM. É o ramo que
--      pega a leitura literal da §2.1 do documento: ela diz "Normal/Mono/ST
--      Recolhido: Valor Gerencial = Valor da última entrada", sem ressalva,
--      enquanto a §4 diz que o 80/20 é "como a Ingrax fatura QUALQUER item da
--      linha". 33 dos 230 SKUs INGRAX são modalidade NORMAL. Deixar o
--      adicional fora do valor gerencial neles colocaria 6 com custo gerencial
--      MAIOR que o valor gerencial (medido em 08/10/2026 — ex.: SKU 8592,
--      custo 343,52 contra valor 280,00). Os dois lados são gated pelo MESMO
--      `upper(fornecedor) = 'INGRAX'`, então divergir aqui é sempre defeito.
--
--   4. O par "últ / ger" aparece e some JUNTO nos dois lados:
--      VALOR_TOT_GERENCIAL é nulo exatamente quando CUSTO_TOT_s_VALOR é nulo.
--      As duas dependem do mesmo guarda-corpo (ST_SUBSTITUTO sem MVA ou com
--      nota zerada). Se uma sair nula e a outra não, a tela mostra "—" de um
--      lado e número do outro, no mesmo produto.
--
-- ⚠ O QUE **NÃO** É INVARIANTE, e não adianta tentar: VALOR_TOT_GERENCIAL >=
-- CUSTO_TOT_GERENCIAL. Parece óbvio — um é bruto de crédito, o outro líquido —
-- e é FALSO. A primeira linha do documento do Diretor explica: VL_ENT_UNIT e
-- CUSTO_ULT_ENT "vêm direto do Winthor, nenhum dos dois é calculado a partir
-- do outro". Sendo campos independentes, nada impede CUSTO_ULT_ENT >
-- VL_ENT_UNIT — e acontece em 24 SKUs hoje (SKU 7136: valor 0,00 contra custo
-- 140.000,00; SKU 3244: 410,00 contra 675,00). Este ramo chegou a ser escrito
-- assim em 08/10/2026 e reprovou nesses 24; a conclusão não foi relaxar a
-- tolerância, foi reconhecer que a afirmação estava errada.
--
-- Tolerância de 0,01: os ramos comparam reais, e arredondamento de centavo não
-- é regressão.

with custo as (
    select * from {{ ref('int_produto_custo') }}
),

fiscal as (
    select * from {{ ref('int_produto_fiscal') }}
)

select
    c.codigo,
    'soma nao fecha' as motivo
  from custo c
  join fiscal f on f.codigo = c.codigo
 where c.valor_tot_gerencial is not null
   and abs(c.valor_tot_gerencial
           - (f.vl_ent_unit + c.icms_st_bruto + c.valor_adicional_imagem)) > 0.01

union all

select
    c.codigo,
    'bruto menor que liquido' as motivo
  from custo c
 where (c.icms_st_bruto is not null
        and c.icms_st_s_valor is not null
        and c.icms_st_bruto < c.icms_st_s_valor - 0.01)
    or  c.valor_adicional_imagem < c.custo_adicional_imagem - 0.01

union all

select
    c.codigo,
    'adicional de imagem so num dos lados' as motivo
  from custo c
 where (c.valor_adicional_imagem  > 0 and c.custo_adicional_imagem <= 0)
    or (c.valor_adicional_imagem <= 0 and c.custo_adicional_imagem  > 0)

union all

select
    c.codigo,
    'par ult/ger nulo so num dos lados' as motivo
  from custo c
 where (c.valor_tot_gerencial is     null and c.custo_tot_s_valor is not null)
    or (c.valor_tot_gerencial is not null and c.custo_tot_s_valor is     null)
