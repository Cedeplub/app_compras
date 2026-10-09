import { useState } from "react";
import { Link } from "react-router-dom";
import { ChevronDown, Filter, Lock } from "lucide-react";
import CabecalhoOrdenavel, { ordenarLista } from "./CabecalhoOrdenavel.jsx";
import FiltroEstoque from "./FiltroEstoque.jsx";
import FiltroUltimaEntrada from "./FiltroUltimaEntrada.jsx";
import { ClasseChip } from "./Basicos.jsx";
import { dataCompleta, mesCurto, mesesAntes, moeda, numero, parseNumeroPreco, quantidadeEstoque } from "../formato.js";
import { coberturaComPedido } from "../cobertura.js";

/* Catálogo de produtos para montar pedido — os filtros e a tabela larga que
 * eram locais de `telas/Pedidos.jsx` (§2.4 do protótipo).
 *
 * POR QUE SAIU DA TELA: a Etapa 17 (pedido do Diretor, 29/09/2026) pede o
 * MESMO contexto de decisão dentro da edição de um pedido salvo — estoque,
 * cobertura, venda dos 4 meses, tendência, sugestão. Duas cópias da mesma
 * tabela divergiriam na primeira coluna que mudasse de um lado só; este
 * arquivo existe para que só haja UMA.
 *
 * ⚠ REGRA AO MEXER AQUI: o que muda neste arquivo muda as DUAS telas
 * (`/pedidos` e a edição em `PedidoDetalhe.jsx`). Mudança que só faz sentido
 * numa delas entra por PROP, não por `if` de tela — não existe nem deve
 * existir um "se for a tela X" aqui dentro.
 *
 * O que NÃO veio junto, de propósito, e continua em `telas/Pedidos.jsx`: o
 * carrinho global (`contexto/carrinho.jsx`), a barra flutuante de totais e o
 * salvar. Aqui a quantidade digitada é só um par (`valor`, `aoTrocar`) por
 * linha — quem consome decide se isso vai para o carrinho global (o que
 * `/pedidos` faz) ou para um estado local que vira `PUT` por item (o que a
 * edição de pedido faz). Foi o que permitiu compartilhar sem fundir os dois
 * caminhos de escrita.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";
const VERDE = "#15803D";
const CINZA = "#6B7280";
// Âmbar = "você mexeu nisto e ainda não confirmou". Mesmo tom que a tela já
// usava no aviso "já está no pedido", para alteração pendente ter UMA cor só.
const AMBAR = "#B98A2E";

/* Quantas colunas de MÊS esta tabela tem. Cabeçalho e células saem daqui, e
 * não do tamanho do que a API mandou — foi assim que ela quebrou em
 * 09/10/2026.
 *
 * A tabela de cima de `PedidoDetalhe` ("No pedido") busca cada item pela rota
 * de DETALHE (`/api/produtos/{codigo}`), enquanto a de baixo vem da LISTAGEM.
 * Os dois contratos eram idênticos até a ampliação do histórico: a rota de
 * detalhe passou a trazer 13 meses (mês corrente + 12 fechados, para o
 * gráfico da Decisão do SKU poder mostrar a janela inteira da média) e a
 * listagem continuou com 4. Mapear o array direto fazia a linha render 13
 * células contra um cabeçalho de 4, e a tabela inteira saía torta.
 *
 * Com o comprimento fixo aqui, o número de colunas é propriedade da TABELA.
 * Mandar mais meses deixa de ser capaz de desalinhá-la, e mandar menos
 * devolve "—" na célula em vez de sumir com ela. */
const MESES_CATALOGO = 4;

const F_EST = "#EFF6FF";
const F_ESTPED = "#DBEAFE";
const F_VENDA = "#F0FDF4";
const F_MEDIA = "#DCFCE7";
const F_COB = "#FAF5FF";

// `dir` espelha a direção padrão de cada coluna em `app/servicos/produto.py`
// (`ORDENACOES`) — mesmo motivo de Precificacao.jsx: o dropdown e o clique no
// cabeçalho da coluna escrevem o mesmo estado (§3.3), nunca direções diferentes.
// Não exportada: só o `<select>` "Ordenar por" daqui de dentro a consome.
// `Alertas.jsx` e `Precificacao.jsx` têm listas próprias, com outras opções.
const ORDENACOES = [
  { id: "cobertura", rotulo: "Cobertura — menor primeiro", dir: "asc" },
  { id: "giro", rotulo: "Mais dias sem venda", dir: "desc" },
  { id: "valor", rotulo: "Maior valor de estoque", dir: "desc" },
  { id: "descricao", rotulo: "Nome (A → Z)", dir: "asc" },
];

// Ajuste 2 do revisor (13/09): o cabeçalho clicável e este `<select>`
// escrevem no MESMO estado (§3.3), mas as colunas que só têm
// `CabecalhoOrdenavel` — sem entrada aqui em cima — deixavam o `<select>`
// SEM `<option>` correspondente, e um `<select>` sem opção casada com seu
// `value` renderiza em branco: parece defeito, não "ordenado por outra
// coisa". Rótulo sintético "Coluna: <nome>", pelo mesmo nome que a coluna
// mostra no cabeçalho da tabela — para o dropdown nunca ficar mudo.
const ROTULO_COLUNA = {
  codigo: "Código",
  estoque: "Estoque",
  pendente: "Pend.",
  estPedido: "EST+PED",
  ultimaEntrada: "Últ. entrada",
  vendaAtual: "Venda do mês",
  mediaVenda: "Média",
  ultimaSaida: "Últ. saída",
  tendencia: "Tend.",
  valorNfSemFrete: "Valor NF (s/ frete)",
};

// Molde dos filtros persistidos. `/pedidos` e a edição de pedido guardam em
// CHAVES DIFERENTES de sessionStorage (ver cada chamador) — filtrar o catálogo
// dentro de um pedido não pode mexer no que a pessoa deixou montado em
// `/pedidos`, e vice-versa.
export const FILTROS_PADRAO = {
  departamento: "", comprador: "", status: "Ativo", estoque: "",
  busca: "", pagina: 1, dtUltEntDe: "", dtUltEntAte: "",
};

export const POR_PAGINA = 50;

/* ------------------------------------------------- ordenação no cliente --- */

/** Mesma chave de coluna que o servidor usa (`produto.py:ORDENACOES`), mapeada
 *  para o campo do produto no contrato. Serve à lista que NÃO é paginada pelo
 *  servidor — os itens de um pedido, na visão "só os do pedido" da edição.
 *
 *  ⚠ Só existe para essa lista curta. Lista paginada continua ordenando no
 *  SERVIDOR: ordenar no cliente ordenaria apenas a página atual, e a pior
 *  cobertura do catálogo continuaria na página 7 enquanto a coluna diz
 *  "ordenado por cobertura" (o defeito que `CabecalhoOrdenavel` documenta). */
const CAMPO_DA_COLUNA = {
  codigo: (p) => p.codigo,
  descricao: (p) => p.nome,
  estoque: (p) => p.estDisp,
  pendente: (p) => p.pendente,
  estPedido: (p) => p.estPend,
  ultimaEntrada: (p) => p.ultimaEntrada,
  valorNfSemFrete: (p) => p.precoEntradaSemFrete,
  vendaAtual: (p) => p.vendaHistorico?.quantidade?.[0],
  mediaVenda: (p) => p.mediaJanela,
  ultimaSaida: (p) => p.ultimaSaida,
  cobertura: (p) => p.mesesCobertura,
  tendencia: (p) => p.tendPct,
  giro: (p) => p.diasSemVenda,
  valor: (p) => p.valorEstoque,
};

export function ordenarCatalogo(itens, ordenar, dir) {
  const extrator = CAMPO_DA_COLUNA[ordenar] ?? CAMPO_DA_COLUNA.codigo;
  return ordenarLista(itens, extrator, dir);
}

/* --------------------------------------------- cobertura alvo simulada --- */

/** `SUG_COBERTURA`, recalculada no cliente só quando a pessoa MEXEU no
 *  controle de cobertura alvo simulada — com `coberturaAlvoSimulada == null`
 *  (estado inicial, e o que "voltar ao alvo do modelo" restaura), a sugestão
 *  é `p.sugCobertura`, o número do SERVIDOR, byte a byte (§4.4 do prompt;
 *  Etapa 19, item 2). Mesma fórmula de `int_produto_demanda.sql:277`:
 *
 *    greatest(0, round(media_janela * cobertura_alvo - est_pend, 0))
 *
 *  `Math.round` é seguro aqui: o Oracle arredonda "metade para longe do
 *  zero" e o JS "metade para cima" — os dois só divergem em valor NEGATIVO,
 *  que o `Math.max(0, …)` já elimina (§4.1 do prompt).
 *
 *  ⚠ CONTEXTO.md regra 6 / `cobertura.js`: `mediaJanela` e `estPend` já
 *  chegam da API em unidade de EXIBIÇÃO (divididos por FATOR_EXIBICAO) — a
 *  mesma unidade do alvo (meses, sem unidade de produto) e do campo de
 *  quantidade. Multiplicar por `fatorExibicao` aqui seria recriar o defeito
 *  que a Etapa 18 removeu de `coberturaComPedido`. */
export function sugestaoCobertura(p, coberturaAlvoSimulada) {
  if (coberturaAlvoSimulada == null) return p.sugCobertura;
  if (!p.mediaJanela) return 0;
  const bruta = Math.max(0, Math.round(p.mediaJanela * coberturaAlvoSimulada - (p.estPend || 0)));
  return paraMultiploDaCaixa(bruta, p);
}

/** Sobe `qtd` para o múltiplo da caixa de compra, na unidade de EXIBIÇÃO.
 *
 *  Pedido do Diretor em 09/10/2026: "a sugestão não arredonda para a caixa —
 *  370 de 805 sugestões; o 109 pede 5.771 unidades de um item que vem em
 *  caixa 24x1". Sugerir um número que não se pode comprar faz a pessoa
 *  refazer a conta à mão toda vez.
 *
 *  A caixa, em unidade de exibição, é `embalCompra / fatorExibicao`:
 *    * item MASTER (fator = embalCompra) → dá 1, e qualquer inteiro já é
 *      múltiplo. O arredondamento não mexe em nada, que é o certo;
 *    * item em unidade (fator 1, caixa 24) → dá 24, e é nele que a conta
 *      vale.
 *
 *  Para CIMA, nunca para baixo: para baixo entregaria menos cobertura que o
 *  alvo pede, o oposto do que a sugestão existe para fazer.
 *
 *  Espelha `int_produto_demanda.sql` (coluna AZ), que faz o mesmo no modelo —
 *  as duas contas têm de dar o mesmo número, senão a coluna "Sug." muda de
 *  valor só por alguém ter encostado no controle de cobertura. */
export function paraMultiploDaCaixa(qtd, p) {
  const caixa = (p?.embalCompra || 0) / (p?.fatorExibicao || 1);
  if (!Number.isFinite(caixa) || caixa <= 1) return qtd;
  return Math.ceil(qtd / caixa) * caixa;
}

/** Slider (0–6, passo 0,5) MAIS campo numérico (0–12, passo 0,1) escrevendo o
 *  MESMO estado — não um OU o outro (§4.3 do prompt, com a medida que decide
 *  isso: o universo inteiro de `COBERTURA_ALVO` cabe em [1,5; 2,0], então um
 *  slider 0–12 daria ~2px por posição no dedo, precisão inatingível; um
 *  slider 0–6 passo 0,5 dá ~19px, e o campo cobre tanto a casa decimal fora
 *  do passo 0,5 quanto valores fora da faixa do slider).
 *
 *  `valor === null` é "use o alvo do modelo" — nunca pré-preenchido com um
 *  número (ex.: 2,0): um placeholder cumpre esse papel sem fingir que
 *  alguém decidiu 2,0. O botão "voltar ao alvo do modelo" é o único caminho
 *  de volta a essa partição exata, e por isso fica desabilitado quando já
 *  não há simulação (nada a desfazer).
 *
 *  O padrão de "campo sob o cursor não é recalculado a cada tecla" é o mesmo
 *  de `Precificacao.jsx` → `CelulaEdicao`: `editando` guarda o texto cru
 *  enquanto a pessoa digita; o valor FORMATADO (`numero(valor, 1)`, vírgula
 *  pt-BR) só volta a aparecer no blur ou quando o valor muda por fora
 *  (slider, "voltar ao alvo do modelo"). */
function ControleCobertura({ valor, setValor }) {
  const [editando, setEditando] = useState(null); // texto cru, ou null (não digitando)

  function aoDigitarCampo(texto) {
    setEditando(texto);
    if (texto.trim() === "") { setValor(null); return; } // campo vazio = "use o alvo do modelo"
    const n = parseNumeroPreco(texto);
    if (Number.isFinite(n) && n >= 0 && n <= 12) setValor(n);
  }

  // Por que o texto digitado não vira alvo — ou `undefined` quando vira. É o
  // `title` e o sinal de borda vermelha, o MESMO par dos campos de margem/MKP
  // (precoEditavel.js: motivoMargemInvalida). Até 08/10/2026 este campo
  // ignorava "13" ou "abc" EM SILÊNCIO: o valor anterior ficava — não havia
  // descarte —, mas a pessoa não via por que nada acontecia, que é meia
  // armadilha do mesmo tipo. Vazio não é erro: é o campo em repouso.
  const motivo = (() => {
    if (editando == null || editando.trim() === "") return undefined;
    const n = parseNumeroPreco(editando);
    if (!Number.isFinite(n)) return "Não é um número — use vírgula no decimal (ex.: 2,5)";
    if (n < 0 || n > 12) return "Fora da faixa — o alvo vai de 0 a 12 meses";
    return undefined;
  })();

  const valorCampo = editando != null ? editando : (valor != null ? numero(valor, 1) : "");

  return (
    <div>
      <div className="mb-1 text-xs text-gray-500">Cobertura alvo simulada (meses)</div>
      <div className="flex items-center gap-2">
        <input type="range" min={0} max={6} step={0.5} value={valor ?? 2}
               aria-label="Cobertura alvo simulada — slider, 0 a 6 meses"
               onChange={(e) => { setEditando(null); setValor(Number(e.target.value)); }}
               className="h-1.5 w-24 accent-current" style={{ color: NAVY }} />
        <input type="text" inputMode="decimal" value={valorCampo} placeholder="alvo do modelo"
               aria-label="Cobertura alvo simulada — valor exato, em meses"
               onChange={(e) => aoDigitarCampo(e.target.value)}
               onBlur={() => setEditando(null)}
               title={motivo}
               className={`num w-16 rounded-md border bg-white px-1.5 py-1 text-center text-sm ${motivo ? "border-red-500" : "border-gray-300"}`} />
        <button type="button" onClick={() => { setEditando(null); setValor(null); }}
                disabled={valor == null}
                title="Cada linha volta a usar o alvo do modelo (COBERTURA_ALVO do departamento, ou o padrão). Nenhuma quantidade digitada ou gravada muda."
                className="whitespace-nowrap rounded-md border border-gray-300 px-2 py-1.5 text-2xs font-medium text-gray-600 disabled:opacity-40">
          Voltar ao alvo do modelo
        </button>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------- paginação --- */

/** Veio de `telas/Pedidos.jsx` junto com a tabela, porque a edição de pedido
 *  pagina a mesma lista pelo mesmo `/api/produtos`. `Alertas.jsx` e
 *  `Precificacao.jsx` ainda têm cópias idênticas desta função — não foram
 *  mexidas aqui para a Etapa 17 não encostar em telas que ela não precisa
 *  tocar; unificar as três é limpeza separada. */
export function Paginacao({ pagina, total, aoTrocar }) {
  return (
    <div className="mt-4 flex items-center justify-center gap-3">
      <button type="button" disabled={pagina <= 1} onClick={() => aoTrocar(pagina - 1)}
              className="rounded-md border border-gray-300 px-3 py-1.5 text-sm disabled:opacity-30">
        Anterior
      </button>
      <span className="num text-sm text-gray-500">{numero(pagina)} de {numero(total)}</span>
      <button type="button" disabled={pagina >= total} onClick={() => aoTrocar(pagina + 1)}
              className="rounded-md border border-gray-300 px-3 py-1.5 text-sm disabled:opacity-30">
        Próxima
      </button>
    </div>
  );
}

/* ----------------------------------------------------------------- filtros --- */

/** `departamentoTravado`: quando vem preenchido, o campo Departamento deixa de
 *  ser `<select>` e vira etiqueta fixa. É o caso da edição de pedido — um
 *  pedido é de um departamento só (é assim que o Winthor importa pela rotina
 *  220), e `pedido.py:upsert_item` RECUSA produto de outro. Deixar o select
 *  aberto ali ofereceria um caminho que só termina em erro do servidor. */
export function FiltrosCatalogo({
  opcoes, departamento, setDepartamento, comprador, setComprador,
  status, setStatus, estoque, setEstoque, ordenar, dir, aoOrdenar,
  busca, setBusca, setPagina, total,
  referencia, dtUltEntDe, setDtUltEntDe, dtUltEntAte, setDtUltEntAte,
  departamentoTravado = null,
  // Etapa 19, item 2 — cobertura alvo SIMULADA (não é filtro: não vai para a
  // API, não entra no `where`, não dispara `buscar()` — §4.4 do prompt). As
  // DUAS telas que montam pedido (`/pedidos` e a edição de pedido salvo)
  // passam por aqui, cada uma com sua PRÓPRIA chave de `sessionStorage`.
  coberturaAlvoSimulada = null, setCoberturaAlvoSimulada = null,
}) {
  return (
    <div className="flex flex-wrap items-end gap-3">
      <div>
        <div className="mb-1 text-xs text-gray-500">Status</div>
        <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
          {["Ativo", "Inativo", "Todos"].map((s) => (
            <button key={s} type="button" aria-pressed={status === s}
                    onClick={() => { setStatus(s); setPagina(1); }}
                    style={status === s
                      ? { background: s === "Ativo" ? NAVY : s === "Inativo" ? RED : CINZA, color: "white" }
                      : {}}
                    className="rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500">
              {s}
            </button>
          ))}
        </div>
      </div>
      <FiltroEstoque valor={estoque} aoTrocar={(v) => { setEstoque(v); setPagina(1); }} />
      <Campo rotulo="Departamento" largura="w-44">
        {departamentoTravado ? (
          <div title="Um pedido é de um departamento só — é assim que o Winthor importa"
               className="flex w-full items-center gap-1.5 truncate rounded-lg border px-2.5 py-1.5 text-sm font-medium"
               style={{ borderColor: `${NAVY}33`, background: `${NAVY}0F`, color: NAVY }}>
            <Lock size={11} aria-hidden="true" className="shrink-0" />
            <span className="truncate">{departamentoTravado}</span>
          </div>
        ) : (
          <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                  aoTrocar={(v) => { setDepartamento(v); setPagina(1); }} />
        )}
      </Campo>
      {/* Backend já pronto: GET /api/produtos aceita `comprador`, GET
          /api/opcoes já devolve a lista. Cabe na fileira dos dois selects
          mortos ao lado, que ainda aguardam o cadastro no Winthor. */}
      <Campo rotulo="Comprador" largura="w-40">
        <Select valor={comprador} vazio="Todos" opcoes={opcoes?.compradores ?? []}
                aoTrocar={(v) => { setComprador(v); setPagina(1); }} />
      </Campo>
      <Campo rotulo="Seção" largura="w-36"><SelectVazio /></Campo>
      <Campo rotulo="Linha" largura="w-36"><SelectVazio /></Campo>
      <Campo rotulo="Ordenar por" largura="w-56">
        {/* Mesmo estado do cabeçalho clicável da tabela (§3.3) — escolher
            aqui move a seta para a coluna correspondente, e vice-versa. Se
            a ordem ativa veio de um clique em coluna que não está na lista
            fixa abaixo (ex.: "Estoque"), entra como opção sintética "Coluna:
            X" — sem isso o `<select>` fica sem `<option>` casada e renderiza
            em branco (ajuste 2 do revisor). */}
        <Select valor={ordenar} aoTrocar={(v) => aoOrdenar(v, ORDENACOES.find((o) => o.id === v)?.dir ?? "asc")}
                opcoes={ORDENACOES.some((o) => o.id === ordenar)
                  ? ORDENACOES.map((o) => o.id)
                  : [ordenar, ...ORDENACOES.map((o) => o.id)]}
                rotulos={{
                  ...Object.fromEntries(ORDENACOES.map((o) => [o.id, o.rotulo])),
                  ...(ORDENACOES.some((o) => o.id === ordenar)
                    ? {}
                    : { [ordenar]: `Coluna: ${ROTULO_COLUNA[ordenar] ?? ordenar}` }),
                }} />
      </Campo>
      <Campo rotulo="Buscar produto" largura="w-52">
        <div className="relative">
          <input type="search" value={busca} aria-label="Buscar produto"
                 onChange={(e) => { setBusca(e.target.value); setPagina(1); }}
                 placeholder="Nome ou código…"
                 className="w-full rounded-lg border border-gray-200 py-1.5 pl-7 pr-2.5 text-sm text-gray-800" />
          <Filter size={11} aria-hidden="true" className="absolute left-2.5 top-2.5 text-gray-400" />
        </div>
      </Campo>
      <FiltroUltimaEntrada referencia={referencia}
                           dtUltEntDe={dtUltEntDe} setDtUltEntDe={(v) => { setDtUltEntDe(v); setPagina(1); }}
                           dtUltEntAte={dtUltEntAte} setDtUltEntAte={(v) => { setDtUltEntAte(v); setPagina(1); }} />
      {setCoberturaAlvoSimulada && (
        <ControleCobertura valor={coberturaAlvoSimulada} setValor={setCoberturaAlvoSimulada} />
      )}
      <div className="num ml-auto text-xs text-gray-500">{numero(total)} produto(s)</div>
    </div>
  );
}

function Campo({ rotulo, largura = "", children }) {
  return (
    <div className={largura}>
      <div className="mb-1 text-xs text-gray-500">{rotulo}</div>
      {children}
    </div>
  );
}

function Select({ valor, aoTrocar, opcoes, vazio, rotulos }) {
  return (
    <div className="relative">
      <select value={valor} onChange={(e) => aoTrocar(e.target.value)}
              className="w-full appearance-none rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 pr-6 text-sm font-medium text-gray-800">
        {vazio !== undefined && <option value="">{vazio}</option>}
        {opcoes.map((o) => <option key={o} value={o}>{rotulos?.[o] ?? o}</option>)}
      </select>
      <ChevronDown size={12} aria-hidden="true"
                   className="pointer-events-none absolute right-2 top-2.5 text-gray-400" />
    </div>
  );
}

function SelectVazio() {
  return (
    <div className="relative">
      <select disabled title="Aguardando o cadastro no Winthor"
              className="w-full appearance-none rounded-lg border border-gray-200 bg-gray-50 px-2.5 py-1.5 pr-6 text-sm font-medium text-gray-400">
        <option>Todas</option>
      </select>
      <ChevronDown size={12} aria-hidden="true"
                   className="pointer-events-none absolute right-2 top-2.5 text-gray-300" />
    </div>
  );
}

/* ------------------------------------------------------------------ tabela --- */

/** `avisoLinha`: função opcional `(produto) => nó | null`, renderizada logo
 *  abaixo do nome do produto. Existe para a edição de pedido poder dizer "já
 *  está no pedido — digitar aqui substitui a quantidade" sem que esta tabela
 *  precise saber o que é um pedido: o servidor faz UPSERT por (pedido,
 *  produto), e sem o aviso a pessoa digitaria de novo achando que soma. */
export function TabelaCatalogo({ itens, valorDe, aoTrocar, ordenar, dir, aoOrdenar,
                                 mesReferencia, parametros, avisoLinha, originalDe,
                                 coberturaAlvoSimulada = null }) {
  // Rótulos dos meses, como no gráfico do SKU: nome do mês em vez de M-1/M-2/M-3.
  const rot = (i) => (mesReferencia ? mesCurto(mesesAntes(mesReferencia, i)) : ["Atual", "M-1", "M-2", "M-3"][i]);
  const props = { ordenar, dir, aoOrdenar };
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-200">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
            <CabecalhoOrdenavel {...props} coluna="codigo" padrao="asc">Código</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="descricao" padrao="asc" className="min-w-[240px]">Produto</CabecalhoOrdenavel>
            {/* Classe (curva ABC) não está no whitelist do servidor — não fica
                clicável (§3.1). */}
            <th className="px-2 py-2 text-center font-medium">Classe</th>
            <CabecalhoOrdenavel {...props} coluna="estoque" padrao="desc" align="center" style={{ background: F_EST }}>Estoque</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="pendente" padrao="desc" align="center" style={{ background: F_EST }}>Pend.</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="estPedido" padrao="desc" align="center" style={{ background: F_ESTPED }}>EST+PED</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="ultimaEntrada" padrao="desc" align="center">Últ. entrada</CabecalhoOrdenavel>
            {/* Preço unitário da MESMA última entrada da coluna vizinha — por
                isso fica colada a ela na leitura (data/qtd da entrada, e o
                preço daquela entrada). Mostra `precoEntradaSemFrete`
                (COMPRAS_PRODUTO_CONTEXTO.PRECO_ULT_ENT_SEM_FRETE, rotina 218 do
                WinThor): o valor do PRODUTO, sem o frete que `vl_ent_unit`
                embute — é este o número que faz sentido negociar com o
                fornecedor (pedido do Diretor, 25/09). O servidor passou a ter
                a chave `valorNfSemFrete` (`produto.py:ORDENACOES`, aponta para
                `ctx.preco_ult_ent_sem_frete`) — cabeçalho volta a ser
                `CabecalhoOrdenavel`. */}
            <CabecalhoOrdenavel {...props} coluna="valorNfSemFrete" padrao="desc" align="center">
              {/* `title` não é prop de `CabecalhoOrdenavel` (não está entre as
                  desestruturadas do componente) — passá-lo direto seria
                  silenciosamente ignorado. O `<span title>` por dentro do
                  `children` é quem carrega o tooltip de verdade. */}
              <span title="Valor da nota, sem o custo do frete — o valor negociado com o fornecedor (rotina 218)">Valor NF (s/ frete)</span>
            </CabecalhoOrdenavel>
            {/* As 4 colunas de venda mensal: só a primeira (mês corrente) tem
                ordenação própria no servidor (`vendaAtual` → VD_MES_ATUAL);
                M-1/M-2/M-3 não têm coluna equivalente no whitelist — ficam
                estáticas, para não fingir uma ordenação que não existe. */}
            <CabecalhoOrdenavel {...props} coluna="vendaAtual" padrao="desc" align="center" style={{ background: F_VENDA }}>{rot(0)}</CabecalhoOrdenavel>
            {Array.from({ length: MESES_CATALOGO - 1 }, (_, i) => (
              <th key={i + 1} className="px-2 py-2 text-center font-medium"
                  style={{ background: F_VENDA }}>{rot(i + 1)}</th>
            ))}
            <CabecalhoOrdenavel {...props} coluna="mediaVenda" padrao="desc" align="center" style={{ background: F_MEDIA }}>Média</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="ultimaSaida" padrao="desc" align="center">Últ. saída</CabecalhoOrdenavel>
            {/* Clientes AT/VAR mistura duas métricas na mesma célula
                ("12/34") — não há UMA coluna que o clique ordene sem ambiguidade,
                então fica sem cabeçalho clicável (§3.1). */}
            <th className="px-2 py-2 text-center font-medium">Clientes AT/VAR</th>
            <CabecalhoOrdenavel {...props} coluna="cobertura" padrao="asc" align="center" style={{ background: F_COB }}>Cob./Alvo</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="tendencia" padrao="desc" align="center" style={{ background: F_COB }}>Tend.</CabecalhoOrdenavel>
            <th className="px-2 py-2 text-center font-medium">Sugestão</th>
            <th className="px-3 py-2 text-center font-medium">Pedido</th>
          </tr>
        </thead>
        <tbody>
          {itens.map((p) => (
            <LinhaCatalogo key={p.codigo} p={p} parametros={parametros}
                           valor={valorDe(p.codigo)}
                           original={originalDe?.(p.codigo) ?? null}
                           aviso={avisoLinha?.(p) ?? null}
                           coberturaAlvoSimulada={coberturaAlvoSimulada}
                           aoTrocar={(v) => aoTrocar(p.codigo, v)} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** `original`: a quantidade que JÁ está gravada para este produto (null quando
 *  não há nenhuma). Quando vem preenchida, o campo da coluna PEDIDO nasce com
 *  ela — pedido do usuário em 30/09/2026: "colocar as unidades pedidas no
 *  mesmo lugar de adicionar" —, e passa a destacar-se em âmbar assim que o
 *  valor digitado difere, com o número anterior logo abaixo ("era 36"). Sem
 *  esse par o campo mentiria: mostraria vazio para um item que tem 36
 *  gravadas, e confirmar sobrescreveria sem a pessoa ver o que mudou. */
function LinhaCatalogo({ p, valor, aoTrocar, parametros, aviso, original, coberturaAlvoSimulada = null }) {
  const digitado = String(valor ?? "").trim();
  const alterado = original != null && digitado !== ""
    && Number(digitado.replace(",", ".")) !== Number(original);
  const limpou = original != null && digitado === "";
  // Mesmo parâmetro de DecisaoSKU.jsx:72 — `cobertura_critica_fracao` vem de
  // GET /api/parametros para não duplicar o literal em duas telas com risco
  // de uma mudar e a outra não (rotas.py:87 documenta por que o limiar não
  // pode ser constante no JS). O `?? 0.6` é só o retrocesso enquanto a rota
  // não respondeu ainda, não um segundo valor de verdade.
  const fracaoCritica = parametros?.cobertura_critica_fracao ?? 0.6;
  const critica = p.mesesCobertura != null && p.coberturaAlvo != null
    && p.mesesCobertura < p.coberturaAlvo * fracaoCritica;
  // Sem média não há cobertura: não é dado faltando, é divisão que não existe.
  const semVenda = !p.mediaJanela;
  // O alvo que a célula MOSTRA. Com o controle mexido, mostra o SIMULADO —
  // pedido do Diretor em 09/10/2026 ("a coluna continua mostrando 2,0 com o
  // slider em 3,0"). A Etapa 19 (§4.4) tinha decidido o contrário, para a
  // pessoa não perder a referência de onde partiu; ele preferiu ver o alvo
  // que está simulando, e o alvo do modelo continua à mão no próprio
  // controle, que mostra quanto foi posto e tem o botão de voltar.
  //
  // ⚠ A COR de crítica continua no alvo do MODELO (`critica`, acima): pintar
  // de verde porque alguém baixou o slider seria o indicador seguindo o
  // ajuste em vez de julgá-lo. O alvo simulado muda o que se lê, não o
  // veredito.
  const alvoSimulado = coberturaAlvoSimulada != null;
  const alvoExibido = alvoSimulado ? coberturaAlvoSimulada : p.coberturaAlvo;
  const emCaixa = (p.fatorExibicao || 1) > 1;
  const seta = p.tendPct == null ? "→" : p.tendPct > 0.03 ? "↑" : p.tendPct < -0.03 ? "↓" : "→";
  const corSeta = p.tendPct == null ? CINZA : p.tendPct > 0.03 ? NAVY : p.tendPct < -0.03 ? RED : CINZA;

  const sug = sugestaoCobertura(p, coberturaAlvoSimulada);
  const mesesComPedido = coberturaComPedido(p, valor);
  const criticaProjetada = mesesComPedido != null && p.coberturaAlvo != null
    && mesesComPedido < p.coberturaAlvo * fracaoCritica;
  const atingiuAlvo = mesesComPedido != null && p.coberturaAlvo != null
    && mesesComPedido >= p.coberturaAlvo;

  return (
    <tr className="border-t border-gray-100 hover:bg-gray-50">
      <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
      <td className="px-3 py-2">
        <Link to={`/produto/${p.codigo}`}
              className="block w-full text-left hover:underline">
          <div className="whitespace-nowrap font-medium text-gray-800">{p.nome}</div>
          <div className="num text-2xs text-gray-400">
            {p.departamento} · {p.embalagem}{emCaixa ? ` · cx ${numero(p.embalCompra, 0)}` : ""}
          </div>
        </Link>
        {aviso}
      </td>
      <td className="px-2 py-2 text-center"><ClasseChip classe={p.classe} /></td>
      <td className="num px-2 py-2 text-center" style={{ background: F_EST }}>{quantidadeEstoque(p.estDisp)}</td>
      <td className="num px-2 py-2 text-center" style={{ background: F_EST }}>{numero(p.pendente, 0)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: F_ESTPED, color: "#1D4ED8" }}>{numero(p.estPend, 0)}</td>
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {dataCompleta(p.ultimaEntrada)}
        {p.qtdUltimaEntrada != null && <div className="text-gray-400">{numero(p.qtdUltimaEntrada, 0)}</div>}
      </td>
      {/* `precoEntradaSemFrete` (COMPRAS_PRODUTO_CONTEXTO.PRECO_ULT_ENT_SEM_FRETE,
          rotina 218 do WinThor) — o valor do PRODUTO na última entrada, SEM o
          frete que `valorEntradaUnitario` embute quando há. Pedido do Diretor
          (25/09): esta COLUNA passa a mostrar o valor sem frete, porque é o
          que se negocia com o fornecedor; o TOTAL do carrinho continua em
          `valorEntradaUnitario` — não foi pedido para mudar, e mudar o total
          junto seria decisão de outro escopo (reportado, não feito). */}
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {p.precoEntradaSemFrete != null ? moeda(p.precoEntradaSemFrete) : "—"}
      </td>
      {/* Etapa 13, ponto 1: `vendaHistorico` virou objeto POR MÉTRICA
          (`app/api/contrato.py:_venda_historico`). Esta tabela não tem
          seletor de métrica — só QUANTIDADE (já em unidade de exibição,
          dividida por FATOR_EXIBICAO) — porque é a única preenchida nas
          LISTAS paginadas; faturamento/peso/litros por linha exigiriam uma
          consulta a mais por produto na página (50/clique), e só o gráfico da
          tela do produto (Decisão do SKU) paga esse custo. */}
      {Array.from({ length: MESES_CATALOGO }, (_, i) => (
        <td key={i} className="num px-2 py-2 text-center" style={{ background: F_VENDA }}>
          {numero(p.vendaHistorico?.quantidade?.[i], 0)}
        </td>
      ))}
      <td className="num px-2 py-2 text-center font-semibold" style={{ background: F_MEDIA }}>
        {numero(p.mediaJanela, 0)}
      </td>
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {p.ultimaSaida ? p.ultimaSaida.split("-").reverse().slice(0, 2).join("/") : "—"}
        {p.qtdUltimaSaida != null && <div className="text-gray-400">{numero(p.qtdUltimaSaida, 0)}</div>}
      </td>
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {numero(p.clientesAtacado, 0)}/{numero(p.clientesVarejo, 0)}
      </td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: F_COB, color: critica ? RED : "#7E22CE" }}>
        {/* "sem venda" em vez de traço quando a média é zero: o traço é
            ambíguo (parece dado faltando) e o número não existe mesmo — não há
            por quanto dividir. Acontece quando o SKU não vendeu na janela, e
            também quando a devolução superou a venda e o total ficou negativo,
            caso em que o dbt trava a média em zero (int_produto_demanda.sql).
            Pedido do Diretor em 09/10/2026, junto com o fim das coberturas
            negativas (-114 meses no SKU 810). */}
        {semVenda ? (
          <div className="text-2xs font-normal text-gray-400">sem venda</div>
        ) : (
          <div>
            <span className="font-normal text-gray-400 text-2xs">agora </span>
            {numero(p.mesesCobertura, 1)}
            <span className={alvoSimulado ? "font-semibold" : "font-normal text-gray-400"}
                  style={alvoSimulado ? { color: NAVY } : undefined}
                  title={alvoSimulado
                    ? `Alvo simulado. O alvo do modelo é ${numero(p.coberturaAlvo, 1)} meses.`
                    : undefined}>
              {" "}/ {numero(alvoExibido, 1)}
            </span>
          </div>
        )}
        {/* Projeção de "se eu comprar isso agora" — só aparece com quantidade
            digitada, que é justamente a pergunta que digitar existe para
            responder (item 5 do Diretor, 08/09). Verde quando a projeção
            atinge o alvo, vermelho quando nem com o pedido sai da faixa
            crítica (mesmo limiar de 60% do `critica` acima). */}
        {mesesComPedido != null && (
          <div className="mt-0.5 border-t border-purple-100 pt-0.5 text-2xs"
               style={{ color: criticaProjetada ? RED : atingiuAlvo ? VERDE : "#7E22CE" }}>
            <span aria-hidden="true">→ </span>{numero(mesesComPedido, 1)}
          </div>
        )}
      </td>
      <td className="num px-2 py-2 text-center font-semibold" style={{ background: F_COB, color: corSeta }}>
        {seta} {p.tendPct != null ? `${numero(p.tendPct * 100, 0)}%` : ""}
      </td>
      <td className="px-2 py-2 text-center">
        {/* Com `coberturaAlvoSimulada == null` (padrão, "voltar ao alvo do
            modelo"), a sugestão é a do MODELO (SUG_COBERTURA, coluna AZ da
            planilha), byte a byte — não recalculada aqui. O protótipo a
            refaz em JS como `coberturaAlvo x média − (estDisp + estPend)` —
            e no nosso modelo EST_PEND já inclui EST_DISP (medido: em 8.829
            de 8.829 SKUs), então aquela conta subtrai o estoque duas vezes e
            pede a menos. Só quando a pessoa MEXEU no controle de cobertura
            (Etapa 19, item 2) é que `sug` vira a simulação — ver
            `sugestaoCobertura`, acima. */}
        {sug > 0 ? (
          <button type="button" onClick={() => aoTrocar(String(sug))}
                  title={coberturaAlvoSimulada == null
                    ? "Usar a sugestão do modelo"
                    : `Usar a sugestão simulada (alvo ${numero(coberturaAlvoSimulada, 1)} meses)`}
                  className="num rounded-md px-2 py-1 text-2xs font-semibold"
                  style={{ background: `${NAVY}12`, color: NAVY }}>
            {numero(sug, 0)}
          </button>
        ) : <span className="text-2xs text-gray-300">—</span>}
      </td>
      <td className="px-3 py-1.5 text-center" style={{ minWidth: 110 }}>
        <input type="text" inputMode="decimal" value={valor ?? ""}
               onChange={(e) => aoTrocar(e.target.value)}
               aria-label={`Quantidade a pedir do produto ${p.codigo}`}
               style={alterado || limpou
                 ? { borderColor: AMBAR, background: `${AMBAR}14`, color: AMBAR, fontWeight: 700 }
                 : undefined}
               className={`num w-[72px] rounded-md border px-1 py-1 text-center text-sm${
                 alterado || limpou ? "" : " border-gray-300"}`} />
        <div className="text-[9px] text-gray-400">{emCaixa ? "caixas" : "unidades"}</div>
        {/* O valor anterior só aparece quando há o que comparar — é a
            "mensagem de observação com a quantidade anterior" pedida em
            30/09/2026, para dar para conferir o que mudou antes de confirmar. */}
        {alterado && (
          <div className="text-[10px] font-semibold" style={{ color: AMBAR }}>
            era {numero(original, 0)}
          </div>
        )}
        {limpou && (
          <div className="text-[10px] font-semibold" style={{ color: RED }}>
            vazio remove ({numero(original, 0)})
          </div>
        )}
      </td>
    </tr>
  );
}
