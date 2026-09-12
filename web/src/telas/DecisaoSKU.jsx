import { useCallback, useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { Check, ChevronDown, ChevronLeft, Layers, Loader2 } from "lucide-react";
import { api } from "../api/cliente.js";
import { Carregando, ClasseChip, Erro } from "../componentes/Basicos.jsx";
import { simular, TOLERANCIA_PRECO_IGUAL, valorAntesDoCredito } from "../precificacao.js";
import {
  compacto, data as fmtData, mesCurto, mesesAntes, moeda, numero, paraCampoPreco, parseNumeroPreco,
} from "../formato.js";
import { METRICAS } from "../periodo.js";
import { textoConfirmacaoLote } from "../lotePrecoStatus.js";

/* Nível 2 — Decisão do SKU (PROTOTIPO.md §2.10, .jsx linha 2395).
 *
 * No protótipo esta tela substitui todas as outras quando `skuAberto` está
 * preenchido, e sair dela perde tudo que foi digitado (§2.10). Aqui ela tem URL
 * própria (`/produto/:codigo`), então dá para mandar o link de um produto para
 * o Diretor e recarregar não perde o lugar.
 */

const NAVY = "#375DA8";
const RED = "#DE434B";
const AMBAR = "#B98A2E";
const AMARELO = "#FBBF24";

const CENARIOS = [
  { id: "st_valor", rotulo: "ST s/Valor" },
  { id: "oficial", rotulo: "Oficial (c/ redução)" },
  { id: "sem_red", rotulo: "Sem Redução" },
];

const mult = (v) => (v == null ? "—" : `${numero(v, 2)}x`);
const pct = (v, c = 1) => (v == null ? "—" : `${numero(v * 100, c)}%`);

export default function DecisaoSKU() {
  const { codigo } = useParams();
  const navegar = useNavigate();
  const [produto, setProduto] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [cenarioSel, setCenarioSel] = useState("st_valor");
  const [pedido, setPedido] = useState("");

  const carregar = useCallback(async () => {
    setCarregando(true);
    setErro(null);
    try {
      const [p, par] = await Promise.all([api.produto(codigo), api.parametros()]);
      setProduto(p);
      setParametros(par);
    } catch (e) {
      setErro(e.detalhe);
    } finally {
      setCarregando(false);
    }
  }, [codigo]);

  useEffect(() => { carregar(); }, [carregar]);

  if (carregando) return <Carregando>Buscando o produto…</Carregando>;
  if (erro) return <Erro mensagem={erro} aoTentarDeNovo={carregar} />;
  if (!produto) return null;

  const p = produto;
  // FATOR_EXIBICAO já resolve "pede em caixa fechada?" em número: vale
  // embal_compra quando o departamento é MASTER, e 1 quando não. O protótipo
  // refaz essa pergunta com uma lista de 5 nomes escrita à mão (§5/§9).
  const fator = p.fatorExibicao || 1;
  const pedidoNum = Number(String(pedido).replace(",", ".")) || 0;
  const pedidoUnidades = pedidoNum * fator;
  const coberturaAtual = p.mediaJanela > 0 ? p.estDisp / p.mediaJanela : null;
  const coberturaAposPedido = p.mediaJanela > 0
    ? (p.estDisp + (p.estPend ?? 0) + pedidoUnidades) / p.mediaJanela : null;
  const critica = coberturaAtual != null && p.coberturaAlvo != null
    && coberturaAtual < p.coberturaAlvo * (parametros?.cobertura_critica_fracao ?? 0.6);

  return (
    <div className="mx-auto max-w-sku pb-8">
      <div className="flex items-start justify-between gap-4 px-4 py-3 md:px-6"
           style={{ background: NAVY }}>
        <div className="min-w-0">
          <button type="button" onClick={() => navegar(-1)}
                  className="mb-2 flex items-center gap-1 text-sm font-medium text-white">
            <ChevronLeft size={14} aria-hidden="true" />
            Voltar
          </button>
          <h1 className="truncate text-lg font-semibold leading-tight text-white">{p.nome}</h1>
          <p className="num mt-0.5 truncate text-xs text-white/70">
            {p.codigo} · {p.departamento}{p.comprador ? ` · ${p.comprador}` : ""}
            {p.codFab ? ` · fab ${p.codFab}` : ""}
          </p>
        </div>
        <ClasseChip classe={p.classe} />
      </div>

      <div className="px-4 pt-4 md:px-6">
        <Contexto p={p} coberturaAtual={coberturaAtual} critica={critica} />
        <Avisos p={p} />
        <Grafico p={p} mesReferencia={parametros?.mes_referencia} />
        <Fiscal p={p} cenarioSel={cenarioSel} />

        <div className="mt-3 md:max-w-xs">
          <div className="mb-1 text-2xs text-gray-500">
            Cenário de margem — muda o cenário em destaque nos dois blocos abaixo e a margem atual
          </div>
          <div className="relative">
            <select value={cenarioSel} onChange={(e) => setCenarioSel(e.target.value)}
                    aria-label="Cenário de margem"
                    className="w-full appearance-none rounded-lg border border-gray-200 bg-white px-3 py-1.5 pr-7 text-sm font-medium text-gray-800">
              {CENARIOS.map((c) => <option key={c.id} value={c.id}>{c.rotulo}</option>)}
            </select>
            <ChevronDown size={13} aria-hidden="true"
                         className="pointer-events-none absolute right-3 top-2 text-gray-400" />
          </div>
        </div>

        <div className="md:grid md:grid-cols-2 md:gap-4">
          <BlocoPreco titulo="Preço — Atacado" p={p} praca="atacado"
                      cenarios={p.cenariosAtacado} cenarioSel={cenarioSel}
                      precoAtual={p.pvAtacado} margemAlvo={p.margemAlvo}
                      fatorPrazo={parametros.fator_prazo_atacado} parametros={parametros}
                      decidido={p.precoDecididoAtacadoAV}
                      aoSalvar={(v) => api.criarOuAcrescentarLotePreco(
                        [{ codigo: p.codigo, precoAtacadoAV: v }])}
                      aoConcluir={carregar} />
          <BlocoPreco titulo="Preço — Varejo" p={p} praca="varejo"
                      cenarios={p.cenariosVarejo} cenarioSel={cenarioSel}
                      precoAtual={p.pvVarejo} margemAlvo={p.margemAlvoVarejo}
                      fatorPrazo={parametros.fator_prazo_varejo} parametros={parametros}
                      decidido={p.precoDecididoVarejoAV}
                      aoSalvar={(v) => api.criarOuAcrescentarLotePreco(
                        [{ codigo: p.codigo, precoVarejoAV: v }])}
                      aoConcluir={carregar} />
        </div>

        <DecisaoCompra p={p} pedido={pedido} setPedido={setPedido}
                       fator={fator} pedidoUnidades={pedidoUnidades}
                       coberturaAposPedido={coberturaAposPedido} />
      </div>
    </div>
  );
}

/* ---------------------------------------------------------------- contexto --- */

function Contexto({ p, coberturaAtual, critica }) {
  return (
    <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
      <Cartao rotulo="Estoque disponível" valor={numero(p.estDisp, 0)}
              nota={p.estPend != null ? `+ pendente ${numero(p.estPend, 0)}` : null} />
      <Cartao rotulo="Média mensal" valor={numero(p.mediaJanela, 0)}
              nota={p.nMeses ? `janela de ${numero(p.nMeses, 0)} meses` : null} />
      <Cartao rotulo="Cobertura" cor={critica ? RED : undefined}
              valor={coberturaAtual != null ? `${numero(coberturaAtual, 2)} m` : "—"}
              nota={p.coberturaAlvo != null ? `alvo ${numero(p.coberturaAlvo, 1)} m` : null} />
      <Cartao rotulo="Última saída" valor={fmtData(p.ultimaSaida)}
              nota={p.qtdUltimaSaida != null ? `${numero(p.qtdUltimaSaida, 0)} un` : null} />
    </div>
  );
}

function Cartao({ rotulo, valor, nota, cor }) {
  return (
    <div className="rounded-xl bg-gray-50 px-2.5 py-2.5">
      <div className="text-2xs leading-tight text-gray-500">{rotulo}</div>
      <div className="num mt-0.5 text-base font-bold" style={{ color: cor ?? NAVY }}>{valor}</div>
      {nota && <div className="num text-[9px] text-gray-400">{nota}</div>}
    </div>
  );
}

/* Faixas de aviso — porte de `FaixaAviso` (.jsx 2386).
 *
 * O protótipo tem três: sazonalidade, sucessão e campanha. Só SUCESSÃO existe
 * no banco hoje (ANT_1/ANT_2 de COMPRAS_PEDIDO). Sazonalidade e campanha são
 * textos livres escritos por gente e ainda não têm tabela — estão no PLANO §2.3
 * como `APP_AVISO_PRODUTO`. Não desenho faixa vazia para elas: uma faixa que
 * nunca aparece é ruído no código e promessa quebrada na tela. */
function Avisos({ p }) {
  if (!p.sucessao?.length) return null;
  return (
    <div className="mt-3 flex items-start gap-2 rounded-lg px-3 py-2"
         style={{ background: `${NAVY}0D` }}>
      <Layers size={14} className="mt-0.5 shrink-0" style={{ color: NAVY }} aria-hidden="true" />
      <p className="text-xs" style={{ color: NAVY }}>
        Herda histórico de venda de{" "}
        {p.sucessao.map((s, i) => (
          <span key={s.antecessor} className="num font-semibold">
            {i > 0 ? " e " : ""}{s.antecessor}
            {s.peso != null ? ` (${pct(s.peso, 0)})` : ""}
          </span>
        ))}
        . A média e a cobertura acima já contam essa herança.
      </p>
    </div>
  );
}

/* Mini-gráfico de venda: os 4 meses recentes em navy, o mesmo mês do ano
 * anterior em amarelo (#FBBF24, §6). Etapa 13, ponto 1 (pedido do Diretor,
 * print do produto 7066): as quatro métricas de Monitoramento.jsx — o
 * seletor é o MESMO `METRICAS` de `periodo.js` (importado, não redeclarado —
 * duas listas divergiriam de rótulo entre as duas telas).
 *
 * Os rótulos são o NOME do mês ("ago/26"), não "M-1"/"M-2"/"M-3" como no
 * protótipo: contar para trás de cabeça é trabalho que a tela pode poupar.
 *
 * ⚠ Os nomes derivam de `MES_REFERENCIA`, que vem do DADO (o `max(mes)` da
 * série mensal), e não da data do dispositivo. Se o build do dia atrasar, a
 * tela continua nomeando corretamente o mês que os números representam — em vez
 * de chamar de "setembro" uma barra que é de agosto.
 *
 * ⚠ `p.vendaHistorico` e `p.anoAnterior` são objetos POR MÉTRICA
 * (`{quantidade, faturamento, peso, litros}`, cada um pronto — nenhuma conta
 * de FATOR_EXIBICAO aqui: o servidor já divide só a quantidade
 * (`app/api/contrato.py:_venda_historico`), CONTEXTO.md regra 6. Trocar de
 * métrica é só reler o objeto que já veio — nenhuma ida ao servidor. */
function Grafico({ p, mesReferencia }) {
  const [metrica, setMetrica] = useState("quantidade");

  // §2.4: 436 dos 4.558 produtos ativos não têm litragem cadastrada
  // (L_POR_UNIDADE nulo ou zero) — o 7066 do print do Diretor é um deles
  // (graxa de 500 g). "Litros" renderia cinco barras rentes ao chão nesses
  // casos, e isso parece defeito; o botão desabilitado com o motivo é
  // informação. Medido no cadastro do PRODUTO, não no resultado da venda —
  // um produto com litragem de verdade pode legitimamente vender zero litros
  // num mês, e isso não deve desabilitar nada.
  const semLitragem = !p.litragemUnidade;

  // `/produto/:codigo` reaproveita o mesmo componente ao navegar de um SKU
  // para outro (mesmo comentário de `BlocoPreco`, mais abaixo) — sem isto,
  // sair de um produto com litragem tendo "Litros" selecionado e abrir um
  // sem litragem manteria a métrica proibida ativa: o botão nasceria
  // desabilitado, mas o gráfico continuaria mostrando cinco barras rentes ao
  // chão da métrica que o §2.4 existe para esconder.
  useEffect(() => {
    if (semLitragem && metrica === "litros") setMetrica("quantidade");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.codigo, semLitragem]);

  const historico = p.vendaHistorico?.[metrica] ?? [null, null, null, null];
  const anoAnteriorValor = p.anoAnterior?.[metrica] ?? null;

  const fmt = (v) => (v == null ? "—" : metrica === "faturamento" ? `R$ ${compacto(v)}`
    : metrica === "peso" ? `${compacto(v)} kg`
    : metrica === "litros" ? `${compacto(v)} L`
    : compacto(v));

  const barras = historico.map((v, i) => ({
    // vendaHistorico[metrica] é [Atual, M-1, M-2, M-3]: o índice é quantos
    // meses antes da referência aquela barra está.
    rotulo: mesReferencia ? mesCurto(mesesAntes(mesReferencia, i)) : ["Atual", "M-1", "M-2", "M-3"][i],
    // O primeiro é o mês corrente, ainda em curso — dizer isso evita ler uma
    // barra baixa como queda de venda quando é só mês pela metade.
    nota: i === 0 ? "em curso" : null,
    valor: v ?? 0,
    cor: NAVY,
  }));
  if (anoAnteriorValor != null) {
    barras.push({
      rotulo: mesReferencia ? mesCurto(mesesAntes(mesReferencia, 12)) : "Ano ant.",
      nota: "ano anterior",
      valor: anoAnteriorValor,
      cor: AMARELO,
    });
  }
  const maior = Math.max(...barras.map((b) => b.valor), 1);

  return (
    <div className="mt-3 rounded-xl border border-gray-200 px-3 py-3">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <div className="text-xs font-medium text-gray-600">Venda dos últimos meses</div>
        {/* Mesmo desenho do seletor de `Monitoramento.jsx:104` — pílulas num
            fundo cinza, a ativa em navy. Trocar aqui NÃO busca de novo: os 20
            números (4 métricas × 5 períodos) já vieram juntos de
            `/api/produtos/{codigo}`. */}
        <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
          {METRICAS.map((m) => {
            const desabilitada = m.id === "litros" && semLitragem;
            return (
              <button key={m.id} type="button" aria-pressed={metrica === m.id}
                      disabled={desabilitada}
                      onClick={() => setMetrica(m.id)}
                      title={desabilitada ? "Este produto não tem litragem cadastrada" : undefined}
                      style={metrica === m.id && !desabilitada ? { background: NAVY, color: "white" } : {}}
                      className="rounded-md px-2 py-1 text-[11px] font-medium text-gray-500 disabled:cursor-not-allowed disabled:text-gray-300">
                {m.rotulo}
              </button>
            );
          })}
        </div>
      </div>
      <div className="flex items-end gap-2" style={{ height: 84 }}>
        {barras.map((b) => (
          <div key={b.rotulo} className="flex flex-1 flex-col items-center justify-end gap-1">
            <span className="num text-[9px] text-gray-500">{fmt(b.valor)}</span>
            <div className="w-full rounded-t"
                 style={{ background: b.cor, height: `${Math.max(2, (b.valor / maior) * 56)}px` }} />
            <span className="text-[9px] text-gray-500">{b.rotulo}</span>
            {b.nota && <span className="text-[8px] leading-none text-gray-400">{b.nota}</span>}
          </div>
        ))}
      </div>
      {anoAnteriorValor == null && (
        // Distinguir "não há dado" de "vendeu zero" importa aqui: uma barra
        // rente ao chão diria que o produto existia e não vendeu.
        <p className="mt-1.5 text-[9px] text-gray-400">
          Sem registro de venda no mesmo mês do ano anterior.
        </p>
      )}
    </div>
  );
}

function Fiscal({ p, cenarioSel }) {
  const cen = p.cenariosAtacado.find((c) => c.id === cenarioSel) ?? p.cenariosAtacado[0];
  const cor = { ST_SUBSTITUTO: NAVY, ST_RECOLHIDO: "#7C3AED" }[p.modalidade] ?? "#6B7280";
  const rotulo = { ST_SUBSTITUTO: "ST Substituto", ST_RECOLHIDO: "ST Recolhido" }[p.modalidade] ?? "Normal";
  const igual = p.custoUltimaEntrada != null && cen?.custo != null
    && Math.abs(p.custoUltimaEntrada - cen.custo) < 0.01;

  return (
    <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-gray-500">
      <span className="inline-flex flex-wrap items-center gap-1">
        <span className="rounded-full px-2 py-0.5 text-2xs font-semibold"
              style={{ background: `${cor}18`, color: cor }}>{rotulo}</span>
        {p.creditoPisCofins === 0 && (
          <span className="rounded-full bg-gray-200 px-2 py-0.5 text-2xs font-semibold text-gray-600">
            Monofásico
          </span>
        )}
        {p.regimeFiscal && <span className="text-[9px] text-gray-400">{p.regimeFiscal}</span>}
      </span>
      {igual ? (
        <>
          <span>Custo <span className="num font-medium text-gray-700">{moeda(cen.custo)}</span></span>
          <span>Valor NF <span className="num font-medium text-gray-700">
            {moeda(valorAntesDoCredito(cen.custo, p.creditoICMS, p.creditoPisCofins))}</span></span>
        </>
      ) : (
        <span className="flex flex-col gap-0.5">
          <span className="num">Custo — últ {moeda(p.custoUltimaEntrada)} / ger {moeda(cen?.custo)}</span>
          <span className="num">Valor NF — últ {moeda(valorAntesDoCredito(p.custoUltimaEntrada, p.creditoICMS, p.creditoPisCofins))} / ger {moeda(valorAntesDoCredito(cen?.custo, p.creditoICMS, p.creditoPisCofins))}</span>
        </span>
      )}
    </div>
  );
}

/* ------------------------------------------------------------ bloco preço --- */

function BlocoPreco({ titulo, p, praca, cenarios, cenarioSel, precoAtual, margemAlvo,
                      fatorPrazo, parametros, decidido, aoSalvar, aoConcluir }) {
  const [expandido, setExpandido] = useState(false);
  // O campo nasce preenchido com o preço já DECIDIDO (editável) quando existe
  // decisão — é a correção do item 2 do Diretor ("nem tem opção de editar").
  // Isto NÃO viola a regra 10 do CONTEXTO: `decidido` vem de
  // `APP_DECISAO_PRECO`, o número que uma PESSOA decidiu — o oposto de nascer
  // com `PV_SUG_*` (a sugestão do modelo), que continua proibido. Sem decisão,
  // o campo nasce vazio, com a sugestão só no placeholder (abaixo). O
  // protótipo nasce sempre preenchido com a SUGESTÃO (§2.10) — o que, num
  // campo que grava em APP_DECISAO_PRECO, faria a tela propor uma decisão que
  // ninguém tomou.
  const [valor, setValor] = useState(() => paraCampoPreco(decidido));
  const [estado, setEstado] = useState("parado");
  const [erroSalvar, setErroSalvar] = useState(null);
  // Para onde foi o preço decidido aqui — id do lote e se o servidor abriu um
  // documento novo ou reaproveitou o Rascunho já aberto do usuário (§4.2/§4.3
  // do PROMPT_ETAPA_12, ajuste de 10/09/2026). Sem isto a decisão desaparece
  // depois de gravada — o mesmo beco sem saída que a mudança existe para
  // fechar, só que dentro desta tela.
  const [confirmacaoLote, setConfirmacaoLote] = useState(null);

  // `DecisaoSKU` não tem `key={codigo}` na rota (`/produto/:codigo` reaproveita
  // o mesmo componente ao navegar de um SKU para outro), então o `useState`
  // acima só roda uma vez, no primeiro produto que a tela abrir. Sem este
  // efeito, trocar de SKU por um link (ex.: a partir da Precificação) faria
  // este bloco continuar mostrando o valor do produto ANTERIOR.
  useEffect(() => {
    setValor(paraCampoPreco(decidido));
    setEstado("parado");
    setErroSalvar(null);
    setConfirmacaoLote(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.codigo]);

  const sim = simular({ produto: p, cenarios, cenarioSel, precoAtual,
                        precoDigitado: valor, fatorPrazo, parametros });
  const outros = cenarios.filter((c) => c.id !== sim.cenario?.id);

  // `parseNumeroPreco` (formato.js): lê de volta o mesmo formato que
  // `paraCampoPreco` produziu acima, sem cair no ponto-de-milhar que quebrava
  // "Gravar preço" para todo produto decidido acima de R$ 1.000 (o parser
  // ingênuo lia "1.234,56" como "1.234.56" → NaN → 0 em silêncio).
  const parsedDigitado = parseNumeroPreco(valor);
  const numeroDigitado = Number.isFinite(parsedDigitado) && parsedDigitado > 0 ? parsedDigitado : 0;
  const podeSalvar = numeroDigitado > 0
    && (decidido == null || Math.abs(numeroDigitado - decidido) >= TOLERANCIA_PRECO_IGUAL);

  async function salvar() {
    setEstado("salvando");
    setErroSalvar(null);
    try {
      // `aoSalvar` chama `POST /lotes-preco` com UM item, sem `idLote` — o
      // servidor resolve sozinho se cria um lote ou soma ao Rascunho aberto
      // do usuário (§4.2/§4.3). A resposta traz o id e `loteReaproveitado`;
      // guardamos os dois para a confirmação apontar para o documento certo.
      const r = await aoSalvar(numeroDigitado);
      setEstado("salvo");
      setConfirmacaoLote({ idLote: r.id, loteReaproveitado: r.loteReaproveitado ?? null });
      await aoConcluir();
    } catch (e) {
      setErroSalvar(e.status === 404 ? "Só a diretoria pode gravar preço." : e.detalhe);
      setEstado("erro");
    }
  }

  // Defeito A (PROMPT_ETAPA_12 §2): "salvo" é um aviso momentâneo, não um
  // estado permanente do bloco — sem isto, depois de gravar uma vez o botão
  // "Gravar preço" nunca mais reaparecia neste produto. Mesmo caminho de
  // `Precificacao.jsx`: limpar o estado no ponto de entrada da digitação, não
  // num `useEffect` no valor — aqui toda mudança de valor É digitação (o
  // campo não é rebuscado por baixo do usuário).
  function aoDigitar(v) {
    setValor(v);
    if (estado !== "parado") {
      setEstado("parado");
      setErroSalvar(null);
      setConfirmacaoLote(null);
    }
  }

  return (
    <div className="mt-3 rounded-xl border border-gray-200 bg-white px-3.5 py-3">
      <div className="mb-2 text-sm font-semibold text-gray-800">{titulo}</div>

      <Linha rotulo="Preço atual" valor={moeda(precoAtual)} forte />
      <Linha rotulo="MKP atual" valor={mult(sim.mkpAtual)} />
      <Linha rotulo={`Margem atual (${sim.cenario?.rotulo ?? "—"})`}
             valor={pct(sim.margemAtual)}
             cor={sim.margemAtual != null && margemAlvo != null && sim.margemAtual < margemAlvo ? RED : NAVY} />

      {sim.cenario && <CenarioCard cenario={sim.cenario} margemAlvo={margemAlvo} />}

      {!sim.existeNestaPraca && (
        <p className="mt-1 text-2xs text-gray-400">
          “Oficial” não existe no varejo — mostrando {sim.cenario?.rotulo} aqui.
        </p>
      )}

      {outros.length > 0 && (
        <>
          <button type="button" onClick={() => setExpandido((v) => !v)}
                  aria-expanded={expandido}
                  className="mt-2 flex w-full items-center justify-center gap-1 py-1 text-xs font-medium"
                  style={{ color: NAVY }}>
            {expandido ? "Ver menos" : `Ver outros ${outros.length} cenário(s)`}
            <ChevronDown size={12} aria-hidden="true" className={expandido ? "rotate-180" : ""} />
          </button>
          {expandido && (
            <div className="mt-1 space-y-2">
              {outros.map((c) => <CenarioCard key={c.id} cenario={c} margemAlvo={margemAlvo} />)}
            </div>
          )}
        </>
      )}

      <div className="mt-3 border-t border-gray-100 pt-3">
        <label className="mb-1 block text-xs text-gray-500"
               htmlFor={`preco-${praca}-${p.codigo}`}>
          Preço final decidido (à vista)
        </label>
        <input id={`preco-${praca}-${p.codigo}`} type="text" inputMode="decimal"
               value={valor} onChange={(e) => aoDigitar(e.target.value)}
               // Placeholder só quando o campo nasce vazio (sem decisão) — com
               // decisão ele já nasce preenchido com ELA (acima), e a sugestão
               // desce para a linha de apoio "sugerido", porque um placeholder
               // não aparece atrás de um valor.
               placeholder={decidido == null && sim.sugerido != null ? numero(sim.sugerido, 2) : "—"}
               className="num w-full rounded-lg border border-gray-300 px-3 py-2 text-md font-medium text-gray-900" />

        {decidido != null && (
          <p className="num mt-1 text-2xs" style={{ color: NAVY }}>
            Já decidido: {moeda(decidido)}
          </p>
        )}
        {decidido != null && sim.sugerido != null && (
          <p className="num mt-1 text-2xs text-gray-400">
            Sugerido: {moeda(sim.sugerido)}
          </p>
        )}

        {sim.novo != null && (
          <p className="mt-1.5 text-xs" style={{ color: NAVY }}>
            → MKP <span className="num font-semibold">{mult(sim.mkpNovo)}</span> · Margem{" "}
            <span className="num font-semibold">{pct(sim.margemNova)}</span>
          </p>
        )}
        {sim.prazo != null && (
          <p className="mt-1.5 border-t border-gray-100 pt-1.5 text-xs text-gray-500">
            A prazo <span className="num font-medium text-gray-800">{moeda(sim.prazo)}</span> · MKP{" "}
            <span className="num">{mult(sim.mkpPrazo)}</span> · Margem{" "}
            <span className="num">{pct(sim.margemPrazo)}</span>
          </p>
        )}

        {podeSalvar && estado !== "salvo" && (
          <button type="button" onClick={salvar} disabled={estado === "salvando"}
                  className="mt-2.5 flex w-full items-center justify-center gap-1.5 rounded-lg py-2 text-sm font-semibold text-white disabled:opacity-50"
                  style={{ background: NAVY }}>
            {estado === "salvando" && <Loader2 size={13} className="animate-spin" aria-hidden="true" />}
            {estado === "salvando" ? "Gravando…" : "Gravar preço"}
          </button>
        )}
        {estado === "salvo" && confirmacaoLote && (
          // Mais discreto que a faixa da Precificação (lá são até 200 itens de
          // uma vez; aqui é um preço só) — mas tem link para o lote de verdade.
          // Decidir preço aqui e não ver para onde aquilo foi é o mesmo beco
          // sem saída da Precificação, só que com outra roupa (PROMPT_ETAPA_12,
          // ajuste de 10/09/2026).
          <div className="mt-2.5 text-center text-sm font-semibold" style={{ color: "#15803D" }}>
            <p className="flex items-center justify-center gap-1">
              <Check size={14} aria-hidden="true" /> Preço gravado
            </p>
            <p className="mt-0.5 text-xs font-normal text-gray-500">
              {textoConfirmacaoLote(1, confirmacaoLote.idLote, confirmacaoLote.loteReaproveitado)}{" "}
              <Link to={`/precos-definidos/${confirmacaoLote.idLote}`}
                    className="font-semibold underline" style={{ color: "#15803D" }}>
                Ver lote
              </Link>
            </p>
          </div>
        )}
        {estado === "erro" && (
          <p role="alert" className="mt-2 text-xs" style={{ color: RED }}>{erroSalvar}</p>
        )}
      </div>
    </div>
  );
}

function Linha({ rotulo, valor, cor, forte }) {
  return (
    <div className="mb-1 flex items-center justify-between text-sm">
      <span className="text-gray-500">{rotulo}</span>
      <span className={`num ${forte ? "font-medium text-gray-800" : "font-medium"}`}
            style={cor ? { color: cor } : undefined}>{valor}</span>
    </div>
  );
}

function CenarioCard({ cenario, margemAlvo }) {
  return (
    <div className="mt-2 rounded-lg border border-gray-100 px-3 py-2.5">
      <div className="mb-1 flex items-center gap-1 text-xs font-medium text-gray-600">
        {cenario.rotulo}
        {cenario.real && (
          <span className="rounded px-1 py-0.5 text-[9px] font-bold"
                style={{ background: `${NAVY}18`, color: NAVY }}>
            CENÁRIO REAL
          </span>
        )}
      </div>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-500">
          Sugerido p/ meta ({margemAlvo != null ? pct(margemAlvo, 0) : "—"})
        </span>
        <span className="num font-medium text-gray-800">
          {moeda(cenario.pvSugeridoAV)} <span className="text-gray-400">à vista</span>
        </span>
      </div>
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-400">a prazo</span>
        <span className="num text-gray-600">{moeda(cenario.pvSugeridoAP)}</span>
      </div>
      <div className="mt-1 flex items-center justify-between text-2xs text-gray-400">
        <span>custo do cenário</span>
        <span className="num">{moeda(cenario.custo)}</span>
      </div>
    </div>
  );
}

/* --------------------------------------------------------- decisão compra --- */

function DecisaoCompra({ p, pedido, setPedido, fator, pedidoUnidades, coberturaAposPedido }) {
  const emCaixa = fator > 1;
  return (
    <div className="mt-4 rounded-xl px-3.5 py-3"
         style={{ background: `${RED}0D`, border: `1px solid ${RED}33` }}>
      <div className="mb-2 text-sm font-semibold" style={{ color: RED }}>Decisão de compra</div>

      <label className="mb-1 block text-xs text-gray-600" htmlFor={`pedido-${p.codigo}`}>
        Quantidade a pedir {emCaixa
          ? `(caixas de ${numero(p.embalCompra, 0)})`
          : "(unidades)"}
      </label>
      <input id={`pedido-${p.codigo}`} type="text" inputMode="decimal"
             value={pedido} onChange={(e) => setPedido(e.target.value)}
             placeholder={p.sugCobertura != null ? numero(p.sugCobertura, 0) : "—"}
             className="num w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-md font-medium" />

      <div className="mt-2 space-y-1 text-xs text-gray-600">
        {emCaixa && pedidoUnidades > 0 && (
          <div className="flex justify-between">
            <span>Em unidades</span>
            <span className="num font-medium">{numero(pedidoUnidades, 0)}</span>
          </div>
        )}
        <div className="flex justify-between">
          <span>Cobertura depois deste pedido</span>
          <span className="num font-semibold" style={{ color: NAVY }}>
            {coberturaAposPedido != null ? `${numero(coberturaAposPedido, 2)} m` : "—"}
            {p.coberturaAlvo != null && (
              <span className="font-normal text-gray-400"> / alvo {numero(p.coberturaAlvo, 1)}</span>
            )}
          </span>
        </div>
        {p.sugCobertura != null && (
          <div className="flex justify-between">
            <span>Sugestão do modelo</span>
            <span className="num">{numero(p.sugCobertura, 0)} {emCaixa ? "cx" : "un"}</span>
          </div>
        )}
      </div>

      {/* O protótipo tem aqui o botão "Enviar pra quem digita no Winthor", que
          não envia nada e nem se desabilita depois de clicado (§8). Não porto um botão que
          mente. A quantidade acima é simulação de verdade — muda a cobertura
          projetada ao vivo — e gravar pedido entra na Etapa 9, junto com a
          entidade "pedido", que hoje não existe no banco. */}
      <p className="mt-2.5 text-2xs" style={{ color: AMBAR }}>
        Simulação. Gravar e enviar pedido entra na Etapa 9, com a entidade de pedido.
      </p>
    </div>
  );
}
