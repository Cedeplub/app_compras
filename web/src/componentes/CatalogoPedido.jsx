import { Link } from "react-router-dom";
import { ChevronDown, Filter, Lock } from "lucide-react";
import CabecalhoOrdenavel, { ordenarLista } from "./CabecalhoOrdenavel.jsx";
import FiltroEstoque from "./FiltroEstoque.jsx";
import FiltroUltimaEntrada from "./FiltroUltimaEntrada.jsx";
import { ClasseChip } from "./Basicos.jsx";
import { dataCompleta, mesCurto, mesesAntes, moeda, numero, quantidadeEstoque } from "../formato.js";

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
                                 mesReferencia, parametros, avisoLinha, originalDe }) {
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
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(1)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(2)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(3)}</th>
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
                           aoTrocar={(v) => aoTrocar(p.codigo, v)} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Cobertura projetada com o pedido digitado (item 5 do Diretor, 08/09).
 *
 *  Fiel à coluna BF da planilha (`int_produto_pedido.sql:196-198`):
 *    meses_est_ped = (est_pend + pedido_unidades) / media_janela   (media_janela != 0)
 *  onde `pedido_unidades = pedido × fator_exibicao` — a mesma conversão que o
 *  carrinho já faz para somar peso/valor/litros.
 *
 *  ⚠ Ressalva que a API já tenta cobrir com `mesesCoberturaComPedido`, mas que
 *  não dá para "consertar" aqui: a coluna BF soma `est_pend + pedido_unidades`
 *  tratando EST_PEND como UNIDADES, enquanto a vizinha BG (`valor_estoque`)
 *  faz `est_pend × fator_exibicao × custo`, tratando EST_PEND como CAIXAS. As
 *  duas só coincidem quando `fator_exibicao = 1` — nos departamentos com
 *  PEDIDO_EM = 'MASTER' esta conta pode divergir do `mesesCoberturaComPedido`
 *  que o servidor manda (que reflete a MESMA fórmula BF, sobre o pedido já
 *  DECIDIDO e gravado — não o que está sendo digitado agora, que é o número
 *  que faz sentido mostrar aqui). Não é bug para corrigir no front: é regra de
 *  negócio do modelo, relatada para o Diretor decidir.
 */
function calcMesesCoberturaComPedido(p, valorDigitado) {
  const qtd = Number(String(valorDigitado ?? "").replace(",", ".")) || 0;
  if (qtd <= 0) return null;
  if (!p.mediaJanela) return null;
  const pedidoUnidades = qtd * (p.fatorExibicao || 1);
  return (Number(p.estPend || 0) + pedidoUnidades) / p.mediaJanela;
}

/** `original`: a quantidade que JÁ está gravada para este produto (null quando
 *  não há nenhuma). Quando vem preenchida, o campo da coluna PEDIDO nasce com
 *  ela — pedido do usuário em 30/09/2026: "colocar as unidades pedidas no
 *  mesmo lugar de adicionar" —, e passa a destacar-se em âmbar assim que o
 *  valor digitado difere, com o número anterior logo abaixo ("era 36"). Sem
 *  esse par o campo mentiria: mostraria vazio para um item que tem 36
 *  gravadas, e confirmar sobrescreveria sem a pessoa ver o que mudou. */
function LinhaCatalogo({ p, valor, aoTrocar, parametros, aviso, original }) {
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
  const emCaixa = (p.fatorExibicao || 1) > 1;
  const seta = p.tendPct == null ? "→" : p.tendPct > 0.03 ? "↑" : p.tendPct < -0.03 ? "↓" : "→";
  const corSeta = p.tendPct == null ? CINZA : p.tendPct > 0.03 ? NAVY : p.tendPct < -0.03 ? RED : CINZA;

  const mesesComPedido = calcMesesCoberturaComPedido(p, valor);
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
      {p.vendaHistorico.quantidade.map((v, i) => (
        <td key={i} className="num px-2 py-2 text-center" style={{ background: F_VENDA }}>{numero(v, 0)}</td>
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
        <div>
          <span className="font-normal text-gray-400 text-2xs">agora </span>
          {numero(p.mesesCobertura, 1)}
          <span className="font-normal text-gray-400"> / {numero(p.coberturaAlvo, 1)}</span>
        </div>
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
        {/* A sugestão vem do MODELO (SUG_COBERTURA, coluna AZ da planilha), não
            recalculada aqui. O protótipo a refaz em JS como
            `coberturaAlvo x média − (estDisp + estPend)` — e no nosso modelo
            EST_PEND já inclui EST_DISP (medido: em 8.829 de 8.829 SKUs), então
            aquela conta subtrai o estoque duas vezes e pede a menos. */}
        {p.sugCobertura > 0 ? (
          <button type="button" onClick={() => aoTrocar(String(p.sugCobertura))}
                  title="Usar a sugestão do modelo"
                  className="num rounded-md px-2 py-1 text-2xs font-semibold"
                  style={{ background: `${NAVY}12`, color: NAVY }}>
            {numero(p.sugCobertura, 0)}
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
