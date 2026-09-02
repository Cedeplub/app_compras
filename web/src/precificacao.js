/** As contas que a tela refaz a cada tecla digitada.
 *
 * Por que existe JavaScript calculando margem, se a regra de ouro do projeto é
 * "a planilha é o gabarito e o dbt é quem calcula": porque estas contas são
 * SIMULAÇÃO, não verdade gravada. O comprador digita um preço que ainda não
 * existe em lugar nenhum e precisa ver a margem resultante no mesmo instante —
 * ir ao servidor a cada tecla daria uma tela lenta e uma consulta por dígito.
 *
 * O que impede isso de virar uma segunda fonte da verdade: **nenhum número aqui
 * é constante escrita à mão**. Custo e alíquota vêm do cenário que a API
 * devolve (os mesmos que `int_produto_preco_sugerido.sql` usou para calcular o
 * preço sugerido), e comissão e fator de prazo vêm de `/api/parametros`, que lê
 * COMPRAS_PARAMETRO. O protótipo chumba os três no arquivo (§4.6); com duas
 * cópias, tela e banco calculariam margens diferentes sem nenhum aviso.
 *
 * Prova de que a fórmula é a mesma: aplicando-a ao preço SUGERIDO de qualquer
 * cenário, a margem resultante é a margem alvo daquele produto.
 */

const nulo = (v) => v === null || v === undefined || Number.isNaN(v);

/** MKP = preço ÷ custo. Multiplicador puro, não percentual — trocar os dois
 *  muda a decisão de preço (PROTOTIPO.md §5). */
export function calcMKP(preco, custo) {
  if (nulo(preco) || nulo(custo) || custo <= 0) return null;
  return preco / custo;
}

/** Margem de contribuição, em FRAÇÃO (0,205 = 20,5%).
 *
 *   margem = 1 − PIS/COFINS(saída) − comissão − ICMS_efetivo(saída) − custo/preço
 *
 * O ICMS é o do CENÁRIO selecionado. O protótipo usa sempre `icmsEfSemReducao`
 * para o preço digitado, mesmo quando o cenário escolhido é "Oficial" — o que
 * põe lado a lado, na mesma linha, uma sugestão calculada com uma alíquota e
 * uma margem calculada com outra. Aqui os dois usam a mesma.
 */
export function calcMargem(preco, custo, { pisCofins, comissao, icmsEf }) {
  if (nulo(preco) || nulo(custo) || preco <= 0) return null;
  if (nulo(pisCofins) || nulo(comissao) || nulo(icmsEf)) return null;
  return 1 - pisCofins - comissao - icmsEf - custo / preco;
}

/** Preço a prazo = à vista × fator. O fator vem da tabela de vendas do Winthor,
 *  definido pela diretoria — não é juros calculado aqui (PROTOTIPO.md §5). */
export const aPrazo = (avista, fator) =>
  nulo(avista) || nulo(fator) ? null : avista * fator;

/** Valor da NF reconstruído a partir do custo, desfazendo os créditos.
 *
 *   valor = custo / ((1 − crédito ICMS) × (1 − crédito PIS/COFINS))
 *
 * A tela nunca lê um "valor NF" de campo próprio: reconstrói de trás para
 * frente, como o protótipo (§5). Vale saber por quê — o custo é que é o número
 * validado contra a planilha; o valor bruto é leitura de apoio.
 */
export function valorAntesDoCredito(custo, creditoICMS, creditoPisCofins) {
  if (nulo(custo)) return null;
  const den = (1 - (creditoICMS ?? 0)) * (1 - (creditoPisCofins ?? 0));
  return den > 0 ? custo / den : null;
}

/** O cenário escolhido, ou — quando ele não existe nesta praça — o cenário REAL
 *  do produto. Varejo não tem "Oficial" (a redução é exclusiva das filiais
 *  02/09), então escolher Oficial e olhar o varejo cai aqui. */
export function cenarioVisivel(cenarios, id) {
  if (!cenarios?.length) return null;
  return cenarios.find((c) => c.id === id)
      ?? cenarios.find((c) => c.real)
      ?? cenarios[0];
}

/** Tudo que um bloco de preço precisa mostrar, para atacado ou varejo. */
export function simular({ produto, cenarios, cenarioSel, precoAtual, precoDigitado,
                          fatorPrazo, parametros }) {
  const cen = cenarioVisivel(cenarios, cenarioSel);
  const existeNestaPraca = cenarios?.some((c) => c.id === cenarioSel) ?? false;
  const base = {
    pisCofins: produto.pisCofinsEfetivo,
    comissao: parametros?.comissao,
    icmsEf: cen?.icmsEf,
  };
  const custo = cen?.custo ?? null;
  const novo = Number(String(precoDigitado ?? "").replace(",", ".")) || 0;
  const prazo = novo > 0 ? aPrazo(novo, fatorPrazo) : null;

  return {
    cenario: cen,
    existeNestaPraca,
    custo,
    mkpAtual: calcMKP(precoAtual, custo),
    margemAtual: cen?.margemAtual ?? null,
    // `existeNestaPraca` separa "o cenário não se aplica aqui" de "o modelo não
    // calculou". A tela mostra "—" no primeiro caso e não finge um número.
    sugerido: existeNestaPraca ? cen?.pvSugeridoAV ?? null : null,
    sugeridoPrazo: existeNestaPraca ? cen?.pvSugeridoAP ?? null : null,
    novo: novo > 0 ? novo : null,
    mkpNovo: novo > 0 ? calcMKP(novo, custo) : null,
    margemNova: novo > 0 ? calcMargem(novo, custo, base) : null,
    prazo,
    mkpPrazo: prazo ? calcMKP(prazo, custo) : null,
    margemPrazo: prazo ? calcMargem(prazo, custo, base) : null,
  };
}
