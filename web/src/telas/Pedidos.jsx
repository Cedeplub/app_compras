import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Check, ChevronDown, Filter, Loader2, X } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, ClasseChip, Erro } from "../componentes/Basicos.jsx";
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

const ORDENACOES = [
  { id: "cobertura", rotulo: "Cobertura — menor primeiro" },
  { id: "giro", rotulo: "Mais dias sem venda" },
  { id: "valor", rotulo: "Maior valor de estoque" },
  { id: "descricao", rotulo: "Nome (A → Z)" },
];

const UNIDADES = [
  { id: "valor", rotulo: "R$" },
  { id: "peso", rotulo: "Peso" },
  { id: "litros", rotulo: "Litros" },
  { id: "qtd", rotulo: "Qtd" },
];

export default function Pedidos() {
  const navegar = useNavigate();
  const [opcoes, setOpcoes] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [departamento, setDepartamento] = useState("");
  const [status, setStatus] = useState("Ativo");
  const [ordenacao, setOrdenacao] = useState("cobertura");
  const [busca, setBusca] = useState("");
  const [pagina, setPagina] = useState(1);
  const [unidadeTotal, setUnidadeTotal] = useState("valor");

  // O carrinho é {codigo: quantidade}. No protótipo ele se perde ao trocar de
  // aba, sem aviso (§2.4). Aqui ele também vive só na tela — mas o botão de
  // salvar está sempre visível quando há item, e o aviso abaixo diz o que
  // acontece se sair. Persistir carrinho é decisão de produto, não minha.
  const [carrinho, setCarrinho] = useState({});
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
        status: status === "Todos" ? null : status,
        busca: busca || null,
        ordenacao, pagina, porPagina: POR_PAGINA,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [departamento, status, busca, ordenacao, pagina]);

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

      <Filtros {...{ opcoes, departamento, setDepartamento, status, setStatus,
                     ordenacao, setOrdenacao, busca, setBusca, setPagina }}
               total={dados?.total} />

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && itens.length === 0 && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}
        {!carregando && !erro && itens.length > 0 && (
          <Tabela itens={itens} carrinho={carrinho} setCarrinho={setCarrinho}
                  mesReferencia={parametros?.mes_referencia} aoAbrir={(c) => navegar(`/produto/${c}`)} />
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

function Filtros({ opcoes, departamento, setDepartamento, status, setStatus,
                   ordenacao, setOrdenacao, busca, setBusca, setPagina, total }) {
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
      <Campo rotulo="Seção" largura="w-36"><SelectVazio /></Campo>
      <Campo rotulo="Linha" largura="w-36"><SelectVazio /></Campo>
      <Campo rotulo="Ordenar por" largura="w-56">
        <Select valor={ordenacao} aoTrocar={(v) => { setOrdenacao(v); setPagina(1); }}
                opcoes={ORDENACOES.map((o) => o.id)}
                rotulos={Object.fromEntries(ORDENACOES.map((o) => [o.id, o.rotulo]))} />
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

function Tabela({ itens, carrinho, setCarrinho, mesReferencia, aoAbrir }) {
  // Rótulos dos meses, como no gráfico do SKU: nome do mês em vez de M-1/M-2/M-3.
  const rot = (i) => (mesReferencia ? mesCurto(mesesAntes(mesReferencia, i)) : ["Atual", "M-1", "M-2", "M-3"][i]);
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-200">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
            <th className="px-2 py-2 text-left font-medium">Código</th>
            <th className="min-w-[240px] px-3 py-2 text-left font-medium">Produto</th>
            <th className="px-2 py-2 text-center font-medium">Classe</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_EST }}>Estoque</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_EST }}>Pend.</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_ESTPED }}>EST+PED</th>
            <th className="px-2 py-2 text-center font-medium">Últ. entrada</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(0)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(1)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(2)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_VENDA }}>{rot(3)}</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_MEDIA }}>Média</th>
            <th className="px-2 py-2 text-center font-medium">Últ. saída</th>
            <th className="px-2 py-2 text-center font-medium">Clientes AT/VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_COB }}>Cob./Alvo</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: F_COB }}>Tend.</th>
            <th className="px-2 py-2 text-center font-medium">Sugestão</th>
            <th className="px-3 py-2 text-center font-medium">Pedido</th>
          </tr>
        </thead>
        <tbody>
          {itens.map((p) => (
            <LinhaPedido key={p.codigo} p={p} aoAbrir={aoAbrir}
                         valor={carrinho[p.codigo]}
                         aoTrocar={(v) => setCarrinho((c) => ({ ...c, [p.codigo]: v }))} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function LinhaPedido({ p, valor, aoTrocar, aoAbrir }) {
  const critica = p.mesesCobertura != null && p.coberturaAlvo != null
    && p.mesesCobertura < p.coberturaAlvo * 0.6;
  const emCaixa = (p.fatorExibicao || 1) > 1;
  const seta = p.tendPct == null ? "→" : p.tendPct > 0.03 ? "↑" : p.tendPct < -0.03 ? "↓" : "→";
  const corSeta = p.tendPct == null ? CINZA : p.tendPct > 0.03 ? NAVY : p.tendPct < -0.03 ? RED : CINZA;

  return (
    <tr className="border-t border-gray-100 hover:bg-gray-50">
      <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
      <td className="px-3 py-2">
        <button type="button" onClick={() => aoAbrir(p.codigo)}
                className="block w-full text-left hover:underline">
          <div className="whitespace-nowrap font-medium text-gray-800">{p.nome}</div>
          <div className="num text-2xs text-gray-400">
            {p.departamento} · {p.embalagem}{emCaixa ? ` · cx ${numero(p.embalCompra, 0)}` : ""}
          </div>
        </button>
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
      {p.vendaHistorico.map((v, i) => (
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
        {numero(p.mesesCobertura, 1)}
        <span className="font-normal text-gray-400"> / {numero(p.coberturaAlvo, 1)}</span>
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
        Um pedido por departamento — é como o Winthor importa. O carrinho não sobrevive a
        recarregar a página.
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
