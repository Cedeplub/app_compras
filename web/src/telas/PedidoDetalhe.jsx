import { useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ChevronLeft, FileSpreadsheet, Loader2, Plus, Printer, Search, Trash2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
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

export default function PedidoDetalhe() {
  const { id } = useParams();
  const navegar = useNavigate();
  const [pedido, setPedido] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [adicionando, setAdicionando] = useState(false);
  const [imprimindo, setImprimindo] = useState(false);

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
      <button type="button" onClick={() => navegar("/pedidos-salvos")}
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
              <th className="px-2 py-2 text-left font-medium">Código</th>
              <th className="min-w-[240px] px-3 py-2 text-left font-medium">Produto</th>
              <th className="px-2 py-2 text-center font-medium">Embalagem</th>
              <th className="px-2 py-2 text-center font-medium">Qtd.</th>
              <th className="px-2 py-2 text-center font-medium">Em unidades</th>
              <th className="px-2 py-2 text-center font-medium">Preço unit.</th>
              <th className="px-2 py-2 text-right font-medium">Total</th>
              {podeEditar && <th className="px-2 py-2" />}
            </tr>
          </thead>
          <tbody>
            {pedido.itens.map((it) => (
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
          <Plus size={14} aria-hidden="true" /> Adicionar produtos ao pedido
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
function AdicionarProdutos({ pedido, aoCancelar, aoConcluir }) {
  const [busca, setBusca] = useState("");
  const [lista, setLista] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [quantidades, setQuantidades] = useState({});
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState(null);

  const jaNoPedido = new Set(pedido.itens.map((i) => i.codigo));

  const buscar = useCallback(async () => {
    setCarregando(true);
    try {
      const d = await api.produtos({
        departamento: pedido.fornecedor, status: "Ativo",
        busca: busca || null, ordenacao: "cobertura", porPagina: 50,
      });
      setLista(d.itens);
    } catch (e) {
      setErro(e.detalhe);
    } finally {
      setCarregando(false);
    }
  }, [pedido.fornecedor, busca]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  async function confirmar() {
    setSalvando(true);
    setErro(null);
    try {
      const novos = Object.entries(quantidades)
        .map(([codigo, q]) => ({ codigo: Number(codigo), quantidade: Number(String(q).replace(",", ".")) || 0 }))
        .filter((i) => i.quantidade > 0);
      // Um PUT por item: a rota de item é a mesma que a edição usa, e assim não
      // existe um segundo caminho de escrita que possa divergir dela.
      for (const i of novos) await api.gravarItemPedido(pedido.id, i.codigo, { quantidade: i.quantidade });
      await aoConcluir();
    } catch (e) {
      setErro(e.detalhe);
    } finally {
      setSalvando(false);
    }
  }

  const escolhidos = Object.values(quantidades).filter((q) => Number(String(q).replace(",", ".")) > 0).length;

  return (
    <div className="px-4 pb-8 pt-3 md:px-6 md:pt-4">
      <button type="button" onClick={aoCancelar}
              className="mb-3 flex items-center gap-1 text-sm font-medium" style={{ color: NAVY }}>
        <ChevronLeft size={14} aria-hidden="true" /> Cancelar e voltar ao pedido
      </button>

      <h2 className="text-lg font-semibold text-gray-900">
        Adicionar produtos — {pedido.fornecedor}
      </h2>
      <p className="mt-0.5 text-xs text-gray-500">
        Só produtos deste departamento: um pedido é sempre de um só, porque é assim que o
        Winthor importa.
      </p>

      <div className="relative mt-3 max-w-sm">
        <input type="search" value={busca} onChange={(e) => setBusca(e.target.value)}
               aria-label="Buscar produto" placeholder="Nome ou código…"
               className="w-full rounded-lg border border-gray-200 py-2 pl-8 pr-3 text-sm" />
        <Search size={13} aria-hidden="true" className="absolute left-2.5 top-2.5 text-gray-400" />
      </div>

      {erro && <div className="mt-3"><Erro mensagem={erro} /></div>}

      <div className="mt-3">
        {carregando && <Carregando />}
        {!carregando && lista?.length === 0 && (
          <div className="py-8 text-center text-sm text-gray-400">Nenhum produto nesse filtro.</div>
        )}
        {!carregando && lista?.length > 0 && (
          <div className="overflow-x-auto rounded-lg border border-gray-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
                  <th className="px-2 py-2 text-left font-medium">Código</th>
                  <th className="min-w-[240px] px-3 py-2 text-left font-medium">Produto</th>
                  <th className="px-2 py-2 text-center font-medium">EST+PED</th>
                  <th className="px-2 py-2 text-center font-medium">Cob./Alvo</th>
                  <th className="px-2 py-2 text-center font-medium">Sugestão</th>
                  <th className="px-3 py-2 text-center font-medium">Qtd.</th>
                </tr>
              </thead>
              <tbody>
                {lista.map((p) => (
                  <tr key={p.codigo} className="border-t border-gray-100">
                    <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
                    <td className="px-3 py-2">
                      <div className="font-medium text-gray-800">{p.nome}</div>
                      {jaNoPedido.has(p.codigo) && (
                        // Sem este aviso a pessoa digitaria de novo achando que
                        // soma, quando o servidor SUBSTITUI (a chave é
                        // pedido+produto).
                        <div className="text-2xs" style={{ color: "#B98A2E" }}>
                          já está no pedido — digitar aqui substitui a quantidade
                        </div>
                      )}
                    </td>
                    <td className="num px-2 py-2 text-center">{numero(p.estPend, 0)}</td>
                    <td className="num px-2 py-2 text-center">
                      {numero(p.mesesCobertura, 1)}
                      <span className="text-gray-400"> / {numero(p.coberturaAlvo, 1)}</span>
                    </td>
                    <td className="px-2 py-2 text-center">
                      {p.sugCobertura > 0 ? (
                        <button type="button"
                                onClick={() => setQuantidades((q) => ({ ...q, [p.codigo]: String(p.sugCobertura) }))}
                                className="num rounded-md px-2 py-1 text-2xs font-semibold"
                                style={{ background: `${NAVY}12`, color: NAVY }}>
                          {numero(p.sugCobertura, 0)}
                        </button>
                      ) : <span className="text-2xs text-gray-300">—</span>}
                    </td>
                    <td className="px-3 py-1.5 text-center">
                      <input type="text" inputMode="decimal"
                             value={quantidades[p.codigo] ?? ""}
                             aria-label={`Quantidade do produto ${p.codigo}`}
                             onChange={(e) => setQuantidades((q) => ({ ...q, [p.codigo]: e.target.value }))}
                             className="num w-[72px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="mt-4 flex items-center gap-3">
        <button type="button" onClick={confirmar} disabled={salvando || escolhidos === 0}
                className="flex items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
                style={{ background: NAVY }}>
          {salvando && <Loader2 size={14} className="animate-spin" aria-hidden="true" />}
          {salvando ? "Adicionando…" : `Confirmar ${numero(escolhidos)} produto(s)`}
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
 * gera. */
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

        <h1 className="mt-6 text-xl font-bold" style={{ color: NAVY }}>Orçamento de compra</h1>
        <p className="num mt-1 text-sm text-gray-600">
          Pedido #{pedido.id} · {pedido.fornecedor} · {pedido.status}
        </p>

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
