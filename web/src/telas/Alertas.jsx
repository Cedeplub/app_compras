import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { api } from "../api/cliente.js";
import { BadgeAlerta, Carregando, ClasseChip, Erro, Vazio } from "../componentes/Basicos.jsx";
import { compacto, moeda, numero, percentual } from "../formato.js";

const POR_PAGINA = 50;

export default function Alertas() {
  const [opcoes, setOpcoes] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [tiposLigados, setTiposLigados] = useState([]);
  const [departamento, setDepartamento] = useState("");
  // Nasce em "Ativo" — é o padrão da tela no protótipo (§2.1), e faz sentido:
  // produto inativo com alerta não é decisão de compra, é limpeza de cadastro.
  const [status, setStatus] = useState("Ativo");
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
        tipoAlerta: tiposLigados,
        // Sem nenhum tipo ligado, a tela mostra quem tem PELO MENOS UM alerta —
        // que não é "todo mundo" (§2.1). A regra vive no backend; aqui só se diz
        // qual das duas listas se quer.
        soComAlerta: tiposLigados.length === 0,
        departamento: departamento || null,
        status: status || null,
        busca: busca || null,
        ordenacao: "cobertura",
        pagina,
        porPagina: POR_PAGINA,
      }));
    } catch (e) {
      setErro(e.detalhe);
      setDados(null);
    } finally {
      setCarregando(false);
    }
  }, [tiposLigados, departamento, status, busca, pagina]);

  useEffect(() => {
    // Espera a digitação parar antes de consultar. Sem isso, "elaion" dispara
    // seis buscas e a última a responder — não a última pedida — é a que fica
    // na tela.
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const alternarTipo = (tipo) => {
    setPagina(1);
    setTiposLigados((atual) =>
      atual.includes(tipo) ? atual.filter((t) => t !== tipo) : [...atual, tipo]);
  };

  const itens = dados?.itens ?? [];
  const valorEmRisco = itens.reduce((s, p) => s + (p.valorEstoque ?? 0), 0);
  const rupturas = itens.filter((p) => p.alertas.some((a) => a.tipo === "RUPTURA")).length;

  return (
    <div className="p-4">
      <div className="grid grid-cols-3 gap-2">
        <Kpi rotulo="Produtos no filtro" valor={numero(dados?.total)} />
        <Kpi rotulo="Valor em risco (página)" valor={`R$ ${compacto(valorEmRisco)}`} />
        <Kpi rotulo="Ruptura (página)" valor={numero(rupturas)} destaque />
      </div>

      <div className="mt-4 flex flex-wrap gap-2">
        <input
          type="search" placeholder="Código, descrição ou cód. fabricante"
          value={busca} onChange={(e) => { setBusca(e.target.value); setPagina(1); }}
          aria-label="Buscar produto"
          className="min-w-[220px] flex-1 rounded-md border border-gray-300 px-3 py-2 text-sm"
        />
        <Select rotulo="Departamento" valor={departamento}
                aoTrocar={(v) => { setDepartamento(v); setPagina(1); }}
                opcoes={opcoes?.departamentos ?? []} vazio="Todos os departamentos" />
        <Select rotulo="Status" valor={status}
                aoTrocar={(v) => { setStatus(v); setPagina(1); }}
                opcoes={opcoes?.status ?? []} vazio="Todos os status" />
      </div>

      {opcoes?.tipos_alerta?.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {opcoes.tipos_alerta.map(({ tipo, quantidade }) => {
            const ligado = tiposLigados.includes(tipo);
            return (
              <button
                key={tipo} type="button" aria-pressed={ligado}
                onClick={() => alternarTipo(tipo)}
                className={`rounded-full border px-2.5 py-1 text-2xs font-semibold transition-colors ${
                  ligado ? "border-navy bg-navy text-white" : "border-gray-300 text-cinza-neutro"}`}
              >
                {tipo.replace(/_/g, " ")} <span className="opacity-70">{numero(quantidade)}</span>
              </button>
            );
          })}
        </div>
      )}

      {status !== "Ativo" && (
        /* Esta nota existe no mobile do protótipo e não no desktop (§8). Aqui
           há uma marcação só, então ela aparece nos dois por construção. */
        <p className="mt-3 rounded-md bg-ambar/10 px-3 py-2 text-xs text-ambar">
          Filtro de status fora de “Ativo”: a lista inclui produtos que não estão
          em linha de compra.
        </p>
      )}

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && itens.length === 0 && (
          <Vazio titulo="Nenhum produto nesse filtro."
                 detalhe="Tente limpar a busca ou desligar alguns tipos de alerta." />
        )}
        {!carregando && !erro && itens.length > 0 && <Lista itens={itens} />}
      </div>

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}
    </div>
  );
}

function Kpi({ rotulo, valor, destaque }) {
  return (
    <div className="rounded-lg border border-gray-200 p-3">
      <p className="text-2xs uppercase tracking-wide text-cinza-neutro">{rotulo}</p>
      <p className={`num mt-1 text-lg font-bold ${destaque ? "text-vermelho" : "text-navy"}`}>
        {valor}
      </p>
    </div>
  );
}

function Select({ rotulo, valor, aoTrocar, opcoes, vazio }) {
  return (
    <select
      aria-label={rotulo} value={valor} onChange={(e) => aoTrocar(e.target.value)}
      className="rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
    >
      <option value="">{vazio}</option>
      {opcoes.map((o) => <option key={o} value={o}>{o}</option>)}
    </select>
  );
}

/* Uma marcação só para celular e mesa: no celular vira cartão empilhado, a
   partir de 768px vira linha de grade. Sem `modoDesktop`, sem JSX duplicado. */
function Lista({ itens }) {
  return (
    <>
      <div className="hidden grid-cols-[80px_1fr_120px_150px_90px_90px_90px] gap-2 border-b border-gray-200 pb-2 text-2xs font-semibold uppercase tracking-wide text-cinza-neutro md:grid">
        <span>Código</span><span>Produto</span><span>Departamento</span><span>Alertas</span>
        <span className="text-right">Cobertura</span><span className="text-right">Margem at.</span>
        <span className="text-right">Estoque R$</span>
      </div>
      <ul className="divide-y divide-gray-100">
        {itens.map((p) => <LinhaProduto key={p.codigo} p={p} />)}
      </ul>
    </>
  );
}

function LinhaProduto({ p }) {
  // A margem que importa é a do cenário que de fato se aplica ao produto. O
  // protótipo mostra aqui um campo estático que NÃO reage ao cenário (§3.2,
  // marcado com ⚠ pelo próprio autor); esta tela usa o cenário real.
  const margemReal = p.cenariosAtacado.find((c) => c.real)?.margemAtual ?? null;
  const critica = p.mesesCobertura != null && p.coberturaAlvo != null
    && p.mesesCobertura < p.coberturaAlvo * 0.6;

  return (
    <li className="py-3 md:grid md:grid-cols-[80px_1fr_120px_150px_90px_90px_90px] md:items-center md:gap-2">
      <span className="num text-sm text-cinza-neutro">{p.codigo}</span>

      <div className="min-w-0">
        <Link to={`/produto/${p.codigo}`}
              className="flex items-center gap-2 font-medium text-gray-900 hover:text-navy">
          <span className="truncate text-md md:text-base">{p.nome}</span>
          <ClasseChip classe={p.classe} />
        </Link>
        <p className="truncate text-xs text-cinza-neutro md:hidden">
          {p.departamento}{p.comprador ? ` · ${p.comprador}` : ""}
        </p>
      </div>

      <span className="hidden truncate text-sm text-cinza-neutro md:block">{p.departamento}</span>

      <div className="mt-1.5 flex flex-wrap gap-1 md:mt-0">
        {p.alertas.length === 0
          ? <span className="text-sm text-gray-300">—</span>
          : p.alertas.map((a) => <BadgeAlerta key={a.tipo} tipo={a.tipo} texto={a.texto} />)}
      </div>

      <div className="mt-2 flex justify-between gap-4 md:mt-0 md:contents">
        <Celula rotulo="Cobertura" className={critica ? "text-vermelho" : ""}>
          {numero(p.mesesCobertura, 2)}
          {p.coberturaAlvo != null && (
            <span className="text-xs font-normal text-cinza-neutro"> / {numero(p.coberturaAlvo, 1)}</span>
          )}
        </Celula>
        <Celula rotulo="Margem at.">{percentual(margemReal)}</Celula>
        <Celula rotulo="Estoque R$">{moeda(p.valorEstoque)}</Celula>
      </div>
    </li>
  );
}

function Celula({ rotulo, children, className = "" }) {
  return (
    <div className={`md:text-right ${className}`}>
      <span className="block text-2xs uppercase text-cinza-neutro md:hidden">{rotulo}</span>
      <span className="num text-sm font-semibold">{children}</span>
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
      <span className="num text-sm text-cinza-neutro">{pagina} de {total}</span>
      <button type="button" disabled={pagina >= total} onClick={() => aoTrocar(pagina + 1)}
              className="rounded-md border border-gray-300 px-3 py-1.5 text-sm disabled:opacity-30">
        Próxima
      </button>
    </div>
  );
}
