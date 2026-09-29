import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AlertTriangle, Check, ChevronDown, ChevronUp, Loader2, Trash2, X } from "lucide-react";
import { api } from "../api/cliente.js";
import { useAtualizacao } from "../contexto/atualizacao.jsx";
import { useCarrinho } from "../contexto/carrinho.jsx";
import { useEstadoPersistente } from "../estadoTela.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import { useOrdenacaoUrl } from "../componentes/CabecalhoOrdenavel.jsx";
import { AvisoSemEntrada } from "../componentes/FiltroUltimaEntrada.jsx";
import { FiltrosCatalogo, TabelaCatalogo, Paginacao, FILTROS_PADRAO,
         POR_PAGINA } from "../componentes/CatalogoPedido.jsx";
import { moeda, numero } from "../formato.js";

/* Tela — Pedidos (PROTOTIPO.md §2.4, .jsx linha 2735).
 *
 * O carrinho: a lista larga com todo o contexto de decisão de compra, e um
 * campo de quantidade por produto. Salvar cria UM pedido por departamento —
 * exigência do formato de importação do Winthor (rotina 220).
 */

const NAVY = "#375DA8";
const RED = "#DE434B";
const VERDE = "#15803D";

// Os filtros e a tabela larga saíram daqui para `componentes/CatalogoPedido.jsx`
// na Etapa 17 — a edição de um pedido salvo passou a mostrar os MESMOS dados
// (pedido do Diretor, 29/09/2026), e duas cópias divergiriam na primeira coluna
// que mudasse de um lado só. `FILTROS_PADRAO` e as cores das colunas vivem lá.
// O que ficou aqui é o que é só desta tela: carrinho global, barra de totais e
// salvar.

const UNIDADES = [
  { id: "valor", rotulo: "R$" },
  { id: "peso", rotulo: "Peso" },
  { id: "litros", rotulo: "Litros" },
  { id: "qtd", rotulo: "Qtd" },
];

export default function Pedidos() {
  const navegar = useNavigate();
  const { versaoDados } = useAtualizacao();
  const [opcoes, setOpcoes] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [filtros, setFiltros] = useEstadoPersistente(
    "app_compras_filtros_pedidos_v1", FILTROS_PADRAO);
  // Aceita valor direto ou função de atualização — mesmo par de formas que
  // `useState` aceita (molde: `Precificacao.jsx`).
  const setCampo = (campo) => (v) => setFiltros((f) => ({
    ...f, [campo]: typeof v === "function" ? v(f[campo]) : v,
  }));
  const { departamento, comprador, status, estoque, busca, pagina,
          dtUltEntDe, dtUltEntAte } = filtros;
  const setDepartamento = setCampo("departamento");
  const setComprador = setCampo("comprador");
  const setStatus = setCampo("status");
  // Etapa 15, ponto 4: "" (todos) | "com" | "sem".
  const setEstoque = setCampo("estoque");
  const setBusca = setCampo("busca");
  const setPagina = setCampo("pagina");
  const setDtUltEntDe = setCampo("dtUltEntDe");
  const setDtUltEntAte = setCampo("dtUltEntAte");
  // Etapa 13, ponto 4: mesmo par `ordenar`/`dir` na URL, escrito tanto pelo
  // dropdown "Ordenar por" quanto pelo clique no cabeçalho da coluna (§3.3/§3.4)
  // — já sobrevive a "voltar" por conta própria (é a própria URL).
  const { ordenar, dir, aoOrdenar } = useOrdenacaoUrl("cobertura", "asc", setPagina);
  const [unidadeTotal, setUnidadeTotal] = useState("valor");

  // O carrinho é {codigo: quantidade}. Etapa 13, §6.2: vive em
  // `contexto/carrinho.jsx` (sessionStorage por aba), não mais em
  // `useState` local — no protótipo ele se perdia ao trocar de aba, sem
  // aviso (§2.4), e isso contradizia o que `historico/PLANO_v2_20260901.md`
  // §3 já tinha decidido para a Etapa 9 ("o carrinho sobrevive à troca de tela").
  const { carrinho, setCarrinho } = useCarrinho();
  const [salvando, setSalvando] = useState(false);
  const [confirmacao, setConfirmacao] = useState(null);

  useEffect(() => {
    api.opcoes().then(setOpcoes).catch((e) => setErro(e.detalhe));
    // MES_REFERENCIA vem daqui, e é o que nomeia as colunas de venda com o mês
    // de verdade em vez de "M-1"/"M-2"/"M-3".
    api.parametros().then(setParametros).catch(() => setParametros(null));
  }, []);

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.produtos({
        departamento: departamento || null,
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
  }, [departamento, comprador, status, estoque, busca, ordenar, dir, pagina,
      dtUltEntDe, dtUltEntAte, versaoDados]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const itens = dados?.itens ?? [];

  // Cache de produtos fora da PÁGINA atual (código → produto | null se a busca
  // falhou), para o total do carrinho poder somar TODOS os produtos
  // preenchidos, não só os da página. Mora aqui — não dentro de
  // `CarrinhoFlutuante` como antes — porque agora é o `totais` deste
  // componente-pai que depende dele; o painel "Ver itens" (que se desmonta ao
  // fechar) só RECEBE o cache pronto, não busca mais por conta própria.
  const [cacheProdutos, setCacheProdutos] = useState({});
  const emAndamento = useRef(new Set());

  // Busca sob demanda: todo código com quantidade digitada que não está na
  // página atual, ainda não está no cache e não tem requisição em voo. Roda
  // sempre — não só com o painel aberto — porque agora é a BARRA (sempre
  // visível) que precisa do total fechado; o `Set` evita pedir o mesmo
  // produto duas vezes, e falha de rede/404 grava `null`, o sinal de "este
  // item nunca vai fechar o total".
  useEffect(() => {
    const naPagina = new Set(itens.map((p) => String(p.codigo)));
    const faltantes = Object.entries(carrinho)
      .filter(([, qtd]) => (Number(String(qtd).replace(",", ".")) || 0) > 0)
      .map(([codigo]) => codigo)
      .filter((codigo) => !naPagina.has(codigo)
        && !(codigo in cacheProdutos) && !emAndamento.current.has(codigo));
    for (const codigo of faltantes) {
      emAndamento.current.add(codigo);
      api.produto(codigo)
        .then((p) => setCacheProdutos((c) => ({ ...c, [codigo]: p })))
        .catch(() => setCacheProdutos((c) => ({ ...c, [codigo]: null })))
        .finally(() => emAndamento.current.delete(codigo));
    }
  }, [carrinho, itens, cacheProdutos]);

  // O total soma TODOS os produtos preenchidos, não só os da página atual
  // (pedido do Diretor) — usando a página quando o produto está nela, e o
  // cache acima quando não está. `pendentes` conta o que ainda não voltou da
  // busca (o total ainda não fechou, mas o número mostrado já soma o que se
  // sabe); `falharam` conta o que a busca não achou (`cacheProdutos[c] ===
  // null`) — para ESSE item o total nunca vai fechar, e a barra precisa
  // dizer isso, não ficar tentando de novo silenciosamente.
  const totais = useMemo(() => {
    const t = { valor: 0, peso: 0, litros: 0, qtd: 0, linhas: 0, pendentes: 0, falharam: 0 };
    const naPagina = new Map(itens.map((p) => [String(p.codigo), p]));
    for (const [codigo, qtd] of Object.entries(carrinho)) {
      const n = Number(String(qtd).replace(",", ".")) || 0;
      if (n <= 0) continue;
      t.linhas += 1;
      const p = naPagina.get(codigo) ?? cacheProdutos[codigo];
      if (p === undefined) { t.pendentes += 1; continue; }
      if (p === null) { t.falharam += 1; continue; }
      const unidades = n * (p.fatorExibicao || 1);
      t.qtd += unidades;
      // `valorEntradaUnitario` (o valor da NOTA, já por unidade) — não
      // `custoGerencial` — é o preço que o Diretor confere linha a linha
      // (Tarefa 2 do pedido: "o preço unitário deve refletir o valor da
      // entrada/nota, não custo").
      t.valor += unidades * (p.valorEntradaUnitario ?? 0);
      t.peso += unidades * (p.pesoUnidade ?? 0);
      t.litros += unidades * (p.litragemUnidade ?? 0);
    }
    return t;
  }, [carrinho, itens, cacheProdutos]);

  async function salvar() {
    setSalvando(true);
    setErro(null);
    try {
      const lista = Object.entries(carrinho)
        .map(([codigo, qtd]) => ({ codigo: Number(codigo), quantidade: Number(String(qtd).replace(",", ".")) || 0 }))
        .filter((i) => i.quantidade > 0);
      const r = await api.salvarCarrinho(lista);
      const n = r.pedidos?.length ?? r.itens?.length ?? 0;
      setCarrinho({});
      setConfirmacao(`${numero(n)} pedido${n > 1 ? "s" : ""} salvo${n > 1 ? "s" : ""} com sucesso`);
    } catch (e) {
      setErro(e.status === 404 ? "Você não tem permissão para salvar pedido." : e.detalhe);
    } finally {
      setSalvando(false);
    }
  }

  return (
    <div className="px-4 pb-28 pt-3 md:px-6 md:pt-4">
      {confirmacao && (
        <div className="mb-3 flex items-center justify-between rounded-lg px-4 py-2.5"
             style={{ background: `${VERDE}12` }}>
          <span className="flex items-center gap-1.5 text-sm font-medium" style={{ color: VERDE }}>
            <Check size={14} aria-hidden="true" /> {confirmacao}
          </span>
          <span className="flex items-center gap-3">
            <button type="button" onClick={() => navegar("/pedidos-salvos")}
                    className="text-sm font-semibold underline" style={{ color: VERDE }}>
              Ir para Pedidos Salvos
            </button>
            <button type="button" onClick={() => setConfirmacao(null)}
                    aria-label="Dispensar aviso" className="text-gray-400">
              <X size={14} aria-hidden="true" />
            </button>
          </span>
        </div>
      )}

      <FiltrosCatalogo {...{ opcoes, departamento, setDepartamento, comprador, setComprador,
                             status, setStatus, estoque, setEstoque, ordenar, dir, aoOrdenar,
                             busca, setBusca, setPagina,
                             referencia: parametros?.data_referencia,
                             dtUltEntDe, setDtUltEntDe, dtUltEntAte, setDtUltEntAte }}
                       total={dados?.total} />
      {(dtUltEntDe || dtUltEntAte) && <AvisoSemEntrada />}

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && itens.length === 0 && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}
        {!carregando && !erro && itens.length > 0 && (
          <TabelaCatalogo itens={itens}
                          valorDe={(codigo) => carrinho[codigo]}
                          aoTrocar={(codigo, v) => setCarrinho((c) => ({ ...c, [codigo]: v }))}
                          ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar}
                          mesReferencia={parametros?.mes_referencia} parametros={parametros} />
        )}
      </div>

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}

      {totais.linhas > 0 && (
        <CarrinhoFlutuante totais={totais} unidade={unidadeTotal} setUnidade={setUnidadeTotal}
                           salvando={salvando} aoSalvar={salvar}
                           carrinho={carrinho} setCarrinho={setCarrinho} itens={itens}
                           cacheProdutos={cacheProdutos} />
      )}
    </div>
  );
}

/* ---------------------------------------------------------- barra carrinho --- */

const ID_PAINEL_ITENS = "painel-itens-carrinho";

/** Envelope fixo no rodapé que junta a barra de totais com o painel "Ver
 *  itens" (pedido do Diretor, Etapa 16: "deve ter um botão que mostre os
 *  pedidos que estão nele"). Painel e barra vivem no MESMO `fixed inset-x-0
 *  bottom-0 z-30` — não dois elementos fixos separados tentando se alinhar —
 *  porque a barra cresce (duas linhas no celular, uma na mesa) e calcular a
 *  altura para "grudar" um painel por cima dela seria reinventar o que o
 *  fluxo normal do flexbox já faz de graça: o painel entra ANTES da barra no
 *  DOM, então "abrir para cima" é só a ordem natural da coluna.
 *
 *  Cache de produtos buscados sob demanda (Tarefa 2): NÃO mora mais aqui —
 *  subiu para `Pedidos` (o componente-pai) porque agora é o TOTAL da barra,
 *  sempre visível, que precisa dele para fechar, não só este painel (que se
 *  desmonta toda vez que fecha: `{aberto && <PainelItens/>}`, e um estado
 *  local dele se perderia a cada reabertura). Aqui só se RECEBE
 *  `cacheProdutos` pronto, já compartilhado com `totais`. */
function CarrinhoFlutuante({ totais, unidade, setUnidade, salvando, aoSalvar,
                             carrinho, setCarrinho, itens, cacheProdutos }) {
  const [aberto, setAberto] = useState(false);
  const [confirmarTudo, setConfirmarTudo] = useState(false);
  const raiz = useRef(null);

  // Fecha com Esc e ao clicar fora — mas só enquanto NÃO há diálogo de
  // confirmação: o diálogo é modal (molde `ConfirmarExclusao` de
  // PedidosSalvos.jsx) e vive DENTRO deste mesmo `raiz`, então um clique nos
  // botões dele nunca conta como "fora".
  useEffect(() => {
    if (!aberto && !confirmarTudo) return;
    function aoTeclar(e) {
      if (e.key !== "Escape") return;
      if (confirmarTudo) setConfirmarTudo(false);
      else setAberto(false);
    }
    function aoClicarFora(e) {
      if (confirmarTudo) return;
      if (raiz.current && !raiz.current.contains(e.target)) setAberto(false);
    }
    document.addEventListener("keydown", aoTeclar);
    document.addEventListener("mousedown", aoClicarFora);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.removeEventListener("mousedown", aoClicarFora);
    };
  }, [aberto, confirmarTudo]);

  // Descartar UM item: tira a CHAVE do objeto (não grava ""), porque é a
  // chave que `Tabela`/`LinhaPedido` lê em `valor={carrinho[p.codigo]}` — sem
  // ela o campo volta a ficar vazio, e `totais` para de contar a linha (o
  // `if (n <= 0) continue` de cima nunca chega a rodar, porque a linha nem
  // existe mais em `Object.entries`).
  const descartarItem = useCallback((codigo) => {
    setCarrinho((c) => {
      const { [codigo]: _omitido, ...resto } = c;
      return resto;
    });
  }, [setCarrinho]);

  return (
    <div ref={raiz} className="fixed inset-x-0 bottom-0 z-30">
      {aberto && (
        <PainelItens id={ID_PAINEL_ITENS} carrinho={carrinho} itens={itens}
                     cacheProdutos={cacheProdutos}
                     aoDescartarItem={descartarItem}
                     aoPedirDescartarTudo={() => setConfirmarTudo(true)}
                     aoFechar={() => setAberto(false)} />
      )}
      <BarraCarrinho totais={totais} unidade={unidade} setUnidade={setUnidade}
                     salvando={salvando} aoSalvar={aoSalvar}
                     aberto={aberto} aoAlternarAberto={() => setAberto((v) => !v)} />
      {confirmarTudo && (
        <ConfirmarDescartarTudo quantidade={totais.linhas}
          aoCancelar={() => setConfirmarTudo(false)}
          aoConfirmar={() => {
            setCarrinho({});
            setConfirmarTudo(false);
            setAberto(false);
          }} />
      )}
    </div>
  );
}

function BarraCarrinho({ totais, unidade, setUnidade, salvando, aoSalvar, aberto, aoAlternarAberto }) {
  const valores = {
    valor: moeda(totais.valor),
    peso: `${numero(totais.peso, 0)} kg`,
    litros: `${numero(totais.litros, 0)} L`,
    qtd: `${numero(totais.qtd, 0)} un`,
  };
  return (
    <div className="border-t border-gray-200 bg-white px-4 py-3 shadow-lg md:px-6">
      <div className="mx-auto flex max-w-app flex-wrap items-center gap-3">
        <div>
          <div className="text-2xs text-gray-500">
            {numero(totais.linhas)} produto(s) no carrinho
            {totais.falharam > 0 && (
              // A busca deste código terminou e não achou o produto — o
              // total NUNCA vai fechar para ele sozinho (não há nova
              // tentativa automática). Fica permanente, não é um "carregando"
              // que passa: é um "isto ficou de fora".
              <span style={{ color: "#B98A2E" }}>
                {" "}· {numero(totais.falharam)} sem preço encontrado, fora do total
              </span>
            )}
          </div>
          <div className="num text-lg font-bold" style={{ color: NAVY }}>
            {valores[unidade]}
            {totais.pendentes > 0 && (
              // Ainda falta buscar produto(s) fora da página — o número acima
              // já soma o que se sabe, mas não é o total fechado ainda; dizer
              // isso aqui é melhor que deixar parecer definitivo (§ tarefa 2).
              <span className="ml-1.5 inline-flex items-center gap-1 align-middle text-xs font-normal text-gray-400">
                <Loader2 size={11} className="animate-spin" aria-hidden="true" /> calculando…
              </span>
            )}
          </div>
        </div>

        <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
          {UNIDADES.map((u) => (
            <button key={u.id} type="button" aria-pressed={unidade === u.id}
                    onClick={() => setUnidade(u.id)}
                    style={unidade === u.id ? { background: NAVY, color: "white" } : {}}
                    className="rounded-md px-2.5 py-1 text-xs font-medium text-gray-500">
              {u.rotulo}
            </button>
          ))}
        </div>

        <button type="button" onClick={aoAlternarAberto}
                aria-expanded={aberto} aria-controls={ID_PAINEL_ITENS}
                className="flex items-center gap-1 rounded-lg border border-gray-300 px-2.5 py-2 text-xs font-semibold text-gray-600">
          {aberto ? <ChevronDown size={14} aria-hidden="true" /> : <ChevronUp size={14} aria-hidden="true" />}
          Ver itens ({numero(totais.linhas)})
        </button>

        <button type="button" onClick={aoSalvar} disabled={salvando}
                className="ml-auto flex items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                style={{ background: NAVY }}>
          {salvando && <Loader2 size={14} className="animate-spin" aria-hidden="true" />}
          {salvando ? "Salvando…" : "Salvar pedido(s)"}
        </button>
      </div>
      <p className="mx-auto mt-1 max-w-app text-2xs text-gray-400">
        Um pedido por departamento — é como o Winthor importa. O carrinho fica salvo nesta
        aba (mesmo ao recarregar); abrir em outra aba começa vazio.
      </p>
    </div>
  );
}

/** Lista do que está no carrinho, item a item (Tarefa 1/2).
 *
 *  Cada linha decide de onde tira nome/departamento, em ordem de preferência:
 *  1. está na página atual (`itens`) — mesmo objeto que a tabela já usa;
 *  2. veio da busca sob demanda (`cacheProdutos[codigo]`, um objeto);
 *  3. a busca terminou e falhou (`cacheProdutos[codigo] === null`) — cai para
 *     mostrar só o código, sem travar o painel nem o descarte;
 *  4. ainda não terminou (`codigo` nem está em `cacheProdutos`) — spinner. */
function PainelItens({ id, carrinho, itens, cacheProdutos, aoDescartarItem, aoPedirDescartarTudo, aoFechar }) {
  const naPagina = new Map(itens.map((p) => [String(p.codigo), p]));
  const linhas = Object.entries(carrinho)
    .filter(([, qtd]) => (Number(String(qtd).replace(",", ".")) || 0) > 0);

  return (
    <div id={id} role="region" aria-label="Itens no carrinho"
         className="mx-auto max-w-app border-x border-t border-gray-200 bg-white px-4 pt-3 md:px-6">
      {/* ⚠ O cabeçalho tem SÓ o "X" de fechar, sozinho. "Descartar todos" fica
          no rodapé, longe dele, e de propósito: na primeira versão os dois
          eram vizinhos a 12px, e o usuário clicou no "X" achando que era o
          descartar — a lista fechava e nada era descartado. Dispensar e
          destruir não podem ficar coladas, ainda mais num painel onde cada
          linha já tem o seu próprio "X" que DESCARTA aquele item. */}
      <div className="flex items-center justify-between pb-2">
        <span className="text-xs font-semibold text-gray-500">Itens no carrinho</span>
        <button type="button" onClick={aoFechar} aria-label="Fechar lista de itens"
                className="rounded-md p-1 text-gray-400 hover:text-gray-600">
          <X size={14} aria-hidden="true" />
        </button>
      </div>
      <ul className="max-h-56 divide-y divide-gray-100 overflow-y-auto pb-2">
        {linhas.map(([codigo, qtd]) => {
          const doCache = cacheProdutos[codigo];
          const info = naPagina.get(codigo) ?? (doCache || undefined);
          const falhouBusca = !info && doCache === null;
          const emCaixa = info && (info.fatorExibicao || 1) > 1;
          // Preço unitário = `valorEntradaUnitario` (o valor da NOTA, já por
          // unidade — Tarefa 3 do pedido). Sem `info` (busca ainda não voltou
          // ou falhou) ou sem o campo (produto sem última entrada), não dá
          // para saber o preço: nunca mostra 0 no lugar, mostra "—".
          const qtdNum = Number(String(qtd).replace(",", ".")) || 0;
          const preco = info?.valorEntradaUnitario;
          const totalItem = preco != null ? qtdNum * (info.fatorExibicao || 1) * preco : null;
          return (
            <li key={codigo} className="flex items-center justify-between gap-2 py-2">
              <div className="min-w-0">
                {info ? (
                  <>
                    <div className="truncate text-sm font-medium text-gray-800">{info.nome}</div>
                    <div className="num text-2xs text-gray-400">
                      {codigo} · {info.departamento ?? "—"}
                    </div>
                  </>
                ) : falhouBusca ? (
                  // A busca terminou e não achou o produto (rede, 404, saiu do
                  // cadastro) — mostra só o código, e o descarte continua
                  // funcionando normalmente: não é motivo para travar o painel.
                  <div className="num text-sm text-gray-500">Produto {codigo}</div>
                ) : (
                  <div className="flex items-center gap-1.5 text-sm text-gray-400">
                    <Loader2 size={12} className="animate-spin" aria-hidden="true" />
                    <span className="num">Produto {codigo}</span>
                  </div>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-3">
                <div className="text-right">
                  <div className="num text-sm font-semibold text-gray-700">{qtd}</div>
                  {emCaixa && <div className="text-[9px] text-gray-400">caixas</div>}
                  {info ? (
                    <div className="num text-2xs text-gray-500">
                      {preco != null
                        ? <>{moeda(preco)} un · <span className="font-semibold text-gray-700">{moeda(totalItem)}</span></>
                        : "preço desconhecido"}
                    </div>
                  ) : (
                    // Ainda buscando ou a busca falhou: sem `info` não há
                    // `fatorExibicao` nem preço — nunca imprime "R$ 0,00"
                    // como se fosse valor real (regra do pedido, Tarefa 3).
                    <div className="text-2xs text-gray-400">preço desconhecido</div>
                  )}
                </div>
                {/* Lixeira vermelha contornada, no mesmo desenho do "Descartar
                    todos" do rodapé — a ação é a mesma, só muda o alcance.
                    Deixou de ser um "X" cinza de propósito: com o "X" aqui, o
                    único outro "X" do painel (fechar, no cabeçalho) era lido
                    como "descartar tudo" e a lista fechava sem descartar nada.
                    Agora "X" significa fechar em todo o painel, e lixeira
                    significa descartar — um símbolo, um sentido. */}
                <button type="button" onClick={() => aoDescartarItem(codigo)}
                        aria-label={`Descartar o produto ${codigo} do carrinho`}
                        className="rounded-md border p-1.5"
                        style={{ color: RED, borderColor: RED }}>
                  <Trash2 size={14} aria-hidden="true" />
                </button>
              </div>
            </li>
          );
        })}
      </ul>
      {/* Rodapé: a ação destrutiva de conjunto, como BOTÃO de verdade
          (contornado, com rótulo), não como link espremido ao lado do "X". */}
      <div className="flex justify-end border-t border-gray-100 py-2">
        <button type="button" onClick={aoPedirDescartarTudo}
                className="flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-xs font-semibold"
                style={{ color: RED, borderColor: RED }}>
          <Trash2 size={12} aria-hidden="true" /> Descartar todos
        </button>
      </div>
    </div>
  );
}

/* O molde é `ConfirmarExclusao` de PedidosSalvos.jsx — mesmo diálogo modal,
 * mesmo texto de aviso sem desfazer. Descartar UM item não passa por aqui
 * (é clique óbvio e refazível: basta digitar de novo); descartar TODOS
 * apaga de uma vez o que várias pessoas podem ter levado minutos digitando. */
function ConfirmarDescartarTudo({ quantidade, aoCancelar, aoConfirmar }) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 px-4"
         role="dialog" aria-modal="true" aria-labelledby="titulo-descartar-tudo">
      <div className="w-full max-w-sm rounded-xl bg-white p-5 shadow-lg">
        <div className="flex items-start gap-2">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" style={{ color: RED }} aria-hidden="true" />
          <div>
            <h2 id="titulo-descartar-tudo" className="font-semibold text-gray-900">
              Descartar {numero(quantidade)} item(ns) do carrinho?
            </h2>
            <p className="mt-2 text-xs text-gray-500">
              O que foi digitado no campo Pedido de cada produto é apagado. Não há como desfazer.
            </p>
          </div>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button type="button" onClick={aoCancelar}
                  className="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700">
            Cancelar
          </button>
          <button type="button" onClick={aoConfirmar}
                  className="rounded-md px-3 py-1.5 text-sm font-semibold text-white"
                  style={{ background: RED }}>
            Descartar todos
          </button>
        </div>
      </div>
    </div>
  );
}

