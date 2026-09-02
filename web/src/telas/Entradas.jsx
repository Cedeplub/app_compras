import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ChevronDown, Filter, PackagePlus } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, Erro, Vazio } from "../componentes/Basicos.jsx";
import SeletorPeriodo from "../componentes/SeletorPeriodo.jsx";
import { intervalo } from "../periodo.js";
import { compacto, moeda, numero } from "../formato.js";

/* Tela — Entradas (PROTOTIPO.md §2.3, .jsx linha 2017).
 *
 * As últimas movimentações de estoque, agrupadas por Hoje / Ontem / Essa semana
 * / Esse mês. No protótipo a lista é um array estático de 6 linhas e o filtro de
 * período não filtra nada (§8); aqui vem de COMPRAS_ENTRADA, com 180 dias.
 *
 * O protótipo não tem granularidade "Ano" nesta tela — só Dia/Semana/Mês. É
 * coerente: entrada de mercadoria se acompanha em janela curta, e o dado tem
 * 180 dias de histórico, não um ano. Mantido.
 */

const NAVY = "#375DA8";

/* O agrupamento é feito AQUI, e não no dbt, de propósito: "hoje" depende de
 * quando se consulta, não de quando o build rodou. Uma coluna `bucket`
 * materializada estaria errada no dia seguinte. */
function agrupar(itens, referencia) {
  const ref = new Date(`${referencia}T00:00:00Z`);
  const diasAtras = (iso) =>
    Math.round((ref - new Date(`${iso}T00:00:00Z`)) / 86400000);

  const grupos = new Map();
  for (const it of itens) {
    const d = diasAtras(it.data);
    const chave = d <= 0 ? "Hoje" : d === 1 ? "Ontem" : d <= 7 ? "Últimos 7 dias" : "Antes disso";
    if (!grupos.has(chave)) grupos.set(chave, []);
    grupos.get(chave).push(it);
  }
  // Só os grupos com item aparecem — como no protótipo.
  return ["Hoje", "Ontem", "Últimos 7 dias", "Antes disso"]
    .filter((k) => grupos.has(k))
    .map((k) => [k, grupos.get(k)]);
}

export default function Entradas() {
  const navegar = useNavigate();
  const [parametros, setParametros] = useState(null);
  const [opcoes, setOpcoes] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [granularidade, setGranularidade] = useState("Mês");
  const [offset, setOffset] = useState(0);
  const [departamento, setDepartamento] = useState("");
  const [secao, setSecao] = useState("");
  const [busca, setBusca] = useState("");

  useEffect(() => {
    api.parametros().then(setParametros).catch((e) => setErro(e.detalhe));
    api.opcoesMonitoramento().then(setOpcoes).catch(() => setOpcoes(null));
  }, []);

  const referencia = parametros?.data_referencia;
  const periodo = useMemo(
    () => (referencia ? intervalo(granularidade, offset, referencia) : null),
    [granularidade, offset, referencia]);

  const buscar = useCallback(async () => {
    if (!periodo) return;
    setCarregando(true);
    setErro(null);
    try {
      setDados(await api.entradas({
        de: periodo.de, ate: periodo.ate,
        departamento: departamento || null,
        secao: secao || null,
        busca: busca || null,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [periodo, departamento, secao, busca]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const grupos = useMemo(
    () => (dados && referencia ? agrupar(dados.itens, referencia) : []),
    [dados, referencia]);

  return (
    <div className="px-4 pb-6 pt-3 md:px-6 md:pt-4">
      {/* Sem "Ano": entrada se acompanha em janela curta, e o dado tem 180 dias. */}
      <SeletorPeriodo granularidade={granularidade} setGranularidade={setGranularidade}
                      offset={offset} setOffset={setOffset} referencia={referencia} />

      <div className="mt-3 flex flex-wrap items-end gap-3">
        <Campo rotulo="Departamento" largura="w-44">
          <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                  aoTrocar={setDepartamento} />
        </Campo>
        <Campo rotulo="Seção" largura="w-44">
          <Select valor={secao} vazio="Todas" opcoes={opcoes?.secoes ?? []} aoTrocar={setSecao} />
        </Campo>
        <Campo rotulo="Buscar produto" largura="w-52">
          <div className="relative">
            <input type="search" value={busca} onChange={(e) => setBusca(e.target.value)}
                   aria-label="Buscar produto" placeholder="Nome ou código…"
                   className="w-full rounded-lg border border-gray-200 py-1.5 pl-7 pr-2.5 text-sm" />
            <Filter size={11} aria-hidden="true" className="absolute left-2.5 top-2.5 text-gray-400" />
          </div>
        </Campo>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2 md:max-w-md">
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <div className="text-2xs uppercase tracking-wide text-gray-500">Valor das entradas</div>
          <div className="num mt-1 text-2xl font-bold" style={{ color: NAVY }}>
            {dados ? `R$ ${compacto(dados.valorTotal)}` : "—"}
          </div>
        </div>
        <div className="rounded-xl bg-gray-50 px-4 py-3">
          <div className="text-2xs uppercase tracking-wide text-gray-500">Itens recebidos</div>
          <div className="num mt-1 text-2xl font-bold" style={{ color: NAVY }}>
            {dados ? numero(dados.linhas) : "—"}
          </div>
          {dados && (
            <div className="num text-2xs text-gray-400">{numero(dados.produtos)} produtos</div>
          )}
        </div>
      </div>

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && grupos.length === 0 && (
          <Vazio titulo="Nenhuma entrada nesse filtro."
                 detalhe="Tente outro período ou limpe os filtros." />
        )}

        {grupos.map(([titulo, itens]) => (
          <section key={titulo} className="mt-4">
            <h3 className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <PackagePlus size={12} aria-hidden="true" />
              {titulo}
              <span className="num font-normal text-gray-400">
                · {numero(itens.length)} item(ns) ·{" "}
                {moeda(itens.reduce((s, i) => s + i.valor, 0))}
              </span>
            </h3>
            <div className="overflow-x-auto rounded-lg border border-gray-200">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
                    <th className="px-2 py-2 text-left font-medium">Data</th>
                    <th className="px-2 py-2 text-left font-medium">Código</th>
                    <th className="min-w-[220px] px-3 py-2 text-left font-medium">Produto</th>
                    <th className="px-3 py-2 text-left font-medium">Departamento</th>
                    <th className="px-2 py-2 text-center font-medium">Tipo</th>
                    <th className="px-3 py-2 text-right font-medium">Qtd.</th>
                    <th className="px-3 py-2 text-right font-medium">Preço unit.</th>
                    <th className="px-3 py-2 text-right font-medium">Valor</th>
                  </tr>
                </thead>
                <tbody>
                  {itens.map((it, i) => (
                    <tr key={`${it.codigo}-${it.data}-${i}`} className="border-t border-gray-100 hover:bg-gray-50">
                      <td className="num px-2 py-2 text-2xs text-gray-500">
                        {it.data.split("-").reverse().slice(0, 2).join("/")}
                      </td>
                      <td className="num px-2 py-2 text-gray-500">{it.codigo}</td>
                      <td className="px-3 py-2">
                        <button type="button" onClick={() => navegar(`/produto/${it.codigo}`)}
                                className="text-left font-medium text-gray-800 hover:underline">
                          {it.nome}
                        </button>
                        {it.secao && <div className="num text-2xs text-gray-400">{it.secao}</div>}
                      </td>
                      <td className="px-3 py-2 text-gray-500">{it.departamento}</td>
                      <td className="px-2 py-2 text-center">
                        {/* Bonificação entra no estoque sem custo de compra —
                            vale distinguir de uma compra normal na leitura. */}
                        <span className="rounded-full px-2 py-0.5 text-2xs font-semibold"
                              style={{ background: `${NAVY}12`, color: NAVY }}>
                          {it.tipo}
                        </span>
                      </td>
                      <td className="num px-3 py-2 text-right">{numero(it.quantidade, 0)}</td>
                      <td className="num px-3 py-2 text-right text-gray-500">{moeda(it.precoUnitario)}</td>
                      <td className="num px-3 py-2 text-right font-semibold">{moeda(it.valor)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        ))}
      </div>
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

function Select({ valor, aoTrocar, opcoes, vazio }) {
  return (
    <div className="relative">
      <select value={valor} onChange={(e) => aoTrocar(e.target.value)}
              className="w-full appearance-none rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 pr-6 text-sm font-medium text-gray-800">
        <option value="">{vazio}</option>
        {opcoes.map((o) => <option key={o} value={o}>{o}</option>)}
      </select>
      <ChevronDown size={12} aria-hidden="true"
                   className="pointer-events-none absolute right-2 top-2.5 text-gray-400" />
    </div>
  );
}
