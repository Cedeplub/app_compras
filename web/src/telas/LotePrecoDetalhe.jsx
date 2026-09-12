import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  ChevronLeft, Download, FileSpreadsheet, Loader2, Printer, Trash2,
} from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { ordenarLista } from "../componentes/CabecalhoOrdenavel.jsx";
import {
  COR_SITUACAO, COR_STATUS, ROTULO_AVANCAR, ROTULO_SITUACAO, ROTULO_VOLTAR,
  podeAvancar, podeVoltar, textoConferencia,
} from "../lotePrecoStatus.js";
import { moeda, numero, paraCampoPreco, parseNumeroPreco } from "../formato.js";

/* Tela — Detalhe do lote de preços (PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §6.3,
 * molde `PedidoDetalhe.jsx`). Referência de layout/rótulo (nunca de código):
 * `.../painel_cedep_prototipo_090926.jsx`, linhas 1363-1460 (exportações e
 * comprovante) e 2114-2382 (a área nova) — ele não conhece rota, sessão,
 * permissão, paginação nem os 8.772 SKUs.
 *
 * ⚠ Diferença central em relação a `PedidoDetalhe.jsx`: lá um status
 * "Fechado"/"Exportado" trava a edição dos itens. Aqui os DOIS status que
 * existem (Rascunho, Enviado) são editáveis — não há um terceiro "Aplicado"
 * de lote (ver o cabeçalho de `lotePrecoStatus.js`); por isso o controle de
 * avançar/desfazer fica sempre visível, e nunca existe um "modo só leitura"
 * de item por causa do status do documento.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";
const AMBAR = "#B98A2E";
const AMBAR_FUNDO = "#FEF3C7";

export default function LotePrecoDetalhe() {
  const { id } = useParams();
  const navegar = useNavigate();
  const [lote, setLote] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [ocupado, setOcupado] = useState(false);
  const [imprimindo, setImprimindo] = useState(false);
  // Etapa 13, ponto 4: itens de UM lote — lista sem paginação, ordena NO
  // CLIENTE (§3.1).
  const [ordenar, setOrdenar] = useState("codigo");
  const [dir, setDir] = useState("asc");
  const aoOrdenar = (coluna, d) => { setOrdenar(coluna); setDir(d); };

  // Conta CAMPOS tocados e ainda não gravados (digitação em andamento, antes
  // do blur) — usado só para o aviso ao sair, nunca para bloquear a tela.
  const pendentesRef = useRef(new Set());
  const [temPendencia, setTemPendencia] = useState(false);
  const marcarPendencia = useCallback((chave, pendente) => {
    if (pendente) pendentesRef.current.add(chave);
    else pendentesRef.current.delete(chave);
    setTemPendencia(pendentesRef.current.size > 0);
  }, []);

  // Cobre o F5/fechar aba com o mesmo aviso — o clique no "Voltar" (função
  // `voltar`, abaixo) cobre a navegação DENTRO do app.
  useEffect(() => {
    function aoFechar(e) {
      if (pendentesRef.current.size === 0) return;
      e.preventDefault();
      e.returnValue = "";
    }
    window.addEventListener("beforeunload", aoFechar);
    return () => window.removeEventListener("beforeunload", aoFechar);
  }, []);

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setLote(await api.lotePreco(id));
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

  // "Sair do detalhe com edição pendente avisa" (regra de toda tela desta
  // etapa). Diferente de PedidoDetalhe, aqui não há um botão "Salvar" que a
  // pessoa possa esquecer de clicar — cada campo grava no `blur` — então o
  // único jeito de perder algo é sair com o CURSOR ainda no campo, antes do
  // blur disparar. `window.confirm` é simples, mas honesto: não há um modelo
  // de diálogo customizado neste projeto para este caso ainda.
  function voltar() {
    if (temPendencia
        && !window.confirm("Há um preço digitado que ainda não foi gravado. Sair mesmo assim?")) {
      return;
    }
    navegar("/precos-definidos");
  }

  if (carregando) return <Carregando>Buscando o lote…</Carregando>;
  if (erro && !lote) return <Erro mensagem={erro} aoTentarDeNovo={carregar} />;
  if (!lote) return null;

  const cor = COR_STATUS[lote.status] ?? "#6B7280";
  const itens = lote.itens ?? [];
  const excluidos201 = itens.filter((it) => it.entraArquivo201 === false);
  const carimbo = textoConferencia(lote.atualizacao);

  return (
    <div className="px-4 pb-8 pt-3 md:px-6 md:pt-4">
      <button type="button" onClick={voltar}
              className="mb-3 flex items-center gap-1 text-sm font-medium" style={{ color: NAVY }}>
        <ChevronLeft size={14} aria-hidden="true" /> Voltar para a lista
      </button>

      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 text-lg font-semibold text-gray-900">
            <span className="num text-gray-400">#{lote.id}</span>
            Lote de preços
            <span className="rounded-full px-2 py-0.5 text-2xs font-bold"
                  style={{ background: `${cor}18`, color: cor }}>{lote.status}</span>
          </h2>
          <p className="num mt-0.5 text-xs text-gray-500">
            {numero(itens.length)} item(ns) · {numero(lote.qtdAplicados ?? 0)} de{" "}
            {numero(lote.qtdItens ?? itens.length)} aplicado(s)
            {lote.criadoPor && ` · criado por ${lote.criadoPor}`}
          </p>
          {carimbo && <p className="mt-0.5 text-2xs text-gray-400">Situação de aplicação {carimbo}.</p>}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {ocupado && <Loader2 size={14} className="animate-spin text-gray-400" aria-hidden="true" />}
          {/* Controle de avançar/desfazer SEMPRE visível — não existe status
              "fechado" aqui que faça sentido escondê-lo, e escondê-lo é
              exatamente o jeito de alguém ficar preso num status errado sem
              caminho de volta na tela. */}
          {podeAvancar(lote.status) && (
            <Botao destaque cor={cor} desabilitado={ocupado}
                   onClick={() => agir(() => api.avancarLotePreco(lote.id))}>
              {ROTULO_AVANCAR[lote.status]}
            </Botao>
          )}
          {podeVoltar(lote.status) && (
            <Botao desabilitado={ocupado} onClick={() => agir(() => api.voltarLotePreco(lote.id))}>
              {ROTULO_VOLTAR[lote.status]}
            </Botao>
          )}
        </div>
      </div>

      {erro && <div className="mt-3"><Erro mensagem={erro} /></div>}

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <Botao onClick={() => setImprimindo(true)} icone={Printer}>Comprovante em PDF</Botao>
        <Botao icone={FileSpreadsheet} desabilitado={ocupado}
               onClick={() => agir(() => baixar(() => api.baixarExcelLotePreco(lote.id)))}>
          Excel de conferência
        </Botao>
        <Botao icone={Download} desabilitado={ocupado}
               onClick={() => agir(() => baixar(() => api.baixar201LotePreco(lote.id, "atacado")))}>
          Importar Atacado — região 2 (201)
        </Botao>
        <Botao icone={Download} desabilitado={ocupado}
               onClick={() => agir(() => baixar(() => api.baixar201LotePreco(lote.id, "varejo")))}>
          Importar Varejo — região 1 (201)
        </Botao>
      </div>

      <p className="mt-2 max-w-2xl text-xs text-gray-500">
        Os dois arquivos já vão prontos para a rotina 201 do Winthor — só o preço à vista, o
        Winthor calcula o a prazo sozinho.
      </p>
      {/* §4.6: o identificador do arquivo é o CÓD. DE FÁBRICA, não o código
          interno da CEDEP — a rotina 201 não aceita o nosso código. Errar a
          região OU o identificador na tela da 201 escreve preço no produto
          errado, ou em nenhum. */}
      <p className="mt-1.5 max-w-2xl rounded-md px-2.5 py-2 text-xs" style={{ background: `${NAVY}0D`, color: NAVY }}>
        Na rotina 201, escolha a região (2 = atacado, 1 = varejo) e o código de identificação{" "}
        <strong>3 - Cód. de Fab. (Rotina 203)</strong>. No padrão (código de barras) a
        importação não acha o produto — ou pior, acha outro.
      </p>

      {excluidos201.length > 0 && (
        <p className="mt-2 max-w-2xl rounded-md px-2.5 py-2 text-xs" style={{ background: AMBAR_FUNDO, color: "#92400E" }}>
          {numero(excluidos201.length)} dos {numero(itens.length)} itens não entram no arquivo de
          importação — estão no Excel, para digitação manual (etiquetados em âmbar na tabela
          abaixo).
        </p>
      )}

      <div className="mt-4 overflow-x-auto rounded-lg border border-gray-200">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="codigo" padrao="asc">Código</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="descricao" padrao="asc" className="min-w-[200px]">Produto</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="pvAtacadoAtual" padrao="desc" align="center">Atacado atual</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="pvAtacadoNovo" padrao="desc" align="center">Atacado novo</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="pvVarejoAtual" padrao="desc" align="center">Varejo atual</CabecalhoOrdenavel>
              <CabecalhoOrdenavel ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar} coluna="pvVarejoNovo" padrao="desc" align="center">Varejo novo</CabecalhoOrdenavel>
              {/* Situação é etiqueta calculada, não um número/texto ordenável
                  de forma óbvia — fica sem cabeçalho clicável (§3.1). */}
              <th className="px-2 py-2 text-center font-medium">Situação</th>
              <th className="px-2 py-2" />
            </tr>
          </thead>
          <tbody>
            {ordenarLista(itens, {
              codigo: (it) => it.codigo, descricao: (it) => it.descricao,
              pvAtacadoAtual: (it) => it.pvAtacadoAtual, pvAtacadoNovo: (it) => it.pvAtacadoNovo,
              pvVarejoAtual: (it) => it.pvVarejoAtual, pvVarejoNovo: (it) => it.pvVarejoNovo,
            }[ordenar] ?? ((it) => it.codigo), dir).map((it) => (
              <LinhaItem key={it.codigo} it={it} idLote={lote.id}
                         aoMudar={carregar} aoPendencia={marcarPendencia} />
            ))}
            {itens.length === 0 && (
              <tr>
                <td colSpan={8} className="py-8 text-center text-sm text-gray-400">
                  Nenhum item neste lote.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* §4.6: remover um item do lote NÃO desfaz a decisão de preço — sem
          esta linha, quem remove acha que desfez a decisão inteira. */}
      <p className="mt-2 text-2xs text-gray-400">
        Remover um item daqui tira ele deste arquivo — o preço decidido continua gravado, com
        histórico.
      </p>

      {imprimindo && <Comprovante lote={lote} aoFechar={() => setImprimindo(false)} />}
    </div>
  );
}

async function baixar(chamada) {
  const { blob, nome } = await chamada();
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

function LinhaItem({ it, idLote, aoMudar, aoPendencia }) {
  // `paraCampoPreco` (formato.js) — o mesmo par usado em Precificacao.jsx e
  // DecisaoSKU.jsx. Antes esta tela tinha seu PRÓPRIO `paraCampo`, que por
  // coincidência não punha ponto de milhar (por isso nunca sofreu o defeito
  // das outras duas telas) — mas três formatações diferentes para o mesmo
  // campo não são um contrato, são três acidentes. Agora é uma função só.
  const [at, setAt] = useState(paraCampoPreco(it.pvAtacadoNovo));
  const [varejo, setVarejo] = useState(paraCampoPreco(it.pvVarejoNovo));
  const [tocado, setTocado] = useState({});
  const [estado, setEstado] = useState("parado");
  const [erro, setErro] = useState(null);
  const [removendo, setRemovendo] = useState(false);

  async function gravar(campo, bruto) {
    if (!tocado[campo]) return;
    // `parseNumeroPreco` distingue três casos que o parser antigo colapsava
    // no mesmo "não grava, e não diz nada":
    //   null (campo apagado)   — não existe, aqui, um jeito de "apagar" um
    //     canal já decidido: o servidor trata campo ausente como "não mexi
    //     nisto", nunca como remover (§4.4). Fica em silêncio mesmo — mas
    //     `tocado` continua marcado, para não fingir que gravou.
    //   NaN (não é número)     — avisa; sem isto a pessoa acha que gravou e
    //     só descobre o engano ao reabrir o lote outro dia.
    //   <= 0 (zero ou negativo) — mesmo aviso, motivo diferente: preço de
    //     venda não pode ser zero.
    const n = parseNumeroPreco(bruto);
    if (n === null) return;
    if (Number.isNaN(n)) {
      setErro("Não entendi esse valor — use vírgula para casas decimais (ex.: 12,50).");
      return;
    }
    if (n <= 0) {
      setErro("Preço tem que ser maior que zero — não gravado.");
      return;
    }
    setEstado("salvando");
    setErro(null);
    try {
      const corpo = campo === "atacado" ? { precoAtacadoAV: n } : { precoVarejoAV: n };
      await api.gravarItemLotePreco(idLote, it.codigo, corpo);
      setTocado((t) => ({ ...t, [campo]: false }));
      aoPendencia(`${it.codigo}-${campo}`, false);
      setEstado("parado");
      await aoMudar();
    } catch (e) {
      setErro(e.detalhe);
      setEstado("erro");
    }
  }

  async function remover() {
    setRemovendo(true);
    setErro(null);
    try {
      await api.removerItemLotePreco(idLote, it.codigo);
      await aoMudar();
    } catch (e) {
      setErro(e.detalhe);
      setRemovendo(false);
    }
  }

  const excluido = it.entraArquivo201 === false;
  const situacao = it.situacao ? ROTULO_SITUACAO[it.situacao] ?? it.situacao : "—";
  const corSituacao = it.situacao ? COR_SITUACAO[it.situacao] ?? "#6B7280" : "#D1D5DB";

  return (
    <tr className="border-t border-gray-100" style={excluido ? { background: AMBAR_FUNDO } : undefined}>
      <td className="num px-2 py-2 text-gray-500">{it.codigo}</td>
      <td className="px-3 py-2">
        <div className="font-medium text-gray-800">{it.descricao}</div>
        {/* §4.6: o COD_FAB fica visível na linha, e o motivo de exclusão do
            arquivo da 201 vai junto, em âmbar — é a etiqueta que permite a
            quem digita no Winthor lançar à mão o que o arquivo não carrega. */}
        <div className={`num text-2xs ${excluido ? "font-medium" : "text-gray-400"}`}
             style={excluido ? { color: AMBAR } : undefined}>
          {it.codFab ? `fab ${it.codFab}` : "sem cód. de fábrica"}
          {excluido && ` — ${it.motivoExclusao201}, não entra no arquivo 201`}
        </div>
        {erro && <div role="alert" className="text-2xs" style={{ color: RED }}>{erro}</div>}
      </td>
      <td className="num px-2 py-2 text-center text-gray-500">{moeda(it.pvAtacadoAtual)}</td>
      <td className="px-2 py-1.5 text-center">
        <input type="text" inputMode="decimal" value={at}
               aria-label={`Novo preço de atacado do produto ${it.codigo}`}
               onChange={(e) => {
                 setAt(e.target.value);
                 setTocado((t) => ({ ...t, atacado: true }));
                 aoPendencia(`${it.codigo}-atacado`, true);
               }}
               onBlur={() => gravar("atacado", at)}
               placeholder={it.pvAtacadoAtual != null ? "não decidido" : "—"}
               className="num w-[84px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
      </td>
      <td className="num px-2 py-2 text-center text-gray-500">{moeda(it.pvVarejoAtual)}</td>
      <td className="px-2 py-1.5 text-center">
        <input type="text" inputMode="decimal" value={varejo}
               aria-label={`Novo preço de varejo do produto ${it.codigo}`}
               onChange={(e) => {
                 setVarejo(e.target.value);
                 setTocado((t) => ({ ...t, varejo: true }));
                 aoPendencia(`${it.codigo}-varejo`, true);
               }}
               onBlur={() => gravar("varejo", varejo)}
               placeholder={it.pvVarejoAtual != null ? "não decidido" : "—"}
               className="num w-[84px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
      </td>
      <td className="px-2 py-2 text-center">
        <span className="rounded-full px-2 py-0.5 text-2xs font-bold"
              style={{ background: `${corSituacao}18`, color: corSituacao }}>
          {situacao}
        </span>
      </td>
      <td className="px-2 py-2 text-center">
        {estado === "salvando"
          ? <Loader2 size={13} className="mx-auto animate-spin text-gray-400" aria-hidden="true" />
          : (
            <button type="button" onClick={remover} disabled={removendo}
                    aria-label={`Remover o produto ${it.codigo} do lote`}
                    title="Remover do lote — não desfaz a decisão de preço">
              {removendo
                ? <Loader2 size={13} className="animate-spin text-gray-400" aria-hidden="true" />
                : <Trash2 size={13} style={{ color: RED }} aria-hidden="true" />}
            </button>
          )}
      </td>
    </tr>
  );
}

/* -------------------------------------------------------------- impressão --- */

/* Molde: `PedidoDetalhe.jsx:460`. `window.print()` gera o PDF — o navegador
 * oferece "Salvar como PDF" no diálogo; não geramos PDF nenhum aqui. */
function Comprovante({ lote, aoFechar }) {
  const itens = lote.itens ?? [];
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

        <h1 className="mt-6 text-xl font-bold" style={{ color: NAVY }}>Lote de preços</h1>
        <p className="num mt-1 text-sm text-gray-600">
          Lote #{lote.id} · {lote.status} · {numero(itens.length)} item(ns)
        </p>

        <table className="mt-4 w-full text-sm">
          <thead>
            <tr className="border-b border-gray-300 text-left text-xs uppercase text-gray-500">
              <th className="py-1.5">Código</th>
              <th className="py-1.5">Produto</th>
              <th className="py-1.5 text-right">Atacado novo</th>
              <th className="py-1.5 text-right">Varejo novo</th>
            </tr>
          </thead>
          <tbody>
            {itens.map((it) => (
              <tr key={it.codigo} className="border-b border-gray-100">
                <td className="num py-1.5">{it.codigo}</td>
                <td className="py-1.5">{it.descricao}</td>
                <td className="num py-1.5 text-right">{moeda(it.pvAtacadoNovo)}</td>
                <td className="num py-1.5 text-right">{moeda(it.pvVarejoNovo)}</td>
              </tr>
            ))}
          </tbody>
        </table>

        <p className="mt-6 text-xs text-gray-500">CEDEP Comércio Ltda · Diretoria de Compras</p>
      </div>
    </div>
  );
}
