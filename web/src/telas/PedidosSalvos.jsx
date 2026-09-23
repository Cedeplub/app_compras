import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { AlertTriangle, Download, Filter, Loader2, Trash2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { useEstadoPersistente } from "../estadoTela.js";
import { Carregando, Erro, Vazio } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { useOrdenacaoUrl } from "../componentes/CabecalhoOrdenavel.jsx";
import { COR_STATUS, ROTULO_AVANCAR, ROTULO_VOLTAR, STATUS,
         avancarEhExportar, podeAvancar, podeVoltar } from "../pedidoStatus.js";
import { moeda, numero } from "../formato.js";

/* Tela — Pedidos Salvos (PROTOTIPO.md §2.5, .jsx linha 1729). */

const NAVY = "#375DA8";
const RED = "#DE434B";

// Etapa 16: filtros sobrevivem a "voltar" de `/pedidos-salvos/:id` (que já
// usa `navegar(-1)`) — mesmo mecanismo de `Precificacao.jsx`. Nasce com os
// dois status "em andamento" ligados, como no protótipo (§2.5): é o recorte
// de quem abre a tela para trabalhar, não para consultar.
const FILTROS_PADRAO = { statusAtivos: ["Rascunho", "Orçamento Enviado"], busca: "" };

export default function PedidosSalvos() {
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [filtros, setFiltros] = useEstadoPersistente(
    "app_compras_filtros_pedidos_salvos_v1", FILTROS_PADRAO);
  const setCampo = (campo) => (v) => setFiltros((f) => ({
    ...f, [campo]: typeof v === "function" ? v(f[campo]) : v,
  }));
  const { statusAtivos, busca } = filtros;
  const setStatusAtivos = setCampo("statusAtivos");
  const setBusca = setCampo("busca");
  const [ocupado, setOcupado] = useState(null);       // id do pedido em ação
  const [aExcluir, setAExcluir] = useState(null);     // pedido aguardando confirmação
  // Etapa 13, ponto 4: lista PAGINADA no servidor (§3.1), mesmo componente
  // `CabecalhoOrdenavel` em `as="button"` (§3.4) — sem `<table>` aqui.
  const { ordenar, dir, aoOrdenar } = useOrdenacaoUrl("criadoEm", "desc");

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.pedidos({ status: statusAtivos, busca: busca || null, ordenar, dir, porPagina: 100 }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [statusAtivos, busca, ordenar, dir]);

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
        <div>
          <div className="mb-1 text-xs text-gray-500">Ordenar por</div>
          {/* Sem `<table>` nesta tela (lista de cartões) — mesmo componente
              `CabecalhoOrdenavel`, em `as="button"` (§3.4). */}
          <div className="flex flex-wrap gap-x-3 gap-y-1 rounded-lg border border-gray-200 px-2.5 py-1.5 text-xs">
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="criadoEm" padrao="desc">Criado em</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="id" padrao="desc">#</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="fornecedor" padrao="asc">Departamento</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="status" padrao="asc">Status</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="valorTotal" padrao="desc">Valor</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="qtdItens" padrao="desc">Itens</CabecalhoOrdenavel>
          </div>
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
                          aoAvancar={() => agir(p.id, async () => {
                            // De Fechado, avançar É exportar: o arquivo do
                            // Winthor e a mudança de status saem juntos.
                            if (avancarEhExportar(p.status)) await baixar(p.id, "winthor");
                            else await api.avancarPedido(p.id);
                          })}
                          aoVoltar={() => agir(p.id, () => api.voltarPedido(p.id))}
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

function CartaoPedido({ p, ocupado, aoAvancar, aoVoltar, aoWinthor, aoExcluir }) {
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

          {/* Exportar documento (PDF e Excel) mora no DETALHE, não aqui: é ação
              de quem abriu o pedido e está vendo o que vai no arquivo. Na lista
              ficam só as ações de fluxo — avançar, desfazer, excluir — e o
              "baixar de novo" do arquivo do Winthor, que é o único download que
              faz sentido sem abrir, porque o pedido já foi conferido antes de
              ser exportado.
              Ajuste 4 do revisor (13/09): "Ver/editar" é NAVEGAÇÃO — vira
              `<Link>` para abrir em aba nova com ctrl+clique (pedido do
              Diretor, §6.1, era mais geral que só telas de produto). As
              quatro abaixo (avançar, voltar, baixar de novo, excluir) GRAVAM
              no clique — continuam `<button>` de propósito: um `<Link>` que
              grava dispara a ação E abre aba ao mesmo tempo. */}
          <AcaoLink to={`/pedidos-salvos/${p.id}`}>{soLeitura ? "Ver" : "Ver/editar"}</AcaoLink>

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

/* Mesma aparência de `Acao`, mas `<Link>` — só para a ação que NAVEGA
 * (ajuste 4 do revisor). Nunca usar para algo que grava: ctrl+clique num
 * `<Link>` abre aba nova SEM cancelar a ação original, então um `<Link>`
 * que também grava dispara a gravação duas vezes (aba original + aba nova). */
function AcaoLink({ children, to }) {
  return (
    <Link to={to}
          className="flex items-center gap-1 rounded-md border px-2 py-1 text-2xs font-semibold"
          style={{ color: NAVY, borderColor: `${NAVY}44` }}>
      {children}
    </Link>
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
