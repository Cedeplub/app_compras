/** Formatação de número, em um lugar só.
 *
 *  Reais e percentuais aparecem em toda tela do sistema. Formatar caso a caso
 *  produz "R$ 1.234,5" numa tela e "1234.50" na outra, e quem confere o pedido
 *  não sabe se a diferença é de formato ou de valor.
 */

const nulo = (v) => v === null || v === undefined || Number.isNaN(v);

export const moeda = (v, casas = 2) =>
  nulo(v)
    ? "—"
    : v.toLocaleString("pt-BR", {
        style: "currency",
        currency: "BRL",
        minimumFractionDigits: casas,
        maximumFractionDigits: casas,
      });

export const numero = (v, casas = 0) =>
  nulo(v)
    ? "—"
    : v.toLocaleString("pt-BR", {
        minimumFractionDigits: casas,
        maximumFractionDigits: casas,
      });

/** Recebe fração (0,1049), mostra percentual (10,5%) — nunca o contrário.
 *  O banco guarda fração em todas as colunas de margem; multiplicar por 100 na
 *  tela e não no serviço mantém uma convenção só de ponta a ponta. */
export const percentual = (v, casas = 1) =>
  nulo(v) ? "—" : `${(v * 100).toLocaleString("pt-BR", {
    minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

/** Multiplicador puro (1,35x). MKP é razão, não percentual — o protótipo é
 *  explícito nisso (§5), e trocar os dois muda a decisão de preço. */
export const multiplicador = (v, casas = 2) =>
  nulo(v) ? "—" : `${numero(v, casas)}×`;

/** "62,2k" — usado só em KPI, onde o dígito exato não muda decisão nenhuma e
 *  o espaço é curto. Nunca em coluna de valor de pedido. */
export const compacto = (v) => {
  if (nulo(v)) return "—";
  if (Math.abs(v) >= 1_000_000) return `${numero(v / 1_000_000, 1)}M`;
  if (Math.abs(v) >= 1_000) return `${numero(v / 1_000, 1)}k`;
  return numero(v, 0);
};

export const data = (iso) => {
  if (!iso) return "—";
  const [ano, mes, dia] = iso.split("-");
  return `${dia}/${mes}/${ano.slice(2)}`;
};

/** "set/26" a partir de uma data ISO. Usado para rotular as barras do gráfico
 *  de venda com o nome do mês em vez de "M-1", "M-2", "M-3".
 *
 *  Recebe a data em partes e monta com `Date.UTC`, em vez de `new Date(iso)`:
 *  uma string "2026-09-01" é interpretada como meia-noite UTC, e num fuso a
 *  oeste de Greenwich isso volta um dia — o que faria setembro virar agosto no
 *  rótulo. Erro clássico, e aqui ele apareceria como o gráfico inteiro
 *  deslocado um mês, com os números certos.
 */
export function mesCurto(iso) {
  if (!iso) return "—";
  const [ano, mes] = iso.split("-").map(Number);
  const d = new Date(Date.UTC(ano, mes - 1, 1));
  const nome = d.toLocaleDateString("pt-BR", { month: "short", timeZone: "UTC" })
                .replace(".", "");
  return `${nome}/${String(ano).slice(2)}`;
}

/** A data ISO de N meses antes da referência. */
export function mesesAntes(iso, n) {
  if (!iso) return null;
  const [ano, mes] = iso.split("-").map(Number);
  const d = new Date(Date.UTC(ano, mes - 1 - n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-01`;
}
