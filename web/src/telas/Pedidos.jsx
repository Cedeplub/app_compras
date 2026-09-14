import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Check, ChevronDown, Filter, Loader2, X } from "lucide-react";
import { api } from "../api/cliente.js";
import { useAtualizacao } from "../contexto/atualizacao.jsx";
import { useCarrinho } from "../contexto/carrinho.jsx";
import { Carregando, ClasseChip, Erro } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { useOrdenacaoUrl } from "../componentes/CabecalhoOrdenavel.jsx";
import FiltroUltimaEntrada, { AvisoSemEntrada } from "../componentes/FiltroUltimaEntrada.jsx";
import { mesCurto, mesesAntes, moeda, numero } from "../formato.js";

/* Tela — Pedidos (PROTOTIPO.md §2.4, .jsx linha 2735).
 *
 * O carrinho: a lista larga com todo o contexto de decisão de compra, e um
 * campo de quantidade por produto. Salvar cria UM pedido por departamento —
 * exigência do formato de importação do Winthor (rotina 220).
 */

const POR_PAGINA = 50;
const NAVY = "#375DA8";
const RED = "#DE434B";
const VERDE = "#15803D";
const CINZA = "#6B7280";

const F_EST = "#EFF6FF";
const F_ESTPED = "#DBEAFE";
const F_VENDA = "#F0FDF4";
const F_MEDIA = "#DCFCE7";
const F_COB = "#FAF5FF";

// `dir` espelha a direção padrão de cada coluna em `app/servicos/produto.py`
// (`ORDENACOES`) — mesmo motivo de Precificacao.jsx: o dropdown e o clique no
// cabeçalho da coluna escrevem o mesmo estado (§3.3), nunca direções diferentes.
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
};

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

  const [departamento, setDepartamento] = useState("");
  const [comprador, setComprador] = useState("");
  const [status, setStatus] = useState("Ativo");
  const [busca, setBusca] = useState("");
  const [pagina, setPagina] = useState(1);
  // Etapa 13, ponto 4: mesmo par `ordenar`/`dir` na URL, escrito tanto pelo
  // dropdown "Ordenar por" quanto pelo clique no cabeçalho da coluna (§3.3/§3.4).
  const { ordenar, dir, aoOrdenar } = useOrdenacaoUrl("cobertura", "asc", setPagina);
  const [unidadeTotal, setUnidadeTotal] = useState("valor");
  const [dtUltEntDe, setDtUltEntDe] = useState("");
  const [dtUltEntAte, setDtUltEntAte] = useState("");

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
  }, [departamento, comprador, status, busca, ordenar, dir, pagina,
      dtUltEntDe, dtUltEntAte, versaoDados]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const itens = dados?.itens ?? [];

  // O total do carrinho só sabe somar o que está na PÁGINA atual, porque é dela
  // que vêm peso, litragem e custo de cada produto. Trocar de página mantém as
  // quantidades digitadas, mas o total deixa de contá-las — e dizer isso é
  // melhor que exibir um total que encolhe sozinho.
  const totais = useMemo(() => {
    const t = { valor: 0, peso: 0, litros: 0, qtd: 0, linhas: 0, foraDaPagina: 0 };
    const naPagina = new Set(itens.map((p) => String(p.codigo)));
    for (const [codigo, qtd] of Object.entries(carrinho)) {
      const n = Number(String(qtd).replace(",", ".")) || 0;
      if (n <= 0) continue;
      t.linhas += 1;
      if (!naPagina.has(codigo)) { t.foraDaPagina += 1; continue; }
      const p = itens.find((x) => String(x.codigo) === codigo);
      const unidades = n * (p.fatorExibicao || 1);
      t.qtd += unidades;
      t.valor += unidades * (p.custoGerencial ?? 0);
      t.peso += unidades * (p.pesoUnidade ?? 0);
      t.litros += unidades * (p.litragemUnidade ?? 0);
    }
    return t;
  }, [carrinho, itens]);

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

      <Filtros {...{ opcoes, departamento, setDepartamento, comprador, setComprador,
                     status, setStatus, ordenar, dir, aoOrdenar, busca, setBusca, setPagina,
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
          <Tabela itens={itens} carrinho={carrinho} setCarrinho={setCarrinho}
                  ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar}
                  mesReferencia={parametros?.mes_referencia} parametros={parametros} />
        )}
      </div>

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}

      {totais.linhas > 0 && (
        <BarraCarrinho totais={totais} unidade={unidadeTotal} setUnidade={setUnidadeTotal}
                       salvando={salvando} aoSalvar={salvar} />
      )}
    </div>
  );
}

/* ----------------------------------------------------------------- filtros --- */

function Filtros({ opcoes, departamento, setDepartamento, comprador, setComprador,
                   status, setStatus, ordenar, dir, aoOrdenar, busca, setBusca, setPagina, total,
                   referencia, dtUltEntDe, setDtUltEntDe, dtUltEntAte, setDtUltEntAte }) {
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
      <Campo rotulo="Departamento" largura="w-44">
        <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                aoTrocar={(v) => { setDepartamento(v); setPagina(1); }} />
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

function Tabela({ itens, carrinho, setCarrinho, ordenar, dir, aoOrdenar, mesReferencia, parametros }) {
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
            <LinhaPedido key={p.codigo} p={p} parametros={parametros}
                         valor={carrinho[p.codigo]}
                         aoTrocar={(v) => setCarrinho((c) => ({ ...c, [p.codigo]: v }))} />
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
 *  carrinho já faz para somar peso/valor/litros (`totais`, mais acima).
 *
 *  ⚠ Ressalva que a API já tenta cobrir com `mesesCoberturaComPedido`, mas que
 *  não dá para "consertar" aqui: a coluna BF soma `est_pend + pedido_unidades`
 *  tratando EST_PEND como UNIDADES, enquanto a vizinha BG (`valor_estoque`)
 *  faz `est_pend × fator_exibicao × custo`, tratando EST_PEND como CAIXAS. As
 *  duas só coincidem quando `fator_exibicao = 1` — nos departamentos com
 *  PEDIDO_EM = 'MASTER' esta conta pode divergir do `mesesCoberturaComPedido`
 *  que o servidor manda (que reflete a MESMA fórmula BF, sobre o pedido já
 *  DECIDIDO e gravado — não o que está sendo digitado agora no carrinho, que
 *  é o número que faz sentido mostrar aqui). Não é bug para corrigir no
 *  front: é regra de negócio do modelo, relatada para o Diretor decidir.
 */
function calcMesesCoberturaComPedido(p, valorDigitado) {
  const qtd = Number(String(valorDigitado ?? "").replace(",", ".")) || 0;
  if (qtd <= 0) return null;
  if (!p.mediaJanela) return null;
  const pedidoUnidades = qtd * (p.fatorExibicao || 1);
  return (Number(p.estPend || 0) + pedidoUnidades) / p.mediaJanela;
}

function LinhaPedido({ p, valor, aoTrocar, parametros }) {
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
      </td>
      <td className="px-2 py-2 text-center"><ClasseChip classe={p.classe} /></td>
      <td className="num px-2 py-2 text-center" style={{ background: F_EST }}>{numero(p.estDisp, 0)}</td>
      <td className="num px-2 py-2 text-center" style={{ background: F_EST }}>{numero(p.pendente, 0)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: F_ESTPED, color: "#1D4ED8" }}>{numero(p.estPend, 0)}</td>
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {p.ultimaEntrada ? p.ultimaEntrada.split("-").reverse().slice(0, 2).join("/") : "—"}
        {p.qtdUltimaEntrada != null && <div className="text-gray-400">{numero(p.qtdUltimaEntrada, 0)}</div>}
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
            responder (item 5 do Diretor, 08/09). Fórmula fiel à coluna BF do
            modelo (`int_produto_pedido.sql`): meses_est_ped = (est_pend +
            pedido_unidades) / media_janela, com pedido_unidades = qtd digitada
            × fator_exibicao — o mesmo fator que o carrinho já usa para somar
            peso/valor/litros (linha ~111 acima). Verde quando a projeção
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
               className="num w-[72px] rounded-md border border-gray-300 px-1 py-1 text-center text-sm" />
        <div className="text-[9px] text-gray-400">{emCaixa ? "caixas" : "unidades"}</div>
      </td>
    </tr>
  );
}

/* ---------------------------------------------------------- barra carrinho --- */

function BarraCarrinho({ totais, unidade, setUnidade, salvando, aoSalvar }) {
  const valores = {
    valor: moeda(totais.valor),
    peso: `${numero(totais.peso, 0)} kg`,
    litros: `${numero(totais.litros, 0)} L`,
    qtd: `${numero(totais.qtd, 0)} un`,
  };
  return (
    <div className="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white px-4 py-3 shadow-lg md:px-6">
      <div className="mx-auto flex max-w-app flex-wrap items-center gap-3">
        <div>
          <div className="text-2xs text-gray-500">
            {numero(totais.linhas)} produto(s) no carrinho
            {totais.foraDaPagina > 0 && (
              // Não deixo o total mentir em silêncio: ele só soma o que está na
              // página, porque peso e custo vêm da linha carregada.
              <span style={{ color: "#B98A2E" }}>
                {" "}· {numero(totais.foraDaPagina)} em outra página, fora do total
              </span>
            )}
          </div>
          <div className="num text-lg font-bold" style={{ color: NAVY }}>{valores[unidade]}</div>
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

function Paginacao({ pagina, total, aoTrocar }) {
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
