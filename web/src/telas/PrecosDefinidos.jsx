import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { AlertTriangle, FileSpreadsheet, Filter, Loader2, Trash2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro, Vazio } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { useOrdenacaoUrl } from "../componentes/CabecalhoOrdenavel.jsx";
import { COR_STATUS, ROTULO_AVANCAR, STATUS, podeAvancar, textoConferencia } from "../lotePrecoStatus.js";
import { numero } from "../formato.js";

/* Tela — Preços Definidos (PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §6.3, molde
 * `PedidosSalvos.jsx`). O lote de preços é o documento que sai da decisão da
 * Precificação/Decisão do SKU em direção a quem digita no Winthor (rotina
 * 201) — antes desta etapa, "gravar o preço" não deixava rastro nenhum além
 * de um número pequeno na tela (relato do Diretor, §1).
 *
 * Diferença central em relação ao `.jsx` novo do Diretor
 * (painel_cedep_prototipo_090926.jsx, linhas 2114-2382): lá existe um terceiro
 * status "Aplicado", clicável. Aqui só existem Rascunho e Enviado — "aplicado"
 * é SITUAÇÃO POR ITEM, medida contra o banco (ver lotePrecoStatus.js), porque
 * não há usuário no app para quem aplica o preço no Winthor dar aquele
 * clique, e o sistema já sabe conferir sozinho.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";

export default function PrecosDefinidos() {
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  // Os dois status existentes, ambos ligados por padrão — diferente de
  // PedidosSalvos (4 status, 2 "em andamento"), aqui isso já é "todos".
  const [statusAtivos, setStatusAtivos] = useState(["Rascunho", "Enviado"]);
  const [ocupado, setOcupado] = useState(null);
  const [aExcluir, setAExcluir] = useState(null);
  // Etapa 13, ponto 4: lista PAGINADA no servidor (§3.1) — mesmo componente
  // `CabecalhoOrdenavel`, em modo `as="button"` (§3.4): não há `<table>` aqui,
  // a lista é de cartões, então não existe `<th>` para anexar. Sem página
  // própria nesta tela (100 itens de uma vez), então sem reset de página.
  const { ordenar, dir, aoOrdenar } = useOrdenacaoUrl("criadoEm", "desc");

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.lotesPreco({ status: statusAtivos, ordenar, dir, porPagina: 100 }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [statusAtivos, ordenar, dir]);

  useEffect(() => { buscar(); }, [buscar]);

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

  const lotes = dados?.itens ?? [];
  const semNenhum = !carregando && !erro && lotes.length === 0 && statusAtivos.length === STATUS.length;
  const carimbo = textoConferencia(dados?.atualizacao);

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
        <div>
          <div className="mb-1 text-xs text-gray-500">Ordenar por</div>
          {/* Sem `<table>` nesta tela (lista de cartões) — mesmo componente
              `CabecalhoOrdenavel`, em `as="button"` (§3.4), para não inventar
              um segundo controle de ordenação só para telas em cartão. */}
          <div className="flex flex-wrap gap-x-3 gap-y-1 rounded-lg border border-gray-200 px-2.5 py-1.5 text-xs">
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="criadoEm" padrao="desc">Criado em</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="id" padrao="desc">#</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="status" padrao="asc">Status</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="qtdItens" padrao="desc">Itens</CabecalhoOrdenavel>
            <CabecalhoOrdenavel as="button" ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="qtdAplicados" padrao="desc">Aplicados</CabecalhoOrdenavel>
          </div>
        </div>
        <div className="num ml-auto text-xs text-gray-500">{numero(dados?.total)} lote(s)</div>
      </div>

      {/* Etapa 12 §4.5: a conferência de "aplicado" tem a idade do último build
          do dbt — sem dizer isso na cara, um preço aplicado às 10h aparece
          pendente até a carga seguinte e o indicador perde credibilidade. */}
      {carimbo && (
        <p className="mt-2 text-2xs text-gray-400">
          Coluna "Aplicados" {carimbo} — a próxima carga do dbt pode mudar o número.
        </p>
      )}

      {erro && <div className="mt-3"><Erro mensagem={erro} aoTentarDeNovo={buscar} /></div>}

      <div className="mt-4">
        {carregando && <Carregando />}
        {semNenhum && (
          <Vazio titulo="Nenhum lote de preço ainda."
                 detalhe='Defina preços na tela de Precificação ou na Decisão do SKU — o botão "Definir preços" cria o primeiro lote.' />
        )}
        {!carregando && !erro && lotes.length === 0 && !semNenhum && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}

        <ul className="space-y-2">
          {lotes.map((l) => (
            <CartaoLote key={l.id} l={l} ocupado={ocupado === l.id}
                        aoAvancar={() => agir(l.id, () => api.avancarLotePreco(l.id))}
                        aoExcel={() => agir(l.id, () => baixar(() => api.baixarExcelLotePreco(l.id)))}
                        aoExcluir={() => setAExcluir(l)} />
          ))}
        </ul>
      </div>

      {aExcluir && (
        <ConfirmarExclusao lote={aExcluir} aoCancelar={() => setAExcluir(null)}
                           aoConfirmar={async () => {
                             const l = aExcluir;
                             setAExcluir(null);
                             await agir(l.id, () => api.excluirLotePreco(l.id));
                           }} />
      )}
    </div>
  );
}

/** Dispara o download no navegador — mesmo padrão de PedidosSalvos.jsx/
 *  PedidoDetalhe.jsx, agora recebendo a chamada de API já pronta (os dois
 *  arquivos da 201 e o Excel de conferência têm assinaturas diferentes). */
async function baixar(chamada) {
  const { blob, nome } = await chamada();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function CartaoLote({ l, ocupado, aoAvancar, aoExcel, aoExcluir }) {
  const cor = COR_STATUS[l.status] ?? "#6B7280";
  const qtdItens = l.qtdItens ?? 0;
  const qtdAplicados = l.qtdAplicados ?? 0;
  return (
    <li className="rounded-xl border border-gray-200 px-3.5 py-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="num text-xs text-gray-400">#{l.id}</span>
            <span className="rounded-full px-2 py-0.5 text-2xs font-bold"
                  style={{ background: `${cor}18`, color: cor }}>
              {l.status}
            </span>
            {l.observacao && (
              <span className="truncate text-2xs text-gray-500">{l.observacao}</span>
            )}
          </div>
          <p className="num mt-0.5 text-2xs text-gray-500">
            {numero(qtdItens)} item(ns)
            {/* "Aplicados" é SITUAÇÃO medida (§4.5), não status do lote — por
                isso aparece como agregado aqui, ao lado da contagem de itens,
                não como mais um chip de status. */}
            {" · "}{numero(qtdAplicados)} de {numero(qtdItens)} aplicado(s)
            {l.criadoEm && ` · criado em ${l.criadoEm.slice(8, 10)}/${l.criadoEm.slice(5, 7)}/${l.criadoEm.slice(2, 4)}`}
            {l.criadoPor && ` por ${l.criadoPor}`}
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ocupado && <Loader2 size={14} className="animate-spin text-gray-400" aria-hidden="true" />}

          {/* Ajuste 4 do revisor (13/09): "Ver/editar" NAVEGA — vira `<Link>`
              para abrir em aba nova com ctrl+clique (mesmo caso de
              PedidosSalvos.jsx). Excel, Avançar e Excluir GRAVAM/baixam no
              clique — continuam `<button>`. */}
          <AcaoLink to={`/precos-definidos/${l.id}`}>Ver/editar</AcaoLink>
          <Acao onClick={aoExcel} icone={FileSpreadsheet}>Excel</Acao>
          {/* Os dois arquivos da 201 (Achado do revisor #1) NÃO baixam daqui.
              Só o detalhe do lote sabe quantos itens ficaram de fora do
              arquivo (`excluidos201`, calculado em LotePrecoDetalhe.jsx a
              partir de `entraArquivo201` — campo que esta listagem, `GET
              /api/lotes-preco`, não traz por item). Um botão de download
              aqui baixaria o arquivo sem a pessoa ver, na mesma tela,
              quantos produtos ficaram de fora e por quê; e §4.6 é explícito:
              "arquivo que sai menor do que o lote sem dizer por quê é pior
              que arquivo nenhum". "Ver/editar" leva ao detalhe, que mostra a
              contagem ANTES dos dois botões de download — por isso a lista
              não duplica o atalho. */}

          {podeAvancar(l.status) && (
            <Acao onClick={aoAvancar} destaque cor={cor} desabilitado={ocupado}>
              {ROTULO_AVANCAR[l.status]}
            </Acao>
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
 * (ajuste 4 do revisor, mesmo componente de PedidosSalvos.jsx). Nunca usar
 * para algo que grava: um `<Link>` que também grava dispara a gravação e a
 * navegação juntas, e ctrl+clique não cancela a gravação. */
function AcaoLink({ children, to }) {
  return (
    <Link to={to}
          className="flex items-center gap-1 rounded-md border px-2 py-1 text-2xs font-semibold"
          style={{ color: NAVY, borderColor: `${NAVY}44` }}>
      {children}
    </Link>
  );
}

/* Molde: `ConfirmarExclusao` de PedidosSalvos.jsx. A diferença que precisa
 * ficar dita: excluir o LOTE não desfaz a decisão de preço — ela continua
 * gravada em APP_DECISAO_PRECO, com histórico. Só o documento (e o arquivo
 * pronto pra 201) desaparece. Sem esta linha, quem exclui acha que desfez a
 * decisão inteira. */
function ConfirmarExclusao({ lote, aoCancelar, aoConfirmar }) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 px-4"
         role="dialog" aria-modal="true" aria-labelledby="titulo-excluir-lote">
      <div className="w-full max-w-sm rounded-xl bg-white p-5 shadow-lg">
        <div className="flex items-start gap-2">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" style={{ color: RED }} aria-hidden="true" />
          <div>
            <h2 id="titulo-excluir-lote" className="font-semibold text-gray-900">
              Excluir o lote #{lote.id}?
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              {numero(lote.qtdItens ?? 0)} item(ns) · status {lote.status}
            </p>
            <p className="mt-2 text-xs text-gray-500">
              Isto apaga só o DOCUMENTO e o histórico de status dele. Os preços já
              decididos continuam gravados — nada aqui desfaz a decisão.
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
