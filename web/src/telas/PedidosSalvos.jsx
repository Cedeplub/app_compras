import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { AlertTriangle, ChevronDown, Download, FileSpreadsheet, Filter, Loader2, Trash2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro, Vazio } from "../componentes/Basicos.jsx";
import { COR_STATUS, ROTULO_AVANCAR, ROTULO_VOLTAR, STATUS,
         avancarEhExportar, podeAvancar, podeVoltar } from "../pedidoStatus.js";
import { moeda, numero } from "../formato.js";

/* Tela — Pedidos Salvos (PROTOTIPO.md §2.5, .jsx linha 1729). */

const NAVY = "#375DA8";
const RED = "#DE434B";

export default function PedidosSalvos() {
  const navegar = useNavigate();
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  // Nasce com os dois status "em andamento" ligados, como no protótipo (§2.5):
  // é o recorte de quem abre a tela para trabalhar, não para consultar.
  const [statusAtivos, setStatusAtivos] = useState(["Rascunho", "Orçamento Enviado"]);
  const [busca, setBusca] = useState("");
  const [ocupado, setOcupado] = useState(null);       // id do pedido em ação
  const [aExcluir, setAExcluir] = useState(null);     // pedido aguardando confirmação

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.pedidos({ status: statusAtivos, busca: busca || null, porPagina: 100 }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [statusAtivos, busca]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  async function agir(id, acao) {
    setOcupado(id);
    setErro(null);
    try {
      await acao();
      await buscar();
    } catch (e) {
      setErro(e.status === 404 ? "Você não tem permissão para esta ação." : e.detalhe);
    } finally {
      setOcupado(null);
    }
  }

  const pedidos = dados?.itens ?? [];
  const semNenhum = !carregando && !erro && pedidos.length === 0 && statusAtivos.length === STATUS.length && !busca;

  return (
    <div className="px-4 pb-6 pt-3 md:px-6 md:pt-4">
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <div className="mb-1 flex items-center gap-1 text-xs text-gray-500">
            <Filter size={11} aria-hidden="true" /> Status (pode combinar)
          </div>
          <div className="flex flex-wrap gap-1.5">
            {STATUS.map((s) => {
              const on = statusAtivos.includes(s);
              const cor = COR_STATUS[s];
              return (
                <button key={s} type="button" aria-pressed={on}
                        onClick={() => setStatusAtivos((a) =>
                          a.includes(s) ? a.filter((x) => x !== s) : [...a, s])}
                        style={on ? { background: cor, color: "white", borderColor: cor }
                                  : { color: cor, borderColor: `${cor}55` }}
                        className="rounded-full border px-2.5 py-1 text-xs font-medium">
                  {s}
                </button>
              );
            })}
          </div>
        </div>
        <div className="w-56">
          <div className="mb-1 text-xs text-gray-500">Buscar</div>
          <input type="search" value={busca} onChange={(e) => setBusca(e.target.value)}
                 aria-label="Buscar pedido" placeholder="Departamento ou nº do pedido…"
                 className="w-full rounded-lg border border-gray-200 px-2.5 py-1.5 text-sm" />
        </div>
        <div className="num ml-auto text-xs text-gray-500">{numero(dados?.total)} pedido(s)</div>
      </div>

      {erro && <div className="mt-3"><Erro mensagem={erro} aoTentarDeNovo={buscar} /></div>}

      <div className="mt-4">
        {carregando && <Carregando />}
        {semNenhum && (
          <Vazio titulo="Nenhum pedido salvo ainda."
                 detalhe="Monte um carrinho em Pedidos e use “Salvar pedido(s)”." />
        )}
        {!carregando && !erro && pedidos.length === 0 && !semNenhum && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}

        <ul className="space-y-2">
          {pedidos.map((p) => (
            <CartaoPedido key={p.id} p={p} ocupado={ocupado === p.id}
                          aoAbrir={() => navegar(`/pedidos-salvos/${p.id}`)}
                          aoAvancar={() => agir(p.id, async () => {
                            // De Fechado, avançar É exportar: o arquivo do
                            // Winthor e a mudança de status saem juntos.
                            if (avancarEhExportar(p.status)) await baixar(p.id, "winthor");
                            else await api.avancarPedido(p.id);
                          })}
                          aoVoltar={() => agir(p.id, () => api.voltarPedido(p.id))}
                          aoExcel={() => agir(p.id, () => baixar(p.id, "excel"))}
                          aoWinthor={() => agir(p.id, () => baixar(p.id, "winthor"))}
                          aoExcluir={() => setAExcluir(p)} />
          ))}
        </ul>
      </div>

      {aExcluir && (
        <ConfirmarExclusao pedido={aExcluir} aoCancelar={() => setAExcluir(null)}
                           aoConfirmar={async () => {
                             const p = aExcluir;
                             setAExcluir(null);
                             await agir(p.id, () => api.excluirPedido(p.id));
                           }} />
      )}
    </div>
  );
}

/** Dispara o download no navegador. O sandbox do artefato não permitiria isso,
 *  mas aqui é aplicação servida pelo próprio FastAPI. */
async function baixar(id, formato) {
  const { blob, nome } = await api.baixarExportacao(id, formato);
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function CartaoPedido({ p, ocupado, aoAbrir, aoAvancar, aoVoltar, aoExcel, aoWinthor, aoExcluir }) {
  const cor = COR_STATUS[p.status] ?? "#6B7280";
  const soLeitura = p.status === "Fechado" || p.status === "Exportado";
  return (
    <li className="rounded-xl border border-gray-200 px-3.5 py-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="num text-xs text-gray-400">#{p.id}</span>
            <span className="truncate font-semibold text-gray-800">{p.fornecedor}</span>
            <span className="rounded-full px-2 py-0.5 text-2xs font-bold"
                  style={{ background: `${cor}18`, color: cor }}>
              {p.status}
            </span>
          </div>
          <p className="num mt-0.5 text-2xs text-gray-500">
            {numero(p.qtdItens)} item(ns) · {moeda(p.valorTotal)}
            {p.criadoEm && ` · criado em ${p.criadoEm.slice(8, 10)}/${p.criadoEm.slice(5, 7)}/${p.criadoEm.slice(2, 4)}`}
            {p.criadoPor && ` por ${p.criadoPor}`}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ocupado && <Loader2 size={14} className="animate-spin text-gray-400" aria-hidden="true" />}

          <Acao onClick={aoAbrir}>{soLeitura ? "Ver" : "Ver/editar"}</Acao>
          <Acao onClick={aoExcel} icone={FileSpreadsheet}>Excel</Acao>

          {p.status === "Exportado" && (
            <Acao onClick={aoWinthor} icone={Download}>Baixar de novo</Acao>
          )}

          {podeAvancar(p.status) && (
            <Acao onClick={aoAvancar} destaque cor={cor} desabilitado={ocupado}>
              {ROTULO_AVANCAR[p.status]}
            </Acao>
          )}
          {podeVoltar(p.status) && (
            <Acao onClick={aoVoltar} desabilitado={ocupado}>{ROTULO_VOLTAR[p.status]}</Acao>
          )}

          <Acao onClick={aoExcluir} icone={Trash2} cor={RED}>Excluir</Acao>
        </div>
      </div>
    </li>
  );
}

function Acao({ children, onClick, icone: Icone, destaque, cor = NAVY, desabilitado }) {
  return (
    <button type="button" onClick={onClick} disabled={desabilitado}
            className="flex items-center gap-1 rounded-md border px-2 py-1 text-2xs font-semibold disabled:opacity-40"
            style={destaque
              ? { background: cor, color: "white", borderColor: cor }
              : { color: cor, borderColor: `${cor}44` }}>
      {Icone && <Icone size={11} aria-hidden="true" />}
      {children}
    </button>
  );
}

/* O protótipo exclui na hora, sem diálogo (§8: "Sem confirmação de exclusão").
 * Apagar um pedido leva junto os itens e todo o histórico de status, por
 * cascata — não há desfazer. Um clique errado ao lado de "Ver/editar" custaria
 * o trabalho inteiro de montar o pedido. */
function ConfirmarExclusao({ pedido, aoCancelar, aoConfirmar }) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 px-4"
         role="dialog" aria-modal="true" aria-labelledby="titulo-excluir">
      <div className="w-full max-w-sm rounded-xl bg-white p-5 shadow-lg">
        <div className="flex items-start gap-2">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" style={{ color: RED }} aria-hidden="true" />
          <div>
            <h2 id="titulo-excluir" className="font-semibold text-gray-900">Excluir o pedido #{pedido.id}?</h2>
            <p className="mt-1 text-sm text-gray-600">
              {pedido.fornecedor} · {numero(pedido.qtdItens)} item(ns) · {moeda(pedido.valorTotal)}
            </p>
            <p className="mt-2 text-xs text-gray-500">
              Os itens e o histórico de status vão junto. Não há como desfazer.
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
            Excluir
          </button>
        </div>
      </div>
    </div>
  );
}
