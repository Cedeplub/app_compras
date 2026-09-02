import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Check, ChevronDown, Filter, Loader2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import { simular, valorAntesDoCredito } from "../precificacao.js";
import { moeda, numero } from "../formato.js";

/* Tela — Precificação (PROTOTIPO.md §2.9, .jsx linha 3265).
 *
 * Porte da tabela de 15 colunas, com as quatro faixas que agrupam a leitura:
 * azul claro para o bloco de atacado, azul forte para o campo editável do
 * atacado, verde claro para o varejo, verde forte para o campo dele. É esse
 * agrupamento que faz 15 colunas serem lidas como quatro assuntos.
 *
 * Diferença central em relação ao protótipo: lá o preço digitado não é gravado
 * em lugar nenhum (§8 — "o valor digitado fica só na tela"). Aqui vai para
 * APP_DECISAO_PRECO, com histórico do valor anterior e restrição de perfil.
 */

const POR_PAGINA = 50;
const NAVY = "#375DA8";
const RED = "#DE434B";
const CINZA = "#6B7280";

const FUNDO_AT = "#EFF6FF";
const FUNDO_AT_EDIT = "#DBEAFE";
const FUNDO_VAR = "#F0FDF4";
const FUNDO_VAR_EDIT = "#DCFCE7";

const CENARIOS = [
  { id: "st_valor", rotulo: "ST s/Valor" },
  { id: "oficial", rotulo: "Oficial (c/ redução)" },
  { id: "sem_red", rotulo: "Sem Redução" },
];

const ORDENACOES = [
  { id: "margem", rotulo: "Margem — pior primeiro" },
  { id: "preco", rotulo: "Maior preço atual" },
  { id: "mkp", rotulo: "Menor MKP" },
  { id: "descricao", rotulo: "Nome (A → Z)" },
];

export default function Precificacao() {
  const navegar = useNavigate();
  const [opcoes, setOpcoes] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [departamento, setDepartamento] = useState("");
  const [status, setStatus] = useState("Ativo");
  const [cenarioSel, setCenarioSel] = useState("st_valor");
  const [ordenacao, setOrdenacao] = useState("margem");
  const [busca, setBusca] = useState("");
  const [pagina, setPagina] = useState(1);

  // Preços digitados, por código. Não são gravados até o botão — e trocar de
  // página os descarta, como no protótipo. A diferença é que aqui existe um
  // botão de gravar; lá o valor morria em silêncio de qualquer jeito (§8).
  const [precosAT, setPrecosAT] = useState({});
  const [precosVAR, setPrecosVAR] = useState({});

  useEffect(() => {
    api.opcoes().then(setOpcoes).catch((e) => setErro(e.detalhe));
    api.parametros().then(setParametros).catch((e) => setErro(e.detalhe));
  }, []);

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.produtos({
        departamento: departamento || null,
        status: status === "Todos" ? null : status,
        busca: busca || null,
        ordenacao,
        cenarioMargem: cenarioSel,
        pagina,
        porPagina: POR_PAGINA,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [departamento, status, busca, ordenacao, cenarioSel, pagina]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  // Grava e RECARREGA a lista. Recarregar é o que faz a linha passar a mostrar
  // "decidido R$ x" e o botão sumir — sem isso a tela ficaria dizendo que há
  // decisão pendente depois de já ter gravado.
  const gravarPreco = useCallback(async (codigo, corpo) => {
    await api.gravarPreco(codigo, corpo);
    await buscar();
  }, [buscar]);

  const itens = dados?.itens ?? [];

  return (
    <div className="px-4 pb-6 pt-3 md:px-6 md:pt-4">
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

        <Campo rotulo="Departamento" largura="w-40">
          <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                  aoTrocar={(v) => { setDepartamento(v); setPagina(1); }} />
        </Campo>
        <Campo rotulo="Seção" largura="w-40"><SelectVazio /></Campo>
        <Campo rotulo="Linha" largura="w-40"><SelectVazio /></Campo>

        <Campo rotulo="Cenário de margem" largura="w-52">
          <Select valor={cenarioSel} aoTrocar={(v) => { setCenarioSel(v); setPagina(1); }}
                  opcoes={CENARIOS.map((c) => c.id)}
                  rotulos={Object.fromEntries(CENARIOS.map((c) => [c.id, c.rotulo]))} />
        </Campo>
        <Campo rotulo="Ordenar por" largura="w-52">
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

        <div className="num ml-auto text-xs text-gray-500">
          {numero(dados?.total)} produto(s)
        </div>
      </div>

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && itens.length === 0 && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}
        {!carregando && !erro && itens.length > 0 && parametros && (
          <Tabela itens={itens} cenarioSel={cenarioSel} parametros={parametros}
                  precosAT={precosAT} setPrecosAT={setPrecosAT}
                  precosVAR={precosVAR} setPrecosVAR={setPrecosVAR}
                  aoAbrir={(c) => navegar(`/produto/${c}`)}
                  aoGravar={gravarPreco} />
        )}
      </div>

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}

      <p className="mt-2 text-2xs text-gray-400">
        O regime fiscal de cada produto sai de <code>dim_tributacao</code>, validado item a
        item contra a planilha. Custo e alíquota mudam com o cenário; o preço praticado hoje, não.
      </p>
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

const mult = (v) => (v == null ? "—" : `${numero(v, 2)}x`);
const pct = (v, casas = 1) => (v == null ? "—" : `${numero(v * 100, casas)}%`);

function Tabela({ itens, cenarioSel, parametros, precosAT, setPrecosAT,
                  precosVAR, setPrecosVAR, aoAbrir, aoGravar }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-200">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
            <th className="px-2 py-2 text-left font-medium">Código</th>
            <th className="min-w-[220px] px-3 py-2 text-left font-medium">Produto</th>
            <th className="px-2 py-2 text-center font-medium">Tributação</th>
            <th className="px-2 py-2 text-center font-medium">Custo</th>
            <th className="px-2 py-2 text-center font-medium">Valor NF</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT }}>Atacado atual</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT }}>MKP AT</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT }}>Margem AT</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT }}>Sugerido AT</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT_EDIT }}>Novo preço AT<br /><span className="normal-case opacity-70">(à vista → a prazo)</span></th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>Varejo atual</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>MKP VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>Margem VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>Sugerido VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR_EDIT }}>Novo preço VAR<br /><span className="normal-case opacity-70">(à vista → a prazo)</span></th>
          </tr>
        </thead>
        <tbody>
          {itens.map((p) => (
            <Linha key={p.codigo} p={p} cenarioSel={cenarioSel} parametros={parametros}
                   precoAT={precosAT[p.codigo]} precoVAR={precosVAR[p.codigo]}
                   setPrecoAT={(v) => setPrecosAT((a) => ({ ...a, [p.codigo]: v }))}
                   setPrecoVAR={(v) => setPrecosVAR((a) => ({ ...a, [p.codigo]: v }))}
                   aoAbrir={aoAbrir} aoGravar={aoGravar} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Linha({ p, cenarioSel, parametros, precoAT, precoVAR, setPrecoAT, setPrecoVAR,
                 aoAbrir, aoGravar }) {
  const at = simular({ produto: p, cenarios: p.cenariosAtacado, cenarioSel,
                       precoAtual: p.pvAtacado, precoDigitado: precoAT,
                       fatorPrazo: parametros.fator_prazo_atacado, parametros });
  const vr = simular({ produto: p, cenarios: p.cenariosVarejo, cenarioSel,
                       precoAtual: p.pvVarejo, precoDigitado: precoVAR,
                       fatorPrazo: parametros.fator_prazo_varejo, parametros });

  // Custo e Valor NF ocupam UMA linha quando a última entrada e o custo do
  // cenário coincidem, e DUAS quando divergem. É do protótipo, e é bom: a
  // segunda linha aparece só quando há de fato duas coisas a dizer.
  const custoIgual = p.custoUltimaEntrada != null && at.custo != null
    && Math.abs(p.custoUltimaEntrada - at.custo) < 0.01;
  const valorUlt = valorAntesDoCredito(p.custoUltimaEntrada, p.creditoICMS, p.creditoPisCofins);
  const valorCen = valorAntesDoCredito(at.custo, p.creditoICMS, p.creditoPisCofins);

  return (
    <tr className="border-t border-gray-100 hover:bg-gray-50">
      <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
      <td className="px-3 py-2">
        <button type="button" onClick={() => aoAbrir(p.codigo)}
                className="block w-full text-left hover:underline">
          <div className="whitespace-nowrap font-medium text-gray-800">{p.nome}</div>
          <div className="num text-2xs text-gray-400">{p.departamento}</div>
        </button>
      </td>
      <td className="px-2 py-2 text-center">
        <Tributacao p={p} />
      </td>
      <td className="num px-2 py-1.5 text-center text-2xs text-gray-600" style={{ minWidth: 96 }}>
        {custoIgual ? moeda(at.custo) : (
          <>
            <div>últ {moeda(p.custoUltimaEntrada)}</div>
            <div className="text-gray-400">ger {moeda(at.custo)}</div>
          </>
        )}
      </td>
      <td className="num px-2 py-1.5 text-center text-2xs text-gray-600" style={{ minWidth: 96 }}>
        {custoIgual ? moeda(valorCen) : (
          <>
            <div>últ {moeda(valorUlt)}</div>
            <div className="text-gray-400">ger {moeda(valorCen)}</div>
          </>
        )}
      </td>

      <td className="num px-2 py-2 text-center" style={{ background: FUNDO_AT }}>{moeda(p.pvAtacado)}</td>
      <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_AT }}>{mult(at.mkpAtual)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: FUNDO_AT,
                   color: at.margemAtual != null && p.margemAlvo != null && at.margemAtual < p.margemAlvo ? RED : NAVY }}>
        {pct(at.margemAtual)}
      </td>
      <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_AT }}>{moeda(at.sugerido)}</td>
      <CelulaEdicao fundo={FUNDO_AT_EDIT} sim={at} valor={precoAT} aoTrocar={setPrecoAT}
                    rotulo={`Novo preço de atacado do produto ${p.codigo}`}
                    decidido={p.precoDecididoAtacadoAV}
                    aoSalvar={(v) => aoGravar(p.codigo, { precoAtacadoAV: v })} />

      <td className="num px-2 py-2 text-center" style={{ background: FUNDO_VAR }}>{moeda(p.pvVarejo)}</td>
      <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_VAR }}>{mult(vr.mkpAtual)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: FUNDO_VAR,
                   color: vr.margemAtual != null && p.margemAlvoVarejo != null && vr.margemAtual < p.margemAlvoVarejo ? RED : NAVY }}>
        {pct(vr.margemAtual)}
      </td>
      <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_VAR }}>{moeda(vr.sugerido)}</td>
      <CelulaEdicao fundo={FUNDO_VAR_EDIT} sim={vr} valor={precoVAR} aoTrocar={setPrecoVAR}
                    rotulo={`Novo preço de varejo do produto ${p.codigo}`}
                    decidido={p.precoDecididoVarejoAV}
                    aoSalvar={(v) => aoGravar(p.codigo, { precoVarejoAV: v })} />
    </tr>
  );
}

function Tributacao({ p }) {
  const cor = { ST_SUBSTITUTO: NAVY, ST_RECOLHIDO: "#7C3AED" }[p.modalidade] ?? CINZA;
  const rotulo = { ST_SUBSTITUTO: "ST Substituto", ST_RECOLHIDO: "ST Recolhido" }[p.modalidade] ?? "Normal";
  return (
    <>
      <span className="whitespace-nowrap rounded-full px-2 py-0.5 text-2xs font-semibold"
            style={{ background: `${cor}18`, color: cor }}>
        {rotulo}{p.creditoPisCofins === 0 ? " · Mono" : ""}
      </span>
      {/* O texto do regime vem de COMPRAS_PRODUTO_CONTEXTO. Nulo nos 5 SKUs sem
          tributação encontrada — os mesmos do alerta TRIB. */}
      {p.regimeFiscal && (
        <div className="mt-0.5 whitespace-nowrap text-[9px] text-gray-400">{p.regimeFiscal}</div>
      )}
    </>
  );
}

function CelulaEdicao({ fundo, sim, valor, aoTrocar, rotulo, decidido, aoSalvar }) {
  const [estado, setEstado] = useState("parado");   // parado | salvando | salvo | erro
  const [erro, setErro] = useState(null);

  const numeroDigitado = Number(String(valor ?? "").replace(",", ".")) || 0;
  // O botão só aparece quando há decisão NOVA a tomar: valor digitado, positivo,
  // e diferente do que já está gravado. Botão sempre visível numa tabela de 50
  // linhas vira 100 botões que não fazem nada.
  const podeSalvar = numeroDigitado > 0
    && (decidido == null || Math.abs(numeroDigitado - decidido) >= 0.005);

  async function salvar() {
    setEstado("salvando");
    setErro(null);
    try {
      await aoSalvar(numeroDigitado);
      setEstado("salvo");
    } catch (e) {
      // 404 aqui não é "produto sumiu": é a resposta de quem não tem perfil de
      // diretoria (a convenção do projeto é 404, nunca 403, para não confirmar
      // que o recurso existe). Traduzir para o comprador evita que ele procure
      // um produto que está bem na frente dele.
      setErro(e.status === 404 ? "Só a diretoria pode gravar preço." : e.detalhe);
      setEstado("erro");
    }
  }

  return (
    <td className="px-2 py-1.5 text-center" style={{ background: fundo, minWidth: 180 }}>
      <div className="flex items-center justify-center gap-1.5">
        <input
          type="text" inputMode="decimal" value={valor ?? ""} aria-label={rotulo}
          onChange={(e) => aoTrocar(e.target.value)}
          // O placeholder é a SUGESTÃO do cenário: o campo em branco já diz qual
          // seria o preço para bater a meta, sem preencher por conta própria. É
          // o ponto de decisão humana que o modelo existe para preservar.
          placeholder={sim.sugerido != null ? numero(sim.sugerido, 2) : "—"}
          className="num w-[76px] rounded-md border border-gray-300 bg-white px-1 py-1 text-center text-sm"
        />
        <span className="num whitespace-nowrap text-2xs leading-none"
              style={{ color: sim.mkpNovo != null ? NAVY : "#D1D5DB" }}>
          {sim.mkpNovo != null ? `${numero(sim.mkpNovo, 2)}x/${pct(sim.margemNova, 0)}` : "—"}
        </span>
      </div>
      <div className="num mt-1 whitespace-nowrap text-[9px] leading-none text-gray-400">
        {sim.prazo != null
          ? `Pz ${moeda(sim.prazo)} · ${numero(sim.mkpPrazo, 2)}x/${pct(sim.margemPrazo, 0)}`
          : "Pz —"}
      </div>
      {/* Preço já decidido por gente, lido AO VIVO de APP_DECISAO_PRECO. O
          protótipo não tem este estado: lá nada é gravado (§8). */}
      {decidido != null && (
        <div className="num mt-1 text-[9px] leading-none" style={{ color: NAVY }}>
          decidido {moeda(decidido)}
        </div>
      )}

      {podeSalvar && estado !== "salvo" && (
        <button type="button" onClick={salvar} disabled={estado === "salvando"}
                className="mt-1 inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[9px] font-semibold text-white disabled:opacity-50"
                style={{ background: NAVY }}>
          {estado === "salvando" && <Loader2 size={9} className="animate-spin" aria-hidden="true" />}
          {estado === "salvando" ? "Gravando…" : "Gravar"}
        </button>
      )}
      {estado === "salvo" && (
        <span className="mt-1 inline-flex items-center gap-1 text-[9px] font-semibold"
              style={{ color: "#15803D" }}>
          <Check size={9} aria-hidden="true" /> gravado
        </span>
      )}
      {estado === "erro" && (
        <div role="alert" className="mt-1 text-[9px] leading-tight" style={{ color: RED }}>{erro}</div>
      )}
    </td>
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
