import { useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ChevronDown, ChevronLeft, ChevronRight, FileSpreadsheet, Loader2, Plus,
         Printer, Trash2 } from "lucide-react";
import { api } from "../api/cliente.js";
import logoCedep from "../logo-cedep.png";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { ordenarLista } from "../componentes/CabecalhoOrdenavel.jsx";
import { AvisoSemEntrada } from "../componentes/FiltroUltimaEntrada.jsx";
import { FiltrosCatalogo, TabelaCatalogo, Paginacao, ordenarCatalogo,
         FILTROS_PADRAO, POR_PAGINA } from "../componentes/CatalogoPedido.jsx";
import { useEstadoPersistente } from "../estadoTela.js";
import { COR_STATUS, ROTULO_AVANCAR, ROTULO_VOLTAR,
         avancarEhExportar, editavel, podeAvancar, podeVoltar } from "../pedidoStatus.js";
import { moeda, numero } from "../formato.js";

/* Tela — Detalhe do pedido salvo (PROTOTIPO.md §2.6, .jsx linha 1548),
 * com a sub-tela de adicionar produtos (§2.7) e o comprovante de impressão
 * (§2.8) embutidos.
 *
 * ⚠ Diferença deliberada em relação ao protótipo: lá a edição é local e sair
 * sem clicar "Salvar alterações" DESCARTA tudo em silêncio (§2.6). Aqui cada
 * alteração vai para o servidor no momento em que acontece, porque a alternativa
 * — um botão de salvar que a pessoa pode não ver — é a que perde trabalho. Em
 * troca, cada linha mostra o seu próprio estado de gravação.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";

// Acima disto, a lista "No pedido" abre FECHADA na sub-tela de produtos. Oito
// linhas é o que cabe numa tela de notebook sem empurrar os filtros do
// catálogo para fora — acima disso a pessoa rola para chegar ao que veio
// fazer, que foi a queixa que originou o colapso.
const LIMITE_AUTO_COLAPSO = 8;

// `aria-controls` do botão que abre/fecha a lista "No pedido" — é o que faz o
// leitor de tela saber QUE região aquele botão comanda.
const ID_SECAO_PEDIDO = "secao-itens-do-pedido";

// Mesmo âmbar de `CatalogoPedido.jsx`: "mexido, ainda não confirmado".
const AMBAR = "#B98A2E";

const comoNumero = (v) => Number(String(v ?? "").replace(",", "."));

/** Um item do pedido foi MEXIDO? Campo vazio conta como mexido porque
 *  confirmar com ele vazio manda quantidade 0, e `upsert_item` remove a linha
 *  — é ação, não ausência de ação. */
function mudou(item, digitado) {
  const texto = String(digitado ?? "").trim();
  if (texto === "") return true;
  const n = comoNumero(texto);
  return Number.isFinite(n) && n !== Number(item.quantidade);
}

export default function PedidoDetalhe() {
  const { id } = useParams();
  const navegar = useNavigate();
  const [pedido, setPedido] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [adicionando, setAdicionando] = useState(false);
  const [imprimindo, setImprimindo] = useState(false);
  // Etapa 13, ponto 4: itens de UM pedido — lista sem paginação, ordena NO
  // CLIENTE (§3.1).
  const [ordenar, setOrdenar] = useState("codigo");
  const [dir, setDir] = useState("asc");
  const aoOrdenar = (coluna, d) => { setOrdenar(coluna); setDir(d); };

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setPedido(await api.pedido(id));
    } catch (e) {
      setErro(e.detalhe);
    } finally {
      setCarregando(false);
    }
  }, [id]);

  useEffect(() => { carregar(); }, [carregar]);

  // Mesmo mecanismo de `LotePrecoDetalhe.jsx:voltar` — `navegar(-1)` devolve
  // a tela ANTERIOR de verdade (Pedidos Salvos com o filtro que a pessoa
  // tinha escolhido, preservado por `estadoTela.js`), com fallback para o
  // destino fixo quando não há "tela anterior" nossa no histórico (link
  // direto, aba nova: `window.history.state.idx` nasce 0 nesse caso).
  function voltar() {
    if (window.history.state?.idx > 0) navegar(-1);
    else navegar("/pedidos-salvos");
  }

  async function agir(acao) {
    setOcupado(true);
    setErro(null);
    try {
      await acao();
      await carregar();
    } catch (e) {
      setErro(e.status === 404 ? "Você não tem permissão para esta ação." : e.detalhe);
    } finally {
      setOcupado(false);
    }
  }

  if (carregando) return <Carregando>Buscando o pedido…</Carregando>;
  if (erro && !pedido) return <Erro mensagem={erro} aoTentarDeNovo={carregar} />;
  if (!pedido) return null;

  if (adicionando) {
    return <AdicionarProdutos pedido={pedido}
                              aoCancelar={() => setAdicionando(false)}
                              aoConcluir={async () => { setAdicionando(false); await carregar(); }} />;
  }

  const podeEditar = editavel(pedido.status);
  const cor = COR_STATUS[pedido.status] ?? "#6B7280";

  return (
    <div className="px-4 pb-8 pt-3 md:px-6 md:pt-4">
      <button type="button" onClick={voltar}
              className="mb-3 flex items-center gap-1 text-sm font-medium" style={{ color: NAVY }}>
        <ChevronLeft size={14} aria-hidden="true" /> Voltar para a lista
      </button>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 text-lg font-semibold text-gray-900">
            <span className="num text-gray-400">#{pedido.id}</span>
            {pedido.fornecedor}
            <span className="rounded-full px-2 py-0.5 text-2xs font-bold"
                  style={{ background: `${cor}18`, color: cor }}>{pedido.status}</span>
          </h2>
          <p className="num mt-0.5 text-xs text-gray-500">
            {numero(pedido.itens.length)} item(ns) · {moeda(pedido.valorTotal)}
            {pedido.criadoPor && ` · criado por ${pedido.criadoPor}`}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ocupado && <Loader2 size={14} className="animate-spin text-gray-400" aria-hidden="true" />}
          {/* PDF e Excel valem em QUALQUER status, Rascunho inclusive: é comum
              querer conferir o pedido em papel ou mandar a planilha para alguém
              olhar ANTES de marcar como enviado. Amarrá-los a Fechado obrigaria
              a fechar para poder revisar, que é a ordem inversa. */}
          <Botao onClick={() => setImprimindo(true)} icone={Printer}>Orçamento em PDF</Botao>
          <Botao icone={FileSpreadsheet} desabilitado={ocupado}
                 onClick={() => agir(() => baixar(pedido.id, "excel"))}>
            Excel
          </Botao>
          {podeAvancar(pedido.status) && (
            <Botao destaque cor={cor} desabilitado={ocupado}
                   onClick={() => agir(async () => {
                     if (avancarEhExportar(pedido.status)) await baixar(pedido.id, "winthor");
                     else await api.avancarPedido(pedido.id);
                   })}>
              {ROTULO_AVANCAR[pedido.status]}
            </Botao>
          )}
          {podeVoltar(pedido.status) && (
            <Botao desabilitado={ocupado} onClick={() => agir(() => api.voltarPedido(pedido.id))}>
              {ROTULO_VOLTAR[pedido.status]}
            </Botao>
          )}
        </div>
      </div>

      {erro && <div className="mt-3"><Erro mensagem={erro} /></div>}

      {!podeEditar && (
        <p className="mt-3 rounded-md px-3 py-2 text-xs" style={{ background: `${cor}0D`, color: cor }}>
          Pedido em “{pedido.status}” — os itens ficam só para leitura. Volte um passo para editar.
        </p>
      )}

      <div className="mt-4 overflow-x-auto rounded-lg border border-gray-200">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="codigo" padrao="asc">Código</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="descricao" padrao="asc" className="min-w-[240px]">Produto</CabecalhoOrdenavel>
              <th className="px-2 py-2 text-center font-medium">Embalagem</th>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="quantidade" padrao="desc" align="center">Qtd.</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="quantidadeUnidades" padrao="desc" align="center">Em unidades</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="precoUnitario" padrao="desc" align="center">Preço unit.</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="valorTotal" padrao="desc" align="right">Total</CabecalhoOrdenavel>
              {podeEditar && <th className="px-2 py-2" />}
            </tr>
          </thead>
          <tbody>
            {ordenarLista(pedido.itens, {
              codigo: (it) => it.codigo, descricao: (it) => it.descricao,
              quantidade: (it) => it.quantidade, quantidadeUnidades: (it) => it.quantidadeUnidades,
              precoUnitario: (it) => it.precoUnitario, valorTotal: (it) => it.valorTotal,
            }[ordenar] ?? ((it) => it.codigo), dir).map((it) => (
              <LinhaItem key={it.codigo} it={it} idPedido={pedido.id} podeEditar={podeEditar}
                         aoMudar={carregar} />
            ))}
            {pedido.itens.length === 0 && (
              <tr>
                <td colSpan={8} className="py-8 text-center text-sm text-gray-400">
                  Nenhum item — adicione produtos ou exclua o pedido.
                </td>
              </tr>
            )}
          </tbody>
          <tfoot>
            <tr className="border-t border-gray-200 bg-gray-50">
              <td colSpan={6} className="px-3 py-2 text-right text-xs font-medium text-gray-600">
                Total do pedido
              </td>
              <td className="num px-2 py-2 text-right font-bold" style={{ color: NAVY }}>
                {moeda(pedido.valorTotal)}
              </td>
              {podeEditar && <td />}
            </tr>
          </tfoot>
        </table>
      </div>

      {podeEditar && (
        <button type="button" onClick={() => setAdicionando(true)}
                className="mt-3 flex items-center gap-1.5 rounded-lg border px-3 py-2 text-sm font-semibold"
                style={{ color: NAVY, borderColor: `${NAVY}44` }}>
          <Plus size={14} aria-hidden="true" /> Ver e adicionar produtos
        </button>
      )}

      {imprimindo && <Comprovante pedido={pedido} aoFechar={() => setImprimindo(false)} />}
    </div>
  );
}

async function baixar(id, formato) {
  const { blob, nome } = await api.baixarExportacao(id, formato);
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = nome;
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(url);
}

function Botao({ children, onClick, icone: Icone, destaque, cor = NAVY, desabilitado }) {
  return (
    <button type="button" onClick={onClick} disabled={desabilitado}
            className="flex items-center gap-1 rounded-md border px-2.5 py-1.5 text-xs font-semibold disabled:opacity-40"
            style={destaque ? { background: cor, color: "white", borderColor: cor }
                            : { color: cor, borderColor: `${cor}44` }}>
      {Icone && <Icone size={12} aria-hidden="true" />}
      {children}
    </button>
  );
}

/* --------------------------------------------------------------- item ----- */

/** Preço com 2 casas e vírgula, para o campo ficar legível.
 *
 *  ⚠ O banco guarda 4 casas (o preço nasce de CUSTO_TOT_GERENCIAL, que tem
 *  muitas). Exibir 12,41 onde estão gravados 12,4111 é bom para ler e perigoso
 *  para escrever: o `blur` veria uma diferença de 0,0011 e gravaria o
 *  arredondamento, mudando um preço que ninguém pediu para mudar. Por isso a
 *  gravação depende de `tocado`, e não de comparar valores. */
const paraCampo = (v, casas = 2) => {
  if (v == null) return "";
  // Quantidade quase sempre é inteira: mostrar "5,00" onde cabe "5" só polui.
  // O tipo do banco aceita fração (number(14,4)), então quando ela existe, ela
  // aparece — o que some é o zero decorativo, não a informação.
  const texto = v.toFixed(casas).replace(/\.?0+$/, "");
  return (texto || "0").replace(".", ",");
};

function LinhaItem({ it, idPedido, podeEditar, aoMudar }) {
  const [qtd, setQtd] = useState(paraCampo(it.quantidade, 4));
  const [preco, setPreco] = useState(paraCampo(it.precoUnitario));
  const [tocado, setTocado] = useState({});
  const [estado, setEstado] = useState("parado");
  const [erro, setErro] = useState(null);

  // Grava no `blur`, e não a cada tecla: uma requisição por dígito digitado
  // seria uma escrita por caractere numa tabela auditada.
  async function gravar(campo, bruto, forcar = false) {
    if (!forcar && !tocado[campo]) return;
    const n = Number(String(bruto).replace(",", ".")) || 0;
    setEstado("salvando");
    setErro(null);
    try {
      // Quantidade zero REMOVE a linha — é o comportamento do protótipo (§2.6),
      // e o servidor faz o mesmo.
      if (campo === "quantidade" && n <= 0) await api.removerItemPedido(idPedido, it.codigo);
      else await api.gravarItemPedido(idPedido, it.codigo, { [campo === "quantidade" ? "quantidade" : "precoUnitario"]: n });
      setEstado("parado");
      await aoMudar();
    } catch (e) {
      setErro(e.detalhe);
      setEstado("erro");
    }
  }

  const emCaixa = (it.fatorExibicao || 1) > 1;

  return (
    <tr className="border-t border-gray-100">
      <td className="num px-2 py-2 text-gray-500">{it.codigo}</td>
      <td className="px-3 py-2">
        <div className="font-medium text-gray-800">{it.descricao}</div>
        {it.codFab && <div className="num text-2xs text-gray-400">fab {it.codFab}</div>}
        {erro && <div role="alert" className="text-2xs" style={{ color: RED }}>{erro}</div>}
      </td>
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {it.embalagem}{emCaixa ? ` · cx ${numero(it.embalCompra, 0)}` : ""}
      </td>
      <td className="px-2 py-2 text-center">
        {podeEditar ? (
          <input type="text" inputMode="decimal" value={qtd}
                 aria-label={`Quantidade do produto ${it.codigo}`}
                 onChange={(e) => { setQtd(e.target.value); setTocado((t) => ({ ...t, quantidade: true })); }}
                 onBlur={() => gravar("quantidade", qtd)}
                 className="num w-[72px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
        ) : <span className="num">{numero(it.quantidade, 0)}</span>}
        <div className="text-[9px] text-gray-400">{emCaixa ? "caixas" : "unidades"}</div>
      </td>
      <td className="num px-2 py-2 text-center text-gray-600">{numero(it.quantidadeUnidades, 0)}</td>
      <td className="px-2 py-2 text-center">
        {podeEditar ? (
          <input type="text" inputMode="decimal" value={preco}
                 aria-label={`Preço unitário do produto ${it.codigo}`}
                 onChange={(e) => { setPreco(e.target.value); setTocado((t) => ({ ...t, preco: true })); }}
                 onBlur={() => gravar("preco", preco)}
                 className="num w-[84px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
        ) : <span className="num">{moeda(it.precoUnitario)}</span>}
      </td>
      <td className="num px-2 py-2 text-right font-semibold">{moeda(it.valorTotal)}</td>
      {podeEditar && (
        <td className="px-2 py-2 text-center">
          {estado === "salvando"
            ? <Loader2 size={13} className="mx-auto animate-spin text-gray-400" aria-hidden="true" />
            : (
              <button type="button" onClick={() => gravar("quantidade", "0", true)}
                      aria-label={`Remover o produto ${it.codigo} do pedido`} title="Remover do pedido">
                <Trash2 size={13} style={{ color: RED }} aria-hidden="true" />
              </button>
            )}
        </td>
      )}
    </tr>
  );
}

/* ---------------------------------------------------- adicionar produtos --- */

/* §2.7: mostra só produtos do MESMO departamento do pedido — um pedido salvo é
 * sempre de um departamento só, exigência do formato do Winthor. */
/** Sub-tela §2.7 — o catálogo do departamento do pedido.
 *
 *  Etapa 17 (pedido do Diretor, 29/09/2026): "na tela de edição de um pedido
 *  salvo ele precisa ver os detalhes que vê na tela de pedido". Por isso aqui
 *  entra a MESMA tabela e os MESMOS filtros de `/pedidos` —
 *  `componentes/CatalogoPedido.jsx`, um componente só para as duas telas — e
 *  não uma tabela reduzida que fatalmente divergiria daquela.
 *
 *  Como todo produto do departamento aparece na lista, os que JÁ estão no
 *  pedido também aparecem: é assim que o Diretor vê estoque, cobertura, venda
 *  e tendência do que já pediu, sem que esta sub-tela precise duplicar a lista
 *  de itens que fica na tela de trás.
 *
 *  ⚠ O departamento fica TRAVADO em `pedido.fornecedor`, não pré-selecionado:
 *  um pedido é de um departamento só (rotina 220 do Winthor) e
 *  `pedido.py:upsert_item` recusa produto de outro. O filtro travado não é a
 *  trava — a trava é do servidor; aqui ele só evita oferecer um caminho que
 *  termina em erro.
 */
function AdicionarProdutos({ pedido, aoCancelar, aoConcluir }) {
  const [opcoes, setOpcoes] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  // Nasce com a quantidade JÁ gravada de cada item do pedido, para o campo da
  // coluna PEDIDO mostrá-la no mesmo lugar onde se digita (pedido do usuário
  // em 30/09/2026). Os produtos do catálogo continuam nascendo vazios.
  const [quantidades, setQuantidades] = useState(
    () => Object.fromEntries(pedido.itens.map((i) => [i.codigo, paraCampo(i.quantidade, 4)])));
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState(null);

  // DUAS TABELAS EMPILHADAS, não duas visões alternadas (pedido do usuário em
  // 29/09/2026, depois de ver a versão com botões: "uma tabela em cima
  // mostrando os produtos já no pedido e embaixo a tabela com os demais").
  // Em cima os itens do pedido; embaixo o resto do departamento. Assim o que
  // já foi pedido está sempre à vista — o defeito original era que, no catálogo
  // inteiro (297 produtos em 6 páginas no PETROBRAS, medido), esses itens caem
  // numa página qualquer e não se acham.
  const [itensDoPedido, setItensDoPedido] = useState(null);
  const [carregandoPedido, setCarregandoPedido] = useState(false);

  // A tabela de cima COLAPSA (pedido do usuário em 29/09/2026: "alguns pedidos
  // estão muito grandes e o usuário tem que rolar muito para baixo para chegar
  // na tabela com produtos para adicionar").
  //
  // Nasce fechada quando o pedido é grande — é justamente aí que o problema
  // aparece; num pedido de 3 itens fechar por padrão só esconderia o que a
  // pessoa quer ver. Depois disso vale a escolha dela, guardada por pedido.
  //
  // ⚠ Objeto, não booleano: `lerStorage` (estadoTela.js) descarta primitivo e
  // devolve o padrão, então um `true`/`false` gravado NUNCA voltaria.
  const [secao, setSecao] = useEstadoPersistente(
    `app_compras_pedido_${pedido.id}_secao_v1`,
    { aberto: pedido.itens.length <= LIMITE_AUTO_COLAPSO });
  const abertoPedido = secao.aberto;

  // Chave PRÓPRIA, por pedido. Filtrar o catálogo aqui dentro não pode mexer no
  // que a pessoa deixou montado em `/pedidos` (chave
  // `app_compras_filtros_pedidos_v1`), nem um pedido herdar o filtro do outro.
  const [filtros, setFiltros] = useEstadoPersistente(
    `app_compras_filtros_pedido_${pedido.id}_v1`, FILTROS_PADRAO);
  const setCampo = (campo) => (v) => setFiltros((f) => ({
    ...f, [campo]: typeof v === "function" ? v(f[campo]) : v,
  }));
  const { comprador, status, estoque, busca, pagina, dtUltEntDe, dtUltEntAte } = filtros;
  const setComprador = setCampo("comprador");
  const setStatus = setCampo("status");
  const setEstoque = setCampo("estoque");
  const setBusca = setCampo("busca");
  const setPagina = setCampo("pagina");
  const setDtUltEntDe = setCampo("dtUltEntDe");
  const setDtUltEntAte = setCampo("dtUltEntAte");

  // Ordenação em estado LOCAL, não em `useOrdenacaoUrl` como `/pedidos`: o
  // "Voltar" desta tela é `navegar(-1)` (ver o comentário lá em cima), e cada
  // clique de coluna escrevendo search param empilharia entradas no histórico
  // — voltar passaria a desfazer ordenações em vez de sair do pedido.
  const [ordenar, setOrdenar] = useState("cobertura");
  const [dir, setDir] = useState("asc");
  const aoOrdenar = useCallback((coluna, direcao) => {
    setOrdenar(coluna);
    setDir(direcao);
    setPagina(1);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Ordenação PRÓPRIA da tabela de cima. Separada de propósito: as duas
  // tabelas têm cabeçalho clicável, e um estado só faria clicar na de cima
  // disparar uma busca no servidor e reordenar a de baixo junto.
  const [ordenarPed, setOrdenarPed] = useState("codigo");
  const [dirPed, setDirPed] = useState("asc");
  const aoOrdenarPed = useCallback((coluna, direcao) => {
    setOrdenarPed(coluna);
    setDirPed(direcao);
  }, []);

  const jaNoPedido = new Map(pedido.itens.map((i) => [i.codigo, i.quantidade]));
  const codigosDoPedido = pedido.itens.map((i) => i.codigo).join(",");

  useEffect(() => {
    api.opcoes().then(setOpcoes).catch(() => setOpcoes(null));
    api.parametros().then(setParametros).catch(() => setParametros(null));
  }, []);

  // Os produtos COMPLETOS dos itens do pedido, para a tabela de cima usar a
  // mesma tabela larga da de baixo. Um GET por item —
  // `/api/produtos/{codigo}` devolve exatamente o mesmo contrato da lista
  // (conferido), e um pedido tem poucos itens, então não vale inventar uma
  // rota nova para isso. Item que falhar sai da lista em vez de derrubar a
  // tela inteira.
  useEffect(() => {
    const codigos = codigosDoPedido ? codigosDoPedido.split(",").map(Number) : [];
    if (codigos.length === 0) { setItensDoPedido([]); return undefined; }
    let cancelado = false;
    setCarregandoPedido(true);
    Promise.all(codigos.map((c) => api.produto(c).catch(() => null)))
      .then((lista) => { if (!cancelado) setItensDoPedido(lista.filter(Boolean)); })
      .finally(() => { if (!cancelado) setCarregandoPedido(false); });
    return () => { cancelado = true; };
  }, [codigosDoPedido]);

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.produtos({
        // Sempre o departamento do pedido — nunca o que estiver guardado no
        // filtro: é a trava, não uma preferência da pessoa.
        departamento: pedido.fornecedor,
        comprador: comprador || null,
        status: status === "Todos" ? null : status,
        estoque: estoque || null,
        busca: busca || null,
        ordenar, dir, pagina, porPagina: POR_PAGINA,
        dtUltEntDe: dtUltEntDe || null,
        dtUltEntAte: dtUltEntAte || null,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [pedido.fornecedor, comprador, status, estoque, busca, ordenar, dir,
      pagina, dtUltEntDe, dtUltEntAte]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  async function confirmar() {
    setSalvando(true);
    setErro(null);
    try {
      // ⚠ Só o que MUDOU. Desde que o campo nasce preenchido com a quantidade
      // gravada, mandar "tudo que tem valor" reescreveria os 42 itens do
      // pedido a cada confirmação — 42 PUTs para nenhuma mudança, e 42 linhas
      // de auditoria mentindo que houve alteração.
      const aGravar = [
        ...alterados.map((i) => ({ codigo: i.codigo, quantidade: comoNumero(quantidades[i.codigo]) || 0 })),
        ...Object.entries(quantidades)
          .filter(([codigo]) => !jaNoPedido.has(Number(codigo)))
          .map(([codigo, q]) => ({ codigo: Number(codigo), quantidade: comoNumero(q) || 0 }))
          .filter((i) => i.quantidade > 0),
      ];
      // Um PUT por item: a rota de item é a mesma que a edição usa, e assim não
      // existe um segundo caminho de escrita que possa divergir dela.
      for (const i of aGravar) await api.gravarItemPedido(pedido.id, i.codigo, { quantidade: i.quantidade });
      await aoConcluir();
    } catch (e) {
      setErro(e.detalhe);
    } finally {
      setSalvando(false);
    }
  }

  // Tabela de cima: lista curta, não paginada pelo servidor — a ordenação por
  // clique no cabeçalho acontece no cliente, senão o cabeçalho ficaria
  // clicável sem fazer nada, que é pior que não ser clicável.
  const itensPedido = ordenarCatalogo(itensDoPedido ?? [], ordenarPed, dirPed);

  // Tabela de baixo: o RESTO do departamento. Tirar daqui quem já está em cima
  // é o que faz "demais produtos" ser verdade; a exclusão é no cliente porque
  // `/api/produtos` não tem "exceto estes códigos", e ela é barata (um pedido
  // tem poucos itens). ⚠ Efeito colateral aceito: a contagem e o número de
  // páginas vêm do servidor e ainda incluem os itens do pedido, então uma
  // página pode exibir menos linhas que as 50 do tamanho nominal.
  const itensCatalogo = (dados?.itens ?? []).filter((p) => !jaNoPedido.has(p.codigo));
  const aoTrocarQtd = (codigo, v) => setQuantidades((q) => ({ ...q, [codigo]: v }));

  // Itens do pedido cujo campo foi MEXIDO — não "preenchido". Desde que o
  // campo nasce com a quantidade gravada, "tem valor" deixou de significar
  // "tem coisa a gravar": só conta quem difere do que já está no banco.
  const alterados = pedido.itens.filter((i) => mudou(i, quantidades[i.codigo]));
  const alteradosNoPedido = alterados.length;

  // O botão conta ALTERAÇÕES, não campos preenchidos: item do pedido só entra
  // se mudou, produto do catálogo só entra se ganhou quantidade.
  // ⚠ Depois de `alterados` de propósito — `const` tem zona morta temporal, e
  // ler `alteradosNoPedido` acima da linha que o declara derruba a tela em
  // tempo de EXECUÇÃO, não de build (foi o que aconteceu em 30/09/2026).
  const novosDoCatalogo = Object.entries(quantidades)
    .filter(([codigo]) => !jaNoPedido.has(Number(codigo)))
    .filter(([, q]) => comoNumero(q) > 0).length;
  const escolhidos = alteradosNoPedido + novosDoCatalogo;

  return (
    <div className="px-4 pb-8 pt-3 md:px-6 md:pt-4">
      <button type="button" onClick={aoCancelar}
              className="mb-3 flex items-center gap-1 text-sm font-medium" style={{ color: NAVY }}>
        <ChevronLeft size={14} aria-hidden="true" /> Cancelar e voltar ao pedido
      </button>

      <h2 className="text-lg font-semibold text-gray-900">
        Produtos — {pedido.fornecedor}
      </h2>
      <p className="mt-0.5 text-xs text-gray-500">
        Só produtos deste departamento: um pedido é sempre de um só, porque é assim que o
        Winthor importa.
      </p>

      {/* ── Tabela 1: o que JÁ está no pedido (colapsável) ──────────────── */}
      {pedido.itens.length > 0 && (
        <section className="mt-5">
          {/* Barra com peso visual de verdade — borda, fundo e o "Mostrar"
              como pastilha sólida (pedido do usuário em 30/09/2026: "dar um
              pouco mais de destaque no cabeçalho 'no pedido' e na tag
              'mostrar'"). Antes era texto cinza solto e passava despercebido
              na altura em que o catálogo começa. */}
          <button type="button" aria-expanded={abertoPedido} aria-controls={ID_SECAO_PEDIDO}
                  onClick={() => setSecao((s) => ({ aberto: !s.aberto }))}
                  className="flex w-full items-center gap-2 rounded-lg border px-3 py-2.5 text-left transition-colors"
                  style={{ borderColor: `${NAVY}40`, background: `${NAVY}0D` }}>
            {abertoPedido
              ? <ChevronDown size={17} aria-hidden="true" style={{ color: NAVY }} />
              : <ChevronRight size={17} aria-hidden="true" style={{ color: NAVY }} />}
            <span className="text-sm font-bold" style={{ color: NAVY }}>
              No pedido
              <span className="num ml-1 font-semibold">({numero(pedido.itens.length)})</span>
            </span>
            <span className="num text-xs text-gray-500">· {moeda(pedido.valorTotal)}</span>
            {/* Alteração pendente não pode sumir sem aviso junto com a tabela:
                ela continua contando no "Confirmar" lá embaixo. */}
            {alteradosNoPedido > 0 && (
              <span className="num rounded-full px-2 py-0.5 text-2xs font-bold"
                    style={{ background: `${AMBAR}1F`, color: AMBAR }}>
                {numero(alteradosNoPedido)} alterado(s)
              </span>
            )}
            <span className="ml-auto rounded-md px-3 py-1.5 text-xs font-bold"
                  style={abertoPedido
                    ? { border: `1px solid ${NAVY}`, color: NAVY }
                    : { background: NAVY, color: "white" }}>
              {abertoPedido ? "Recolher" : "Mostrar"}
            </span>
          </button>

          <div id={ID_SECAO_PEDIDO} hidden={!abertoPedido}>
            <p className="mt-0.5 text-xs text-gray-500">
              O campo “Pedido” já vem com a quantidade gravada. O que você mudar fica em
              âmbar, com o valor anterior embaixo, até confirmar. Campo vazio remove o item.
            </p>
            <div className="mt-2">
              {carregandoPedido && <Carregando />}
              {!carregandoPedido && itensPedido.length > 0 && (
                /* Sem `avisoLinha`: a quantidade já pedida deixou de ser texto
                   embaixo do nome e virou o VALOR do campo da coluna PEDIDO
                   (`originalDe`), que é onde se digita. */
                <TabelaCatalogo itens={itensPedido}
                                valorDe={(codigo) => quantidades[codigo]}
                                originalDe={(codigo) => jaNoPedido.get(codigo) ?? null}
                                aoTrocar={aoTrocarQtd}
                                ordenar={ordenarPed} dir={dirPed} aoOrdenar={aoOrdenarPed}
                                mesReferencia={parametros?.mes_referencia} parametros={parametros} />
              )}
            </div>
          </div>
        </section>
      )}

      {/* ── Tabela 2: o RESTO do departamento ───────────────────────────── */}
      <section className="mt-6 border-t border-gray-200 pt-5">
        <h3 className="text-sm font-semibold text-gray-800">
          Demais produtos de {pedido.fornecedor}
        </h3>
        <p className="mt-0.5 text-xs text-gray-500">
          O que ainda não está no pedido. Digite a quantidade e confirme no fim da página.
        </p>

        <div className="mt-3">
          <FiltrosCatalogo {...{ opcoes, comprador, setComprador, status, setStatus,
                                 estoque, setEstoque, ordenar, dir, aoOrdenar,
                                 busca, setBusca, setPagina,
                                 referencia: parametros?.data_referencia,
                                 dtUltEntDe, setDtUltEntDe, dtUltEntAte, setDtUltEntAte }}
                           departamentoTravado={pedido.fornecedor}
                           total={dados?.total} />
        </div>
        {(dtUltEntDe || dtUltEntAte) && <AvisoSemEntrada />}

        {erro && <div className="mt-3"><Erro mensagem={erro} aoTentarDeNovo={buscar} /></div>}

        <div className="mt-4">
          {carregando && <Carregando />}
          {!carregando && !erro && itensCatalogo.length === 0 && (
            <div className="py-8 text-center text-sm text-gray-400">
              Nenhum outro produto nesse filtro.
            </div>
          )}
          {!carregando && !erro && itensCatalogo.length > 0 && (
            <TabelaCatalogo itens={itensCatalogo}
                            valorDe={(codigo) => quantidades[codigo]}
                            aoTrocar={aoTrocarQtd}
                            ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar}
                            mesReferencia={parametros?.mes_referencia} parametros={parametros} />
          )}
        </div>

        {dados && dados.totalPaginas > 1 && (
          <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
        )}
      </section>

      <div className="mt-4 flex items-center gap-3">
        <button type="button" onClick={confirmar} disabled={salvando || escolhidos === 0}
                className="flex items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
                style={{ background: NAVY }}>
          {salvando && <Loader2 size={14} className="animate-spin" aria-hidden="true" />}
          {/* "alteração", não "produto": o campo nasce preenchido, então o que
              o botão grava é o que MUDOU — item novo, quantidade trocada ou
              item esvaziado (que o servidor remove). */}
          {salvando ? "Gravando…" : `Confirmar ${numero(escolhidos)} alteração(ões)`}
        </button>
        <button type="button" onClick={aoCancelar}
                className="rounded-lg border border-gray-300 px-3 py-2 text-sm font-medium text-gray-700">
          Cancelar
        </button>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------- impressão --- */

/* §2.8: overlay de tela cheia com o documento formatado. `window.print()` é o
 * que gera o PDF — o navegador oferece "Salvar como PDF" no diálogo. O
 * protótipo faz igual, e vale dizer em voz alta: não geramos PDF, o navegador
 * gera.
 *
 * A logo entra aqui como `<img>`, nunca como `background-image`: por padrão o
 * navegador NÃO imprime imagem de fundo (nem cor de fundo), só o que está no
 * fluxo do documento — um `background-image` sumiria no PDF sem aviso nenhum.
 * Altura fixa (`h-12`, 48px) para não competir com o timbrado — a arte
 * original é 300×163, então em `w-auto` ela sai com ~88px de largura no
 * papel, um retângulo pequeno ao lado do título, não meia página. */
function Comprovante({ pedido, aoFechar }) {
  return (
    <div className="fixed inset-0 z-50 overflow-auto bg-white p-6 print:p-0">
      <div className="mx-auto max-w-3xl">
        <div className="flex items-center justify-between print:hidden">
          <button type="button" onClick={aoFechar}
                  className="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium">
            Fechar
          </button>
          <button type="button" onClick={() => window.print()}
                  className="rounded-md px-3 py-1.5 text-sm font-semibold text-white"
                  style={{ background: NAVY }}>
            Imprimir / Salvar PDF
          </button>
        </div>

        <div className="mt-6 flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-bold" style={{ color: NAVY }}>Orçamento de compra</h1>
            <p className="num mt-1 text-sm text-gray-600">
              Pedido #{pedido.id} · {pedido.fornecedor} · {pedido.status}
            </p>
          </div>
          <img src={logoCedep} alt="CEDEP" className="h-12 w-auto shrink-0" />
        </div>

        <table className="mt-4 w-full text-sm">
          <thead>
            <tr className="border-b border-gray-300 text-left text-xs uppercase text-gray-500">
              <th className="py-1.5">Código</th>
              <th className="py-1.5">Produto</th>
              <th className="py-1.5 text-center">Qtd.</th>
              <th className="py-1.5 text-center">Unidades</th>
              <th className="py-1.5 text-right">Preço unit.</th>
              <th className="py-1.5 text-right">Total</th>
            </tr>
          </thead>
          <tbody>
            {pedido.itens.map((it) => (
              <tr key={it.codigo} className="border-b border-gray-100">
                <td className="num py-1.5">{it.codigo}</td>
                <td className="py-1.5">{it.descricao}</td>
                <td className="num py-1.5 text-center">{numero(it.quantidade, 0)}</td>
                <td className="num py-1.5 text-center">{numero(it.quantidadeUnidades, 0)}</td>
                <td className="num py-1.5 text-right">{moeda(it.precoUnitario)}</td>
                <td className="num py-1.5 text-right">{moeda(it.valorTotal)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr>
              <td colSpan={5} className="py-2 text-right font-medium">Total</td>
              <td className="num py-2 text-right font-bold">{moeda(pedido.valorTotal)}</td>
            </tr>
          </tfoot>
        </table>

        <p className="mt-6 text-xs text-gray-500">CEDEP Comércio Ltda · Diretoria de Compras</p>
      </div>
    </div>
  );
}
