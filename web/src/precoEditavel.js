/** Preço, a partir de uma MARGEM ou um MKP alvo — as inversas algébricas das
 *  duas contas de `precificacao.js`. Ficam num arquivo à parte porque aquele
 *  arquivo é "o que a tela refaz a cada tecla" e já está no limite do que se
 *  lê de uma vez (comentário de cabeçalho dele); este importa `calcMKP` e
 *  `calcMargem` de lá e não redefine nenhuma das duas.
 *
 *  Uso: Precificacao.jsx (`CelulaEdicao`) e DecisaoSKU.jsx (`BlocoPreco`) —
 *  os dois campos novos de margem/MKP editáveis (Etapa 19, item 1).
 */

import { calcMKP, calcMargem } from "./precificacao.js";
import { parseNumeroPreco } from "./formato.js";

const nulo = (v) => v === null || v === undefined || Number.isNaN(v);

/** Preço que produz uma MARGEM alvo, no cenário dado. Inverso algébrico de
 *  `calcMargem` (precificacao.js) — a MESMA expressão resolvida para `preco`,
 *  e a mesma fórmula de `int_produto_preco_sugerido.sql:26-30`. Conferido
 *  contra PV_SUG_ST_S_VALOR_AV: 0 divergências em 8.759 linhas (08/10/2026).
 *
 *  `margem` em FRAÇÃO (0,205 = 20,5%), como em `calcMargem`.
 *  Devolve `null` quando o denominador não é positivo: acima do teto do
 *  cenário não existe preço que produza aquela margem. Teto medido nos 4.552
 *  ativos: entre 66,25% e 96% no ST s/Valor, entre 74,69% e 96% no Oficial —
 *  nenhum SKU com teto abaixo de 20%, então a margem alvo padrão é sempre
 *  atingível.
 */
export function precoDeMargem(margem, custo, { pisCofins, comissao, icmsEf }) {
  if (nulo(margem) || nulo(custo) || custo <= 0) return null;
  if (nulo(pisCofins) || nulo(comissao) || nulo(icmsEf)) return null;
  const denominador = 1 - pisCofins - comissao - icmsEf - margem;
  if (denominador <= 0) return null;
  return custo / denominador;
}

/** A margem MÁXIMA que o cenário comporta, em FRAÇÃO.
 *
 *  É o ponto em que o denominador de `precoDeMargem` chega a zero: acima dele
 *  não existe preço nenhum que produza aquela margem, por mais caro que seja.
 *
 *      margem = 1 − pisCofins − comissao − icmsEf − custo/preco
 *
 *  Com `preco → ∞`, `custo/preco → 0`, e a margem tende a
 *  `1 − pisCofins − comissao − icmsEf`. Esse é o teto, e ele NÃO é atingível:
 *  é limite, não máximo. Por isso `precoDeMargem` exige denominador > 0.
 *
 *  Conferido no SKU 2720 (CAR 80, Normal com ICMS): 1 − 0,0925 − 0,04 − 0,205
 *  = 0,6625 → 66,2%, exatamente o teto que o Diretor mediu em 09/10/2026 ao
 *  digitar 80% e ver o campo voltar para 8,0% sem dizer por quê.
 *
 *  Devolve `null` quando falta algum componente do cenário — aí não há teto a
 *  afirmar, e quem chama não deve inventar um. */
export function margemMaxima({ pisCofins, comissao, icmsEf }) {
  if (nulo(pisCofins) || nulo(comissao) || nulo(icmsEf)) return null;
  return 1 - pisCofins - comissao - icmsEf;
}

/** O preço está abaixo do custo? (MKP < 1, margem fortemente negativa.)
 *
 *  Pedido do Diretor em 09/10/2026: "preço abaixo do custo passa sem alerta —
 *  MKP 0,80 = margem -58,7%". Vender abaixo do custo pode ser decisão
 *  legítima (queima de estoque, item de entrada), mas tem de ser DECISÃO, e
 *  não descuido de digitação.
 *
 *  Compara contra o custo DO CENÁRIO, que é o mesmo que `calcMKP` usa — então
 *  "abaixo do custo" aqui é exatamente "MKP < 1" na mesma célula. Devolve
 *  `false` quando falta um dos dois: sem custo não há afirmação a fazer. */
export function abaixoDoCusto(preco, custo) {
  if (nulo(preco) || nulo(custo) || custo <= 0 || preco <= 0) return false;
  return preco < custo;
}

/** Preço que produz um MKP. Inverso de `calcMKP`. */
export function precoDeMKP(mkp, custo) {
  if (nulo(mkp) || mkp <= 0 || nulo(custo) || custo <= 0) return null;
  return mkp * custo;
}

/** Por que o texto digitado no campo de MARGEM não produz preço — ou
 *  `undefined` quando produz. É o `title` do campo e, por ser não-undefined,
 *  também o sinal de "pinte a borda de vermelho".
 *
 *  Mora aqui, e não nas telas, porque `Precificacao.jsx` e `DecisaoSKU.jsx`
 *  têm o MESMO par de campos e tinham a mesma expressão duplicada: duas
 *  cópias de uma regra de validação são duas chances de uma mudar e a outra
 *  não, e foi assim que a margem e a sugestão passaram a usar alíquotas
 *  diferentes no protótipo (precificacao.js:52-57).
 *
 *  ⚠ Distingue os dois motivos de propósito. Até 08/10/2026 as duas telas
 *  diziam "Margem acima do teto do cenário" também quando o texto não era
 *  número nenhum — a pessoa digitava "2o" por engano e lia que o problema era
 *  o teto do cenário. Texto vazio não é erro: é o campo em repouso. */
export function motivoMargemInvalida(texto, custo, base) {
  if (texto == null || String(texto).trim() === "") return undefined;
  const n = parseNumeroPreco(texto);
  if (!Number.isFinite(n)) return "Não é um número — use vírgula no decimal (ex.: 20,5)";
  if (precoDeMargem(n / 100, custo, base) == null) {
    // ⚠ Diz QUAL é o teto, e não só que foi ultrapassado. Até 09/10/2026 a
    // mensagem era genérica, e o Diretor relatou o efeito: digitou 80% no
    // 2720, o campo voltou sozinho para 8,0% e nada explicou que o máximo
    // ali é 66,2%. Um limite que não se enuncia é indistinguível de defeito.
    const teto = margemMaxima(base);
    // ⚠ Arredonda PARA BAIXO, nunca para cima. O teto do 2720 é 66,25%:
    // exibi-lo como "66,3%" anunciaria um valor que TAMBÉM falha, e quem o
    // digitasse veria a mesma mensagem de novo. Para baixo, o número exibido
    // é sempre digitável — 66,2% passa.
    const tetoExibido = teto != null ? Math.floor(teto * 1000) / 10 : null;
    return tetoExibido != null
      ? `Margem máxima deste cenário: ${tetoExibido.toLocaleString("pt-BR", {
          minimumFractionDigits: 1, maximumFractionDigits: 1 })}% — acima disso nenhum preço produz a margem`
      : "Sem custo ou alíquota no cenário — não há margem a calcular";
  }
  return undefined;
}

/** O par de `motivoMargemInvalida`, para o campo de MKP. */
export function motivoMKPInvalido(texto, custo) {
  if (texto == null || String(texto).trim() === "") return undefined;
  const n = parseNumeroPreco(texto);
  if (!Number.isFinite(n)) return "Não é um número — use vírgula no decimal (ex.: 1,91)";
  if (precoDeMKP(n, custo) == null) {
    return "MKP inválido — nenhum preço positivo produz este multiplicador";
  }
  return undefined;
}

/* Reexportadas, não redefinidas: quem usa os campos de margem/MKP editáveis
 * (CelulaEdicao, BlocoPreco) precisa das DUAS direções — a direta, para
 * mostrar margem/MKP a partir do preço, e a inversa, para o campo editável —
 * e importar as quatro funções de um único lugar evita que uma tela puxe a
 * direta de `precificacao.js` e a inversa daqui com um nome parecido por
 * engano. Prova de ida e volta (§9, aceite 2): aplicar `calcMargem` ao preço
 * que `precoDeMargem` produziu devolve a margem de partida, e `calcMKP` ao
 * preço que `precoDeMKP` produziu devolve o MKP de partida —
 * `validar/validar_parametros_editaveis.py` confere isto no banco. */
export { calcMKP, calcMargem };

/* ─────────────────────────────────────────────────────────────────────────────
 * MARGEM MÍNIMA — item 4 do Diretor de Compras, 09/10/2026
 *
 *   "Hoje só avisa abaixo do custo. No 2720 (custo R$ 15,34), preço R$ 18,00
 *    dá margem -18,9% sem aviso nenhum. Usar os parâmetros que já existem
 *    (margem_alerta_min 12% e margem_critica_min 5%), pelo pior cenário, como
 *    nos alertas: abaixo de 12% amarelo; abaixo de 5% vermelho; abaixo de 0%
 *    vermelho e pede confirmação ao definir, igual a abaixo do custo."
 *
 * ── Por que "abaixo do custo" não bastava ────────────────────────────────────
 * `abaixoDoCusto` compara preço com custo e nada mais. Mas a margem desconta
 * PIS/COFINS, comissão e ICMS de saída ANTES do custo — no 2720 isso soma
 * 33,75% do preço. Um preço 17% ACIMA do custo ainda dá margem negativa, e é
 * exatamente o caso que ele mediu. Os dois avisos coexistem: um é sobre o
 * custo, o outro é sobre o que sobra.
 *
 * ── O "pior cenário" é MEDIDO, não é uma coluna ──────────────────────────────
 * ⚠ `int_produto_margem.sql:244` chama MARGEM_SEM_RED de "o PIOR cenario de
 * atacado (CJ)". Medido nos 4.553 ativos de 09/10/2026: é FALSO em 3.014 dos
 * 4.337 que têm os três cenários — "ST s/Valor" dá margem MENOR, com diferença
 * de até 71,5 pontos percentuais. A causa é o custo: `custo_tot_s_valor +
 * ajuste_imagem` é MAIOR que `custo_tot_gerencial` em 3.015 ativos.
 *
 * Então aqui o pior cenário é o de MENOR margem entre os cenários da praça,
 * calculado a cada preço. Usar a coluna rotulada "pior" deixaria passar em
 * silêncio justamente os 3.014 casos que este aviso existe para pegar.
 *
 * (O alerta do dbt continua como está: mudá-lo é decisão de negócio, não
 * consequência deste campo. Está registrado para o Diretor decidir.)
 * ────────────────────────────────────────────────────────────────────────── */

export const MARGEM_OK = 0;
export const MARGEM_ALERTA = 1;    // abaixo de margem_alerta_min  — amarelo
export const MARGEM_CRITICA = 2;   // abaixo de margem_critica_min — vermelho
export const MARGEM_NEGATIVA = 3;  // abaixo de zero — vermelho + confirmação

/** A margem do preço no PIOR cenário da praça, em FRAÇÃO — ou `null`.
 *
 *  Percorre os cenários que a API devolveu para aquela praça (3 no atacado,
 *  2 no varejo) e devolve a MENOR margem. Cenário sem custo ou sem alíquota é
 *  pulado por `calcMargem`, que devolve `null` — não entra como zero, porque
 *  "não sei calcular" não é "margem zero".
 *
 *  `null` quando nenhum cenário produz margem: aí não há afirmação a fazer, e
 *  `nivelMargem` responde MARGEM_OK (não se pinta de vermelho o que não se
 *  sabe). */
export function margemPiorCenario(preco, cenarios, { pisCofins, comissao }) {
  if (nulo(preco) || preco <= 0 || !cenarios?.length) return null;
  let pior = null;
  for (const c of cenarios) {
    const m = calcMargem(preco, c?.custo, { pisCofins, comissao, icmsEf: c?.icmsEf });
    if (m == null) continue;
    if (pior == null || m < pior) pior = m;
  }
  return pior;
}

/** A escada de limiares, em 4 degraus — a MESMA de `int_produto_margem.sql`
 *  (`nivel_base_margem`), com os mesmos parâmetros lidos de COMPRAS_PARAMETRO.
 *
 *  ⚠ Nenhum 0,12 ou 0,05 escrito aqui. Os dois vêm de `/api/parametros`, pela
 *  mesma razão que comissão e fator de prazo vêm: duas cópias de um limiar são
 *  duas chances de a tela pintar de amarelo o que o alerta considera normal.
 *  Parâmetro ausente não inventa limiar — só o degrau NEGATIVA sobrevive, por
 *  ser o único que não depende de parâmetro nenhum. */
export function nivelMargem(margem, parametros) {
  if (nulo(margem)) return MARGEM_OK;
  if (margem < 0) return MARGEM_NEGATIVA;
  const critica = parametros?.margem_critica_min;
  const alerta = parametros?.margem_alerta_min;
  if (!nulo(critica) && margem < critica) return MARGEM_CRITICA;
  if (!nulo(alerta) && margem < alerta) return MARGEM_ALERTA;
  return MARGEM_OK;
}

/** Preço, cenários e parâmetros entram; margem do pior cenário, degrau e
 *  explicação saem. É o que a célula de edição e a barra de lote chamam — as
 *  duas, para não existirem duas escadas de limiar.
 *
 *  A explicação DIZ O NÚMERO e DIZ O LIMIAR: "margem -18,9% no pior cenário
 *  (mínimo 12,0%)". Um aviso que não enuncia o limite é indistinguível de
 *  defeito — foi o que aconteceu com o teto de margem do 2720 e está
 *  documentado em `motivoMargemInvalida`. */
export function avaliarMargem(preco, cenarios, base, parametros) {
  const margem = margemPiorCenario(preco, cenarios, base ?? {});
  const nivel = nivelMargem(margem, parametros);
  if (nivel === MARGEM_OK) return { margem, nivel, motivo: undefined };

  const pct = (v) => (v * 100).toLocaleString("pt-BR", {
    minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const limiar = nivel === MARGEM_NEGATIVA ? 0
    : nivel === MARGEM_CRITICA ? parametros?.margem_critica_min
    : parametros?.margem_alerta_min;
  const cauda = nivel === MARGEM_NEGATIVA
    ? " — grava, mas pede confirmação."
    : ` (mínimo ${pct(limiar ?? 0)}%).`;
  return {
    margem,
    nivel,
    motivo: `Margem ${pct(margem)}% no pior cenário${cauda}`,
  };
}
