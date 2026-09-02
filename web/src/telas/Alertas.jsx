import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronDown, ChevronRight, Filter } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, ClasseChip, Erro } from "../componentes/Basicos.jsx";
import { corDoAlerta, detalheDoTexto, iconeDoAlerta } from "../alertas.js";
import { compacto, moeda, numero } from "../formato.js";

/* Tela 1 — Alertas.
 *
 * Porte fiel de `TelaAlertas` (PROTOTIPO.md §2.1, .jsx linha 558): mesmos 3
 * KPIs, mesmo filtro de status com as duas notas explicativas, mesmos botões de
 * tipo com ícone e contagem, mesmo seletor de cenário, mesma tabela de 13
 * colunas com as faixas azul/verde separando atacado de varejo, e a mesma
 * ordenação por score de prioridade.
 *
 * Onde diverge, diverge de propósito e está comentado no ponto. As três
 * divergências estruturais: uma marcação só em vez de dois blocos de JSX
 * (§6/§8), estados de carregando e erro (não existem lá, §8), e agregados
 * calculados no banco em vez de somados em memória — são 8.772 SKUs, não 8.
 */

const POR_PAGINA = 50;
const NAVY = "#375DA8";
const RED = "#DE434B";
const AMBAR = "#B98A2E";
const CINZA = "#6B7280";

// Faixas de fundo que agrupam as colunas de preço (§ tabela do .jsx): azul para
// o bloco de atacado, verde para o de varejo. É o recurso visual que faz a
// tabela de 13 colunas ser lida como três blocos, e não como 13 números soltos.
const FUNDO_ATACADO = "#EFF6FF";
const FUNDO_VAREJO = "#F0FDF4";

const CENARIOS = [
  { id: "st_valor", rotulo: "ST s/Valor" },
  { id: "oficial", rotulo: "Oficial (c/ redução)" },
  { id: "sem_red", rotulo: "Sem Redução" },
];

export default function Alertas() {
  const navegar = useNavigate();
  const [opcoes, setOpcoes] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [ativos, setAtivos] = useState([]);
  const [filtroDepartamento, setFiltroDepartamento] = useState("");
  const [filtroStatus, setFiltroStatus] = useState("Ativo");
  const [cenarioSel, setCenarioSel] = useState("st_valor");
  const [busca, setBusca] = useState("");
  const [pagina, setPagina] = useState(1);

  useEffect(() => {
    api.opcoes().then(setOpcoes).catch((e) => setErro(e.detalhe));
  }, []);

  const buscar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.produtos({
        tipoAlerta: ativos,
        // Sem nenhum tipo ligado a tela mostra quem tem PELO MENOS UM alerta —
        // que não é "todo mundo" (§2.1).
        soComAlerta: ativos.length === 0,
        // A tela de Alertas é só de DECISÃO. Pendência de cadastro (IMPORTADO,
        // LITRAGEM, TRIB, MVA, SUCESSAO, FABRICA) sai daqui inteira e vai para
        // tela própria — item 2 do Diretor. Sem este recorte, 1.871 SKUs cujo
        // único alerta é de cadastro entrariam na fila de decisão de compra.
        categoria: "DECISAO",
        departamento: filtroDepartamento || null,
        status: filtroStatus === "Todos" ? null : filtroStatus,
        busca: busca || null,
        ordenacao: "prioridade",
        pagina,
        porPagina: POR_PAGINA,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [ativos, filtroDepartamento, filtroStatus, busca, pagina]);

  useEffect(() => {
    // Espera a digitação parar. Sem isso "elaion" dispara seis buscas, e a
    // última a RESPONDER — não a última pedida — é a que fica na tela.
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const alternarTipo = (id) => {
    setPagina(1);
    setAtivos((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const metaPorTipo = useMemo(() => {
    const m = {};
    (opcoes?.alertas ?? []).forEach((a) => { m[a.tipo] = a; });
    return m;
  }, [opcoes]);

  const resumo = dados?.resumo;
  const itens = dados?.itens ?? [];

  return (
    <div className="pb-6">
      {/* ---------------------------------------------------------- KPIs --- */}
      {/* Quatro KPIs, não três. O protótipo tem um só indicador de valor
          ("Valor em risco" = estoque de quem tem alerta), e medimos o que ele
          esconde: dos produtos em ruptura, quase metade tem estoque ZERO —
          porque ruptura é justamente não ter estoque. O pior problema entrava
          com R$ 0. O Diretor separou em dois (item 5): CAPITAL PARADO é
          dinheiro imobilizado, VENDA EM RISCO é dinheiro que deixa de entrar.
          Não se somam: um é estoque, o outro é faturamento. */}
      <div className="grid grid-cols-2 gap-2 px-4 pt-3 md:max-w-[700px] md:grid-cols-4 md:gap-3 md:px-6 md:pt-4">
        <Kpi rotulo="Alertas (filtro)" cor={RED} valor={numero(resumo?.comAlerta)} />
        {/* O protótipo divide por mil e escreve "k" (§3.1). Com 8 produtos de
            exemplo dá "R$ 62,2k"; no real são dezenas de milhões, e o mesmo
            formato produz "R$ 71.363,5k" — que ninguém lê. `compacto` escolhe
            k ou M conforme a ordem de grandeza. */}
        <Kpi rotulo="Capital parado" cor={AMBAR}
             valor={resumo ? `R$ ${compacto(resumo.capitalParado)}` : "—"} />
        <Kpi rotulo="Venda em risco" cor={RED}
             valor={resumo ? `R$ ${compacto(resumo.vendaEmRisco)}` : "—"} />
        <Kpi rotulo="Ruptura urgente" cor={RED} valor={numero(resumo?.rupturas)} />
      </div>

      {/* ------------------------------------------------ status + busca --- */}
      <div className="flex flex-wrap items-end justify-between gap-3 px-4 pt-3 md:px-6">
        <div>
          <div className="mb-1 text-xs text-gray-500">Status do cadastro</div>
          <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
            {["Ativo", "Inativo", "Todos"].map((s) => (
              <button
                key={s} type="button" onClick={() => { setFiltroStatus(s); setPagina(1); }}
                aria-pressed={filtroStatus === s}
                style={filtroStatus === s
                  ? { background: s === "Ativo" ? NAVY : s === "Inativo" ? RED : CINZA, color: "white" }
                  : {}}
                className="rounded-md px-2.5 py-1 text-2xs font-medium text-gray-500 md:text-xs"
              >
                {s}
              </button>
            ))}
          </div>
        </div>
        <input
          type="search" value={busca}
          onChange={(e) => { setBusca(e.target.value); setPagina(1); }}
          placeholder="Código, descrição ou cód. fabricante" aria-label="Buscar produto"
          className="min-w-[200px] flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm md:max-w-xs"
        />
      </div>

      {/* As duas notas são textos DIFERENTES, um para "Inativo" e outro para
          "Todos" — é assim no protótipo, e a distinção importa: uma diz que a
          lista não serve para decidir compra, a outra que ela tem ruído. No
          .jsx isso só existe na versão mobile (§8); aqui há uma marcação só,
          então aparece nos dois tamanhos por construção. */}
      {filtroStatus !== "Ativo" && (
        <p className="px-4 pt-1 text-2xs text-gray-400 md:px-6">
          {filtroStatus === "Inativo"
            ? "Mostrando só produtos descontinuados — útil pra auditar, não pra decidir compra."
            : "Mostrando ativo + inativo juntos — alerta de produto descontinuado pode ser ruído."}
        </p>
      )}

      {/* ------------------------------------------------------- filtros --- */}
      <div className="flex items-center gap-1 px-4 pt-3 text-xs text-gray-500 md:px-6">
        <Filter size={11} aria-hidden="true" />
        Filtrar produto por (pode combinar os três)
      </div>
      <div className="grid grid-cols-3 gap-2 px-4 pt-1.5 md:max-w-[640px] md:px-6">
        <Campo rotulo="Departamento">
          <Select valor={filtroDepartamento} vazio="Todos"
                  aoTrocar={(v) => { setFiltroDepartamento(v); setPagina(1); }}
                  opcoes={opcoes?.departamentos ?? []} />
        </Campo>
        {/* Seção e Linha ficam DESABILITADAS, e não escondidas. O cadastro
            delas está em andamento no Winthor (§8), então o campo existe no
            desenho e ainda não tem dado. Esconder faria a tela mudar de forma
            no dia em que o dado chegasse; mostrar vazio faria parecer que não
            há nenhuma seção cadastrada. */}
        <Campo rotulo="Seção"><SelectVazio /></Campo>
        <Campo rotulo="Linha"><SelectVazio /></Campo>
      </div>
      <p className="px-4 pt-1.5 text-2xs text-gray-400 md:px-6">
        Seção e Linha aguardam o cadastro no Winthor — o campo já está aqui, o dado ainda não.
      </p>

      {/* --------------------------------------------- tipos  de alerta --- */}
      <div className="px-4 pt-3 md:px-6">
        <div className="mb-2 flex items-center gap-1.5 text-xs text-gray-500">
          <Filter size={12} aria-hidden="true" />
          Filtrar por tipo de alerta — toque para ligar/desligar
        </div>
        <div className="flex flex-wrap gap-1.5">
          {(opcoes?.alertas ?? []).map((meta) => {
            const on = ativos.includes(meta.tipo);
            const cor = corDoAlerta(meta);
            const Icone = iconeDoAlerta(meta.tipo);
            const qtd = dados?.contagemAlertas?.[meta.tipo] ?? 0;
            return (
              <button
                key={meta.tipo} type="button" aria-pressed={on}
                onClick={() => alternarTipo(meta.tipo)}
                style={on
                  ? { background: cor, color: "white", borderColor: cor }
                  : { color: cor, borderColor: `${cor}55` }}
                className="flex items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors"
              >
                <Icone size={12} aria-hidden="true" />
                {meta.rotulo}
                <span className="num opacity-70">{numero(qtd)}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* ------------------------------------------ cenário  de  margem --- */}
      <div className="px-4 pt-3 md:max-w-xs md:px-6">
        <div className="mb-1 text-xs text-gray-500">Cenário de margem</div>
        <div className="relative">
          <select value={cenarioSel} onChange={(e) => setCenarioSel(e.target.value)}
                  aria-label="Cenário de margem"
                  className="w-full appearance-none rounded-lg border border-gray-200 bg-white px-3 py-2 pr-7 text-sm font-medium text-gray-800">
            {CENARIOS.map((c) => <option key={c.id} value={c.id}>{c.rotulo}</option>)}
          </select>
          <ChevronDown size={13} aria-hidden="true"
                       className="pointer-events-none absolute right-3 top-2.5 text-gray-400" />
        </div>
        {/* ⚠ O protótipo escreve aqui "Margem/MKP atual não mudam com o cenário
            — só o sugerido reflete a escolha". O código dele faz o contrário:
            `margemAtualPorCenario` troca a margem, e `infoPreco` calcula o MKP
            sobre `custoPorCenario`. Os três mudam. A nota abaixo diz o que a
            tela de fato faz; a divergência está na lista para o Diretor. */}
        <p className="mt-1 text-2xs text-gray-400">
          Custo, margem e MKP mudam com o cenário — o preço praticado hoje, não.
        </p>
      </div>

      {/* --------------------------------------------------------- lista --- */}
      <div className="px-4 pb-1 pt-4 text-xs font-medium text-gray-500 md:px-6">
        {ativos.length === 0
          ? `Prioridade — ${numero(dados?.total)} com alerta`
          : `Prioridade — ${numero(dados?.total)} produto(s)`}
      </div>

      {carregando && <Carregando />}
      {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
      {!carregando && !erro && itens.length === 0 && (
        <div className="py-8 text-center text-sm text-gray-400">
          Nenhum produto nesse filtro agora.
        </div>
      )}
      {!carregando && !erro && itens.length > 0 && (
        <Lista itens={itens} cenarioSel={cenarioSel} metaPorTipo={metaPorTipo}
               aoAbrir={(codigo) => navegar(`/produto/${codigo}`)} />
      )}

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}
    </div>
  );
}

/* ------------------------------------------------------------ auxiliares --- */

function Kpi({ rotulo, valor, cor }) {
  return (
    <div className="rounded-xl bg-gray-50 px-2.5 py-2.5 md:px-3">
      <div className="text-2xs leading-tight text-gray-500 md:text-xs">{rotulo}</div>
      <div className="num mt-0.5 text-lg font-bold md:text-xl" style={{ color: cor }}>{valor}</div>
    </div>
  );
}

function Campo({ rotulo, children }) {
  return (
    <div>
      <div className="mb-1 text-2xs text-gray-500">{rotulo}</div>
      {children}
    </div>
  );
}

function Select({ valor, aoTrocar, opcoes, vazio }) {
  return (
    <div className="relative">
      <select value={valor} onChange={(e) => aoTrocar(e.target.value)}
              className="w-full appearance-none rounded-lg border border-gray-200 bg-white px-2 py-1.5 pr-5 text-xs font-medium text-gray-800">
        <option value="">{vazio}</option>
        {opcoes.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
      <ChevronDown size={11} aria-hidden="true"
                   className="pointer-events-none absolute right-1.5 top-2 text-gray-400" />
    </div>
  );
}

function SelectVazio() {
  return (
    <div className="relative">
      <select disabled title="Aguardando o cadastro no Winthor"
              className="w-full appearance-none rounded-lg border border-gray-200 bg-gray-50 px-2 py-1.5 pr-5 text-xs font-medium text-gray-400">
        <option>Todas</option>
      </select>
      <ChevronDown size={11} aria-hidden="true"
                   className="pointer-events-none absolute right-1.5 top-2 text-gray-300" />
    </div>
  );
}

/* `comDetalhe` decide se a etiqueta mostra o texto da planilha ao lado do
 * rótulo. Na TABELA, não: os textos reais são longos ("CREDITO REAL MUITO
 * ABAIXO DO ESPERADO - CONFERIR SE E IMPORTADO (4%)") e um produto pode ter
 * cinco alertas — juntos, empurram a altura da linha para ~100px e desmancham
 * a tabela de 13 colunas, que existe justamente para comparar produtos de
 * relance. Foi esse o defeito que derrubou a primeira versão da tela na v1.
 * O texto integral continua no `title`, a um passar de mouse.
 *
 * No CELULAR, sim: lá não há tabela para desmanchar, o cartão já é vertical, e
 * o detalhe é a informação que evita abrir o produto para descobrir o óbvio. */
function EtiquetaAlerta({ alerta, meta, comDetalhe = false }) {
  const cor = corDoAlerta(meta);
  const Icone = iconeDoAlerta(alerta.tipo);
  const detalhe = comDetalhe ? detalheDoTexto(alerta.texto) : null;
  return (
    <span title={alerta.texto} style={{ background: `${cor}18`, color: cor }}
          className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium">
      <Icone size={11} aria-hidden="true" />
      {meta?.rotulo ?? alerta.tipo}
      {detalhe && <span className="num opacity-80">· {detalhe}</span>}
    </span>
  );
}

/** Preço/MKP/margem do cenário escolhido.
 *
 *  Todos vêm do banco: `cenariosAtacado`/`cenariosVarejo` já trazem custo,
 *  margem e preço sugerido por cenário. O protótipo recalcula tudo em
 *  JavaScript com FATOR_PRAZO e COMISSAO chumbados (§4.6) — duas cópias da
 *  mesma fórmula, e a divergência sairia como um preço plausível e errado.
 *  O MKP é a única conta feita aqui, e é razão pura: preço ÷ custo do cenário.
 */
function infoPreco(p, cenarioSel) {
  const at = p.cenariosAtacado.find((c) => c.id === cenarioSel);
  // Varejo não tem "Oficial" — a redução de base é exclusiva das filiais 02/09
  // (§5). Quando o cenário escolhido não existe lá, cai no cenário REAL do
  // produto, que é o que o protótipo faz.
  const varSel = p.cenariosVarejo.find((c) => c.id === cenarioSel);
  const varUsado = varSel ?? p.cenariosVarejo.find((c) => c.real) ?? p.cenariosVarejo[0];
  const custo = at?.custo ?? null;
  return {
    mkpAtacado: custo > 0 && p.pvAtacado != null ? p.pvAtacado / custo : null,
    mkpVarejo: custo > 0 && p.pvVarejo != null ? p.pvVarejo / custo : null,
    margemAtacado: at?.margemAtual ?? null,
    margemVarejo: varUsado?.margemAtual ?? null,
    sugAtacado: at?.pvSugeridoAV ?? null,
    // null (não o do cenário real) quando o cenário não existe no varejo: a
    // tabela mostra "—", igual ao protótipo, para não dar a entender que o
    // número é do cenário selecionado.
    sugVarejo: varSel ? varSel.pvSugeridoAV : null,
  };
}

const mult = (v) => (v == null ? "—" : `${numero(v, 2)}x`);
const pct = (v) => (v == null ? "—" : `${numero(v * 100, 1)}%`);

function Lista({ itens, cenarioSel, metaPorTipo, aoAbrir }) {
  return (
    <>
      {/* mesa: a tabela de 13 colunas */}
      <div className="hidden px-6 md:block">
        <div className="overflow-x-auto rounded-lg border border-gray-200">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
                <th className="px-2 py-2 text-left font-medium">Código</th>
                <th className="min-w-[260px] px-3 py-2 text-left font-medium">Produto</th>
                <th className="px-2 py-2 text-center font-medium">Classe</th>
                <th className="min-w-[150px] max-w-[220px] px-3 py-2 text-left font-medium">Alertas</th>
                <th className="px-2 py-2 text-center font-medium">Dias s/venda</th>
                <th className="px-2 py-2 text-center font-medium">Cobertura</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_ATACADO }}>MKP AT</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_ATACADO }}>Margem AT</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_ATACADO }}>Sugerido AT</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAREJO }}>MKP VAR</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAREJO }}>Margem VAR</th>
                <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAREJO }}>Sugerido VAR</th>
                <th className="px-2 py-2 text-center font-medium">Valor em risco</th>
              </tr>
            </thead>
            <tbody>
              {itens.map((p) => {
                const info = infoPreco(p, cenarioSel);
                return (
                  <tr key={p.codigo} className="border-t border-gray-100 hover:bg-gray-50">
                    <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
                    <td className="px-3 py-2">
                      <button type="button" onClick={() => aoAbrir(p.codigo)}
                              className="block w-full text-left hover:underline">
                        <div className="whitespace-nowrap font-medium text-gray-800">{p.nome}</div>
                        <div className="num text-2xs text-gray-400">
                          {p.departamento}{p.comprador ? ` · ${p.comprador}` : ""}
                        </div>
                      </button>
                    </td>
                    <td className="px-2 py-2 text-center"><ClasseChip classe={p.classe} /></td>
                    <td className="max-w-[220px] px-3 py-2">
                      <div className="flex flex-wrap gap-1">
                        {p.alertas.map((a) => (
                          <EtiquetaAlerta key={a.tipo} alerta={a} meta={metaPorTipo[a.tipo]} />
                        ))}
                      </div>
                    </td>
                    <td className="num px-2 py-2 text-center">{numero(p.diasSemVenda)}</td>
                    <td className="num px-2 py-2 text-center">{numero(p.mesesCobertura, 1)}</td>
                    <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_ATACADO }}>{mult(info.mkpAtacado)}</td>
                    <td className="num px-2 py-2 text-center" style={{ background: FUNDO_ATACADO, color: info.margemAtacado != null && p.margemAlvo != null && info.margemAtacado < p.margemAlvo ? RED : "#374151" }}>{pct(info.margemAtacado)}</td>
                    <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_ATACADO }}>{moeda(info.sugAtacado)}</td>
                    <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_VAREJO }}>{mult(info.mkpVarejo)}</td>
                    <td className="num px-2 py-2 text-center" style={{ background: FUNDO_VAREJO, color: info.margemVarejo != null && p.margemAlvoVarejo != null && info.margemVarejo < p.margemAlvoVarejo ? RED : "#374151" }}>{pct(info.margemVarejo)}</td>
                    <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_VAREJO }}>{moeda(info.sugVarejo)}</td>
                    <td className="num px-2 py-2 text-center font-semibold" style={{ color: AMBAR }}>{moeda(p.valorEstoque)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* celular: a mesma informação empilhada, na ordem do protótipo */}
      <ul className="divide-y divide-gray-100 md:hidden">
        {itens.map((p) => {
          const info = infoPreco(p, cenarioSel);
          return (
            <li key={p.codigo}>
              <button type="button" onClick={() => aoAbrir(p.codigo)}
                      className="flex w-full items-start gap-2.5 px-4 py-3 text-left active:bg-gray-50">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    <ClasseChip classe={p.classe} />
                    <span className="num truncate text-2xs text-gray-400">{p.departamento}</span>
                  </div>
                  <div className="mt-0.5 truncate text-base font-medium leading-snug text-gray-900">
                    <span className="num text-xs text-gray-400">{p.codigo}</span> {p.nome}
                  </div>
                  <div className="mt-1.5 flex flex-wrap gap-1">
                    {p.alertas.map((a) => (
                      <EtiquetaAlerta key={a.tipo} alerta={a} meta={metaPorTipo[a.tipo]} comDetalhe />
                    ))}
                  </div>
                  <div className="mt-1.5 text-2xs text-gray-500">
                    MKP AT <span className="num font-medium text-gray-700">{mult(info.mkpAtacado)}</span>
                    {" · "}sug. <span className="num text-gray-500">{moeda(info.sugAtacado)}</span>
                    {" · "}MKP VAR <span className="num font-medium text-gray-700">{mult(info.mkpVarejo)}</span>
                    {info.sugVarejo != null && (
                      <> · sug. <span className="num text-gray-500">{moeda(info.sugVarejo)}</span></>
                    )}
                  </div>
                </div>
                <ChevronRight size={16} aria-hidden="true" className="mt-1 shrink-0 text-gray-300" />
              </button>
            </li>
          );
        })}
      </ul>
    </>
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
