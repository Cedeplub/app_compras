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
    return "Margem acima do teto do cenário — nenhum preço produz esta margem";
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
