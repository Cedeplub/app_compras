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

/** Contrato do campo EDITÁVEL de preço (Precificacao, DecisaoSKU,
 *  LotePrecoDetalhe): duas casas, vírgula decimal, **nunca** ponto de milhar.
 *
 *  `numero(v, 2)` (acima) usa `toLocaleString`, que a partir de R$ 1.000 insere
 *  ponto de milhar — "1.234,56". Nenhum parser deste projeto lê esse formato de
 *  volta: `Number(String(v).replace(",", "."))` vira "1.234.56" (dois pontos)
 *  → `NaN` → `|| 0` em silêncio. Medido no banco: 254 produtos ativos com
 *  PV_ATACADO ≥ 1.000 — cada um deles nascia com o campo de edição quebrado
 *  antes desta função existir. Por isso o campo de preço nunca usa `numero()`
 *  nem `moeda()` para se formatar; usa esta função, e só ela.
 *
 *  `parseNumeroPreco` (abaixo) é o par: lê de volta qualquer coisa que esta
 *  função produz, e mais alguns formatos plausíveis de colar/digitar.
 */
export const paraCampoPreco = (v) =>
  nulo(v) ? "" : v.toFixed(2).replace(".", ",");

/** O par de `paraCampoPreco`. Lê o texto de um campo de preço de volta a
 *  número, aceitando os formatos que uma pessoa realmente digita ou cola:
 *
 *    "1234,56"   → 1234.56  (o formato que este campo produz)
 *    "1.234,56"  → 1234.56  (pt-BR completo, ex.: colado de outro relatório)
 *    "1234.56"   → 1234.56  (en-US — o teclado numérico de alguns celulares
 *                            produz ponto mesmo com o SO em pt-BR)
 *    "1.234"     → 1234     (milhar sem decimal — 3 dígitos depois do único
 *                            ponto; ninguém digita R$ 1,234 de propósito)
 *    "0,99"      → 0.99
 *    ""          → null     ("apagou" — ainda não decidiu, distinto de zero)
 *    "abc"       → NaN      (não é número — quem chama decide o que fazer)
 *
 *  Zero é preço inválido (uma decisão de preço não pode ser R$ 0) e vazio é
 *  "não decidiu ainda" — os dois nunca podem colapsar no mesmo retorno, ou o
 *  chamador não consegue distinguir "apagou o campo" de "digitou zero".
 */
export function parseNumeroPreco(texto) {
  if (texto == null) return null;
  const t = String(texto).trim();
  if (t === "") return null;

  const pontos = (t.match(/\./g) || []).length;
  const virgulas = (t.match(/,/g) || []).length;
  if (virgulas > 1) return NaN; // "1,23,4" não é número em formato nenhum

  let normalizado;
  if (virgulas === 1) {
    // Havendo vírgula, ela é sempre o decimal — ponto(s), se houver, são milhar.
    normalizado = t.replace(/\./g, "").replace(",", ".");
  } else if (pontos > 1) {
    // Vários pontos, nenhuma vírgula: só podem ser milhares ("1.234.567").
    normalizado = t.replace(/\./g, "");
  } else if (pontos === 1) {
    const depois = t.split(".")[1] ?? "";
    normalizado = depois.length === 3 ? t.replace(".", "") : t; // milhar × decimal en-US
  } else {
    normalizado = t;
  }
  const n = Number(normalizado);
  return Number.isFinite(n) ? n : NaN;
}

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

/** Quantidade de estoque em unidade de exibição (EST_DISP já vem dividido por
 *  FATOR_EXIBICAO). Inteiro sem casas; fracionário com 2 — 1 litro solto de uma
 *  caixa de 12 vale 0,08 e não pode ser impresso como "0" numa linha que o
 *  filtro classificou como "com estoque". 10 SKUs ativos hoje, o menor 0,0833. */
export const quantidadeEstoque = (v) =>
  v == null ? "—" : numero(v, Number.isInteger(v) ? 0 : 2);

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

/** "hoje às 06:05" / "ontem às 06:05" / "09/09 às 06:05" — idade e hora de um
 *  timestamp de CARGA (quando o dbt terminou de rodar), a partir de um ISO
 *  local como `estado.fim` (`GET /api/atualizacao`) ou `atualizacao.fim` de um
 *  lote de preço. Compartilhado entre o carimbo do cabeçalho
 *  (`componentes/Cabecalho.jsx`) e a conferência de aplicação de preço
 *  (`lotePrecoStatus.textoConferencia`) — as duas frases falam da idade da
 *  MESMA carga e não podiam divergir de formato (uma dizendo "há 1 dia", a
 *  outra "ontem", por exemplo).
 *
 *  Diferente do resto deste arquivo — que trabalha em UTC para datas PURAS
 *  (`mesCurto`, por exemplo, documenta por quê) — este ISO tem hora de
 *  verdade e chega SEM sufixo de fuso (ex. "2026-09-11T06:05:12"); `new
 *  Date()` o lê como hora LOCAL do navegador, que é o comportamento certo
 *  aqui: servidor e navegador estão na mesma casa (Brasil).
 *
 *  `relativo: true` quando o texto já é "hoje"/"ontem" (não pede "em" antes,
 *  ex. "Atualizado hoje às 06:05"); `false` quando é uma data explícita
 *  (DD/MM), que pede "em" na frase do cabeçalho ("Atualizado em 09/09 às
 *  06:05") — mas não na da conferência, que já tem seu próprio "de"
 *  ("conferido com os dados de 09/09 às 06:05"). Por isso a preposição não
 *  vem embutida aqui: cada chamador decide a sua.
 */
export function dataHoraCarga(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;

  const agora = new Date();
  const meiaNoite = (dt) => new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime();
  const dias = Math.round((meiaNoite(agora) - meiaNoite(d)) / 86_400_000);

  const hora = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

  if (dias === 0) return { texto: `hoje às ${hora}`, curto: hora, relativo: true };
  if (dias === 1) return { texto: `ontem às ${hora}`, curto: `ontem ${hora}`, relativo: true };
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  return { texto: `${dd}/${mm} às ${hora}`, curto: `${dd}/${mm} ${hora}`, relativo: false };
}

/** A data ISO de N meses antes da referência. */
export function mesesAntes(iso, n) {
  if (!iso) return null;
  const [ano, mes] = iso.split("-").map(Number);
  const d = new Date(Date.UTC(ano, mes - 1 - n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-01`;
}
