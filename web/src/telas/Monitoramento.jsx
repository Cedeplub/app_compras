import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronDown, TrendingDown, TrendingUp } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import SeletorPeriodo from "../componentes/SeletorPeriodo.jsx";
import { METRICAS, intervalo, intervaloAnoAnterior, rotuloComparacao } from "../periodo.js";
import { compacto, moeda, numero } from "../formato.js";

/* Tela — Monitoramento (PROTOTIPO.md §2.2, .jsx linha 917).
 *
 * Três coisas que aqui funcionam e no protótipo não (§8):
 *   1. O filtro de período FILTRA. Lá a navegação no tempo não muda número.
 *   2. O comparativo com o ano anterior é CALCULADO. Lá é "+6,4%" fixo.
 *   3. Clicar numa linha abre o produto. Era a única tela de lista sem isso.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";
const VERDE = "#15803D";
const CINZA = "#6B7280";

const ROTULO_DIMENSAO = { departamento: "Departamento", secao: "Seção" };

export default function Monitoramento() {
  const navegar = useNavigate();
  const [parametros, setParametros] = useState(null);
  const [opcoes, setOpcoes] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [granularidade, setGranularidade] = useState("Mês");
  const [offset, setOffset] = useState(0);
  const [metrica, setMetrica] = useState("faturamento");
  const [departamento, setDepartamento] = useState("");
  const [secao, setSecao] = useState("");
  // Nasce em "Todos", diferente das outras telas: histórico realizado vale
  // mesmo para produto hoje inativo — foi vendido, entrou no faturamento.
  // É a mesma escolha do protótipo (§2.2).
  const [status, setStatus] = useState("");
  const [porProduto, setPorProduto] = useState(false);

  useEffect(() => {
    api.parametros().then(setParametros).catch((e) => setErro(e.detalhe));
    api.opcoesMonitoramento().then(setOpcoes).catch((e) => setErro(e.detalhe));
  }, []);

  // A referência do dado, não a do relógio: DATA_REFERENCIA é o último dia com
  // movimento em COMPRAS_MONITORAMENTO. Se o build atrasar, "hoje" na tela
  // continua sendo o último dia que os números de fato cobrem.
  const referencia = parametros?.data_referencia;

  const periodo = useMemo(
    () => (referencia ? intervalo(granularidade, offset, referencia) : null),
    [granularidade, offset, referencia]);
  const anterior = useMemo(
    () => (referencia ? intervaloAnoAnterior(granularidade, offset, referencia) : null),
    [granularidade, offset, referencia]);

  const buscar = useCallback(async () => {
    if (!periodo || !anterior) return;
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.monitoramento({
        de: periodo.de, ate: periodo.ate,
        deAnterior: anterior.de, ateAnterior: anterior.ate,
        metrica,
        departamento: departamento || null,
        secao: secao || null,
        status: status || null,
        porProduto: porProduto || null,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [periodo, anterior, metrica, departamento, secao, status, porProduto]);

  useEffect(() => { buscar(); }, [buscar]);

  const fmt = (v) => (metrica === "faturamento" ? `R$ ${compacto(v)}`
    : metrica === "peso" ? `${compacto(v)} kg`
    : metrica === "litros" ? `${compacto(v)} L`
    : compacto(v));

  const r = dados?.resumo;

  return (
    <div className="px-4 pb-6 pt-3 md:px-6 md:pt-4">
      <SeletorPeriodo granularidade={granularidade} setGranularidade={setGranularidade}
                      offset={offset} setOffset={setOffset} referencia={referencia} />

      <div className="mt-3 flex flex-wrap items-end gap-3">
        <div>
          <div className="mb-1 text-xs text-gray-500">Métrica</div>
          <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
            {METRICAS.map((m) => (
              <button key={m.id} type="button" aria-pressed={metrica === m.id}
                      onClick={() => setMetrica(m.id)}
                      style={metrica === m.id ? { background: NAVY, color: "white" } : {}}
                      className="rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500">
                {m.rotulo}
              </button>
            ))}
          </div>
        </div>
        <Campo rotulo="Departamento" largura="w-44">
          <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                  aoTrocar={setDepartamento} />
        </Campo>
        <Campo rotulo="Seção" largura="w-44">
          {/* O campo só fica ativo se houver seção de verdade. Medido em
              02/09/2026: dos 47 departamentos, só 2 têm mais de uma seção — nos
              outros a "seção" é o próprio nome do departamento repetido, porque
              o cadastro segue em andamento no Winthor. Um filtro populado com os
              mesmos nomes do filtro ao lado parece uma segunda dimensão e não é:
              cruzar os dois não muda nada, e a pessoa perde tempo tentando. */}
          <Select valor={secao} vazio="Todas" opcoes={opcoes?.secoes ?? []}
                  aoTrocar={setSecao}
                  desabilitado={!opcoes?.secoes?.length}
                  aviso="Aguardando o cadastro de seções no Winthor" />
        </Campo>
        <Campo rotulo="Linha" largura="w-36"><SelectVazio /></Campo>
        <Campo rotulo="Status" largura="w-32">
          <Select valor={status} vazio="Todos" opcoes={["Ativo", "Inativo"]} aoTrocar={setStatus} />
        </Campo>
        <label className="flex items-center gap-1.5 pb-1.5 text-xs text-gray-600">
          <input type="checkbox" checked={porProduto}
                 onChange={(e) => setPorProduto(e.target.checked)} />
          Detalhar por produto
        </label>
      </div>

      <div className="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-2 md:max-w-2xl">
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <div className="text-2xs uppercase tracking-wide text-gray-500">
            {METRICAS.find((m) => m.id === metrica)?.rotulo} no período
          </div>
          <div className="num mt-1 text-2xl font-bold" style={{ color: NAVY }}>
            {r ? fmt(r.atual) : "—"}
          </div>
          {r && <div className="num text-2xs text-gray-400">{numero(r.produtos)} produtos</div>}
        </div>
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <div className="text-2xs uppercase tracking-wide text-gray-500">
            Contra o ano anterior
          </div>
          <div className="mt-1 flex items-baseline gap-2">
            <Variacao v={r?.variacao} tamanho="text-2xl" />
            <span className="num text-xs text-gray-400">{r ? fmt(r.anterior) : ""}</span>
          </div>
          {/* Sem esta frase, um "−38%" num mês pela metade parece desabamento de
              vendas. O protótipo tem o texto mas não o número (§8); aqui os
              dois dizem a mesma coisa. */}
          <div className="text-2xs text-gray-400">
            {referencia ? rotuloComparacao(granularidade, offset, referencia) : ""}
          </div>
        </div>
      </div>

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && dados && (
          porProduto
            ? <TabelaProdutos itens={dados.produtos ?? []} fmt={fmt}
                              aoAbrir={(c) => navegar(`/produto/${c}`)} />
            : <TabelaGrupos grupos={dados.grupos ?? []} dimensao={dados.dimensao} fmt={fmt}
                            aoFixar={(g) => (dados.dimensao === "departamento"
                              ? setDepartamento(g) : setSecao(g))} />
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ campos --- */

function Campo({ rotulo, largura = "", children }) {
  return (
    <div className={largura}>
      <div className="mb-1 text-xs text-gray-500">{rotulo}</div>
      {children}
    </div>
  );
}

function Select({ valor, aoTrocar, opcoes, vazio, desabilitado, aviso }) {
  return (
    <div className="relative">
      <select value={valor} onChange={(e) => aoTrocar(e.target.value)}
              disabled={desabilitado} title={desabilitado ? aviso : undefined}
              className={`w-full appearance-none rounded-lg border border-gray-200 px-2.5 py-1.5 pr-6 text-sm font-medium ${
                desabilitado ? "bg-gray-50 text-gray-400" : "bg-white text-gray-800"}`}>
        <option value="">{vazio}</option>
        {opcoes.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
      <ChevronDown size={12} aria-hidden="true"
                   className={`pointer-events-none absolute right-2 top-2.5 ${
                     desabilitado ? "text-gray-300" : "text-gray-400"}`} />
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

function Variacao({ v, tamanho = "text-sm" }) {
  // `null` é "não havia base no ano anterior" — não é 0% nem 100%. Mostrar um
  // número ali seria inventar comparação onde não há com o que comparar.
  if (v == null) return <span className={`${tamanho} font-bold text-gray-400`}>—</span>;
  const cor = v > 0.005 ? VERDE : v < -0.005 ? RED : CINZA;
  const Icone = v > 0.005 ? TrendingUp : v < -0.005 ? TrendingDown : null;
  return (
    <span className={`num inline-flex items-center gap-1 ${tamanho} font-bold`} style={{ color: cor }}>
      {Icone && <Icone size={tamanho === "text-2xl" ? 18 : 12} aria-hidden="true" />}
      {v > 0 ? "+" : ""}{numero(v * 100, 1)}%
    </span>
  );
}

/* ----------------------------------------------------------------- tabelas --- */

function TabelaGrupos({ grupos, dimensao, fmt, aoFixar }) {
  if (!dimensao) {
    return (
      <p className="py-8 text-center text-sm text-gray-400">
        Departamento e Seção já estão fixados — não há mais dimensão para abrir.
        Marque “Detalhar por produto” para ver os itens.
      </p>
    );
  }
  if (grupos.length === 0) {
    return <p className="py-8 text-center text-sm text-gray-400">Nada nesse cruzamento de filtros.</p>;
  }
  const total = grupos.reduce((s, g) => s + g.atual, 0);
  return (
    <>
      {/* A tela não tem botão de "agrupar por": ela abre pela primeira dimensão
          ainda não fixada, como no protótipo (§2.2). Dizer isso em voz alta
          evita que a quebra pareça arbitrária. */}
      <p className="mb-1.5 text-xs text-gray-500">
        Aberto por <strong>{ROTULO_DIMENSAO[dimensao]}</strong> — a primeira dimensão ainda
        não filtrada. Clique numa linha para fixá-la e abrir a próxima.
      </p>
      <div className="overflow-x-auto rounded-lg border border-gray-200">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
              <th className="px-3 py-2 text-left font-medium">{ROTULO_DIMENSAO[dimensao]}</th>
              <th className="px-3 py-2 text-right font-medium">Período</th>
              <th className="px-3 py-2 text-right font-medium">Ano anterior</th>
              <th className="px-3 py-2 text-right font-medium">Variação</th>
              <th className="px-3 py-2 text-right font-medium">% do total</th>
            </tr>
          </thead>
          <tbody>
            {grupos.map((g) => (
              <tr key={g.grupo} className="border-t border-gray-100 hover:bg-gray-50">
                <td className="px-3 py-2">
                  <button type="button" onClick={() => aoFixar(g.grupo)}
                          className="font-medium text-gray-800 hover:underline">
                    {g.grupo}
                  </button>
                </td>
                <td className="num px-3 py-2 text-right font-semibold">{fmt(g.atual)}</td>
                <td className="num px-3 py-2 text-right text-gray-500">{fmt(g.anterior)}</td>
                <td className="px-3 py-2 text-right"><Variacao v={g.variacao} /></td>
                <td className="num px-3 py-2 text-right text-gray-500">
                  {total > 0 ? `${numero((g.atual / total) * 100, 1)}%` : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}

function TabelaProdutos({ itens, fmt, aoAbrir }) {
  if (itens.length === 0) {
    return <p className="py-8 text-center text-sm text-gray-400">Nada nesse cruzamento de filtros.</p>;
  }
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-200">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
            <th className="px-2 py-2 text-left font-medium">Código</th>
            <th className="min-w-[240px] px-3 py-2 text-left font-medium">Produto</th>
            <th className="px-3 py-2 text-left font-medium">Departamento</th>
            <th className="px-3 py-2 text-right font-medium">Período</th>
            <th className="px-3 py-2 text-right font-medium">Ano anterior</th>
            <th className="px-3 py-2 text-right font-medium">Variação</th>
          </tr>
        </thead>
        <tbody>
          {itens.map((p) => (
            <tr key={p.codigo} className="border-t border-gray-100 hover:bg-gray-50">
              <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
              <td className="px-3 py-2">
                {/* No protótipo esta é a ÚNICA tela de lista que não abre o
                    produto (§8). Aqui abre, como todas as outras. */}
                <button type="button" onClick={() => aoAbrir(p.codigo)}
                        className="text-left font-medium text-gray-800 hover:underline">
                  {p.nome}
                </button>
                {p.secao && <div className="num text-2xs text-gray-400">{p.secao}</div>}
              </td>
              <td className="px-3 py-2 text-gray-500">{p.departamento}</td>
              <td className="num px-3 py-2 text-right font-semibold">{fmt(p.atual)}</td>
              <td className="num px-3 py-2 text-right text-gray-500">{fmt(p.anterior)}</td>
              <td className="px-3 py-2 text-right"><Variacao v={p.variacao} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
