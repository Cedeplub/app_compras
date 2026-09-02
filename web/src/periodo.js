/** Navegação no tempo: rótulos e intervalos.
 *
 * Porte de `rotuloPeriodo` e `SeletorPeriodo` (.jsx 267 e 380).
 *
 * ⚠ Duas diferenças de fundo em relação ao protótipo, ambas listadas em §8 como
 * limitação conhecida dele:
 *
 * 1. "Hoje" ali é `new Date(2026, 7, 28)` chumbado no arquivo. Aqui a
 *    referência vem de fora — do dado, não do relógio do dispositivo —, para
 *    que a tela nomeie o período que os números de fato representam.
 * 2. O seletor de período dele é decorativo: navega no tempo e o número não
 *    muda, porque os arrays são estáticos. Aqui cada função devolve um
 *    INTERVALO de datas, que vai para a consulta.
 *
 * Todas as contas usam UTC. `new Date("2026-09-01")` é lido como meia-noite
 * UTC; num fuso a oeste de Greenwich, `getMonth()` sobre isso devolve agosto —
 * e o período inteiro sai deslocado, com os números certos.
 */

const NOMES_MES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
                   "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

export const GRANULARIDADES = ["Dia", "Semana", "Mês", "Ano"];

const dataDeISO = (iso) => {
  const [a, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(a, m - 1, d));
};

const iso = (d) =>
  `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;

const curta = (d) =>
  `${String(d.getUTCDate()).padStart(2, "0")}/${String(d.getUTCMonth() + 1).padStart(2, "0")}`;

/** Segunda-feira da semana de `d`.
 *
 *  O protótipo usa `inicioDaSemana` sem dizer qual é o primeiro dia; adotamos
 *  SEGUNDA, que é a semana comercial brasileira. Domingo — o padrão de
 *  `getDay()` e de boa parte do Oracle — faria a "semana" do comprador começar
 *  num dia em que ninguém compra, e o total de segunda cairia na semana
 *  anterior. */
function inicioDaSemana(d) {
  const r = new Date(d);
  const diaDaSemana = (r.getUTCDay() + 6) % 7;   // 0 = segunda
  r.setUTCDate(r.getUTCDate() - diaDaSemana);
  return r;
}

/** O intervalo [de, ate] de um período, em ISO — o que a consulta recebe.
 *
 *  `ate` nunca passa da referência: pedir "esse mês" no dia 2 devolve 01–02, e
 *  não o mês inteiro. É isso que permite comparar período parcial com a fatia
 *  equivalente do ano anterior, em vez de comparar meio mês com um mês cheio e
 *  ler uma queda que não existe. */
export function intervalo(granularidade, offset, referenciaISO) {
  const hoje = dataDeISO(referenciaISO);
  let de, ate;

  if (granularidade === "Dia") {
    de = new Date(hoje);
    de.setUTCDate(hoje.getUTCDate() + offset);
    ate = new Date(de);
  } else if (granularidade === "Semana") {
    de = inicioDaSemana(hoje);
    de.setUTCDate(de.getUTCDate() + offset * 7);
    ate = new Date(de);
    ate.setUTCDate(de.getUTCDate() + 6);
  } else if (granularidade === "Mês") {
    de = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() + offset, 1));
    ate = new Date(Date.UTC(de.getUTCFullYear(), de.getUTCMonth() + 1, 0));
  } else {
    de = new Date(Date.UTC(hoje.getUTCFullYear() + offset, 0, 1));
    ate = new Date(Date.UTC(de.getUTCFullYear(), 11, 31));
  }

  // Nunca projeta para o futuro: o dado não existe lá.
  if (ate > hoje) ate = hoje;
  return { de: iso(de), ate: iso(ate), parcial: iso(ate) !== iso(fimNatural(granularidade, de)) };
}

function fimNatural(granularidade, de) {
  if (granularidade === "Dia") return de;
  if (granularidade === "Semana") {
    const f = new Date(de);
    f.setUTCDate(de.getUTCDate() + 6);
    return f;
  }
  if (granularidade === "Mês") return new Date(Date.UTC(de.getUTCFullYear(), de.getUTCMonth() + 1, 0));
  return new Date(Date.UTC(de.getUTCFullYear(), 11, 31));
}

/** O MESMO intervalo, um ano antes — inclusive quando parcial.
 *
 *  Comparar 1–2/set/2026 com setembro/2025 inteiro mostraria uma queda de 95%
 *  que é só o calendário. O protótipo descreve essa proporcionalidade em
 *  comentário, mas o número dele é fixo (§8). */
export function intervaloAnoAnterior(granularidade, offset, referenciaISO) {
  const { de, ate } = intervalo(granularidade, offset, referenciaISO);
  const menosUmAno = (s) => {
    const d = dataDeISO(s);
    return iso(new Date(Date.UTC(d.getUTCFullYear() - 1, d.getUTCMonth(), d.getUTCDate())));
  };
  return { de: menosUmAno(de), ate: menosUmAno(ate) };
}

export function rotuloPeriodo(granularidade, offset, referenciaISO) {
  const hoje = dataDeISO(referenciaISO);
  if (granularidade === "Dia") {
    if (offset === 0) return "Hoje";
    if (offset === -1) return "Ontem";
    const d = new Date(hoje);
    d.setUTCDate(hoje.getUTCDate() + offset);
    return curta(d);
  }
  if (granularidade === "Semana") {
    if (offset === 0) return "Essa semana";
    const { de, ate } = intervalo("Semana", offset, referenciaISO);
    return `${curta(dataDeISO(de))} a ${curta(dataDeISO(ate))}`;
  }
  if (granularidade === "Mês") {
    if (offset === 0) return "Esse mês";
    const d = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth() + offset, 1));
    return `${NOMES_MES[d.getUTCMonth()]}/${d.getUTCFullYear()}`;
  }
  if (offset === 0) return "Esse ano";
  return String(hoje.getUTCFullYear() + offset);
}

/** Como a comparação está sendo feita, em palavras.
 *
 *  Sem esta frase, um "−38%" num mês pela metade parece desabamento de vendas.
 *  Dizer "1 a 2 de setembro, contra o mesmo trecho de 2025" transforma o mesmo
 *  número em informação. */
export function rotuloComparacao(granularidade, offset, referenciaISO) {
  const { de, ate, parcial } = intervalo(granularidade, offset, referenciaISO);
  const a = dataDeISO(de), b = dataDeISO(ate);
  const trecho = de === ate ? curta(a) : `${curta(a)} a ${curta(b)}`;
  return parcial
    ? `${trecho} — comparado com o mesmo trecho de ${a.getUTCFullYear() - 1} (período em curso)`
    : `período completo — comparado com ${a.getUTCFullYear() - 1}`;
}

export const METRICAS = [
  { id: "faturamento", rotulo: "Faturamento", unidade: "R$" },
  { id: "peso", rotulo: "Peso", unidade: "kg" },
  { id: "litros", rotulo: "Litros", unidade: "L" },
  { id: "quantidade", rotulo: "Quantidade", unidade: "un" },
];
