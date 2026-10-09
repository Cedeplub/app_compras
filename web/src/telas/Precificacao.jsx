import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { AlertTriangle, Check, ChevronDown, Filter, Loader2, X } from "lucide-react";
import { api } from "../api/cliente.js";
import { useUltimaRequisicao } from "../ultimaRequisicao.js";
import { useAtualizacao } from "../contexto/atualizacao.jsx";
import { useEstadoPersistente } from "../estadoTela.js";
import { Carregando, Erro } from "../componentes/Basicos.jsx";
import CabecalhoOrdenavel, { useOrdenacaoUrl } from "../componentes/CabecalhoOrdenavel.jsx";
import FiltroEstoque from "../componentes/FiltroEstoque.jsx";
import FiltroPreco from "../componentes/FiltroPreco.jsx";
import FiltroRevenda from "../componentes/FiltroRevenda.jsx";
import AplicarEmLote, { aplicarNosMapas } from "../componentes/AplicarEmLote.jsx";
import FiltroUltimaEntrada, { AvisoSemEntrada } from "../componentes/FiltroUltimaEntrada.jsx";
import { precoJaAplicado, simular, TOLERANCIA_PRECO_IGUAL } from "../precificacao.js";
import { precoDeMargem, motivoMargemInvalida, motivoMKPInvalido, precoDeMKP, abaixoDoCusto,
         avaliarMargem, MARGEM_ALERTA, MARGEM_CRITICA, MARGEM_NEGATIVA } from "../precoEditavel.js";
import { data as fmtData, dataCompleta, moeda, numero, paraCampoPreco, parseNumeroPreco, quantidadeEstoque } from "../formato.js";
import { textoConfirmacaoLote } from "../lotePrecoStatus.js";

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
 *
 * Etapa 12 (PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §4.2): decidir o preço e criar
 * o LOTE de preços (o documento que vai para quem digita no Winthor) são um ato só.
 * Por isso não existe mais botão de gravar POR CÉLULA — só o botão do rodapé,
 * que grava tudo que foi digitado de uma vez e devolve o lote criado.
 */

const POR_PAGINA = 50;
// Espelha app/servicos/preco.py:LIMITE_LOTE_PRECO — o front parte o lote em
// pedaços deste tamanho ANTES de mandar, em vez de deixar o servidor recusar
// com 422 e o Diretor perder 200+ edições feitas na tela.
const LIMITE_LOTE_PRECO = 200;
const NAVY = "#375DA8";
const RED = "#DE434B";
const VERDE = "#15803D";
const CINZA = "#6B7280";

const FUNDO_AT = "#EFF6FF";
const FUNDO_AT_EDIT = "#DBEAFE";
const FUNDO_VAR = "#F0FDF4";
const FUNDO_VAR_EDIT = "#DCFCE7";
// Etapa 15, ponto 3: laranja-50/700 — mesma família das outras faixas
// (azul-50/100 do atacado, verde-50/100 do varejo), sem disputar com elas.
const FUNDO_EST = "#FFF7ED";
const LARANJA_EST = "#C2410C";

const CENARIOS = [
  { id: "st_valor", rotulo: "ST s/Valor" },
  { id: "oficial", rotulo: "Oficial (c/ redução)" },
  { id: "sem_red", rotulo: "Sem Redução" },
];

// `dir` de cada opção é a direção PADRÃO daquela coluna no servidor
// (`ORDENACOES` de `app/servicos/produto.py`) — o dropdown escolhe a MESMA
// direção que o primeiro clique no cabeçalho da coluna escolheria, para as
// duas UI nunca discordarem sobre o que "Margem" ordenado significa (§3.3).
const ORDENACOES = [
  { id: "margem", rotulo: "Margem — pior primeiro", dir: "asc" },
  { id: "preco", rotulo: "Maior preço atual", dir: "desc" },
  { id: "mkp", rotulo: "Menor MKP", dir: "asc" },
  { id: "descricao", rotulo: "Nome (A → Z)", dir: "asc" },
];

// Ajuste 2 do revisor (13/09) — mesmo caso de Pedidos.jsx: coluna que só
// tem `CabecalhoOrdenavel` (sem entrada em `ORDENACOES`) deixava o `<select>`
// abaixo sem `<option>` casada, e ele renderizava em branco. Rótulo
// sintético "Coluna: <nome>", com o mesmo nome do cabeçalho da tabela.
const ROTULO_COLUNA = {
  codigo: "Código",
  tributacao: "Tributação",
  custo: "Custo",
  valorNf: "Valor NF (c/ frete)",
  ultimaEntrada: "Últ. entrada",
  estoque: "Estoque",
  precoVarejo: "Varejo atual",
};

// Etapa 16 (PROMPT_ETAPA_16): "voltar" agora devolve a tela ANTERIOR de
// verdade (LotePrecoDetalhe/PedidoDetalhe usam `navegar(-1)`) — sem isto, o
// filtro escolhido antes de abrir um produto ou um lote se perdia ao
// remontar a Precificação vazia. `estadoTela.js` é o mecanismo genérico
// (molde `contexto/carrinho.jsx`); `pagina` entra junto — voltar para a
// página 7 e cair na 1 é perder o lugar tanto quanto perder o filtro.
// ⚠ `revenda: "S"` NASCE LIGADO, e é a única exceção no conjunto: os outros
// filtros nascem vazios ("tudo"). Item 1.17 do Diretor (09/10/2026) — "item
// que não é de venda na Precificação". Esta é a tela de DECIDIR PREÇO, e
// material que não se vende não tem preço a decidir. Medido: esconde 67 dos
// 4.553 ativos, então a contagem da tela passa de 4.553 para 4.486.
// O seletor "Revenda" deixa ver os escondidos sem mexer em código.
const FILTROS_PADRAO = {
  departamento: "", comprador: "", status: "Ativo", estoque: "", preco: "",
  revenda: "S",
  cenarioSel: "st_valor", busca: "", pagina: 1, dtUltEntDe: "", dtUltEntAte: "",
};

export default function Precificacao() {
  const { versaoDados } = useAtualizacao();
  const [opcoes, setOpcoes] = useState(null);
  const [parametros, setParametros] = useState(null);
  const [dados, setDados] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);

  const [filtros, setFiltros] = useEstadoPersistente(
    "app_compras_filtros_precificacao_v1", FILTROS_PADRAO);
  // Aceita valor direto OU função de atualização (`setX(prev => ...)`) — a
  // mesma dupla de formas que `useState` aceita, porque `Alertas.jsx` usa a
  // segunda para alternar tipo de alerta (lista de "ligados").
  const setCampo = (campo) => (v) => setFiltros((f) => ({
    ...f, [campo]: typeof v === "function" ? v(f[campo]) : v,
  }));
  const { departamento, comprador, status, estoque, preco, revenda, cenarioSel, busca,
          pagina, dtUltEntDe, dtUltEntAte } = filtros;
  const setDepartamento = setCampo("departamento");
  const setComprador = setCampo("comprador");
  const setStatus = setCampo("status");
  const setEstoque = setCampo("estoque");
  const setPreco = setCampo("preco");
  const setRevenda = setCampo("revenda");
  const setCenarioSel = setCampo("cenarioSel");
  const setBusca = setCampo("busca");
  const setPagina = setCampo("pagina");
  const setDtUltEntDe = setCampo("dtUltEntDe");
  const setDtUltEntAte = setCampo("dtUltEntAte");
  // Etapa 13, ponto 4: `ordenar`/`dir` vivem na URL (`?ordenar=...&dir=...`)
  // e são o MESMO estado que o cabeçalho clicável da tabela escreve — o
  // dropdown "Ordenar por" abaixo e o clique na coluna nunca divergem (§3.3).
  // Já sobrevive a "voltar" por conta própria (é a própria URL) — não entra
  // no `estadoTela.js` acima.
  const { ordenar, dir, aoOrdenar } = useOrdenacaoUrl("margem", "asc", setPagina);

  // Preços digitados, por código — {codigo: {valor, decidido}}. Não são
  // gravados até "Definir preços" no rodapé (§4.2 — não existe mais gravação
  // por célula).
  //
  // Sobrevivem a TROCAR DE PÁGINA e a TROCAR DE FILTRO, de propósito: nenhum
  // dos dois é um "cancelar" que a pessoa pediu, e apagar edição sem avisar é
  // o defeito do protótipo (§8) que este projeto corrige tela por tela. A
  // alternativa seria avisar antes de descartar a cada mudança de página ou
  // filtro — mas isso interromperia a navegação normal (trocar página é a
  // forma comum de revisar a lista inteira antes de definir o lote) com um
  // diálogo a cada clique. Sobreviver é a escolha certa aqui; só morrem
  // quando o SKU é de fato gravado (removido do mapa em `definirPrecos`) —
  // nunca por navegação.
  //
  // Etapa 16: também sobrevivem a SAIR DA TELA (voltar de `/produto/:codigo`
  // ou de `/precos-definidos/:id`, que agora usam `navegar(-1)`) — mas só o
  // `valor` DIGITADO é persistido (`precosATValor`/`precosVARValor`, abaixo),
  // nunca o `decidido`. `decidido` é um PREÇO vindo do JSON
  // (`precoDecidido*AV`) — guardá-lo em `sessionStorage` é exatamente o que
  // `carrinho.jsx` proíbe: ele envelhece no próximo `dbt run`, e comparar
  // "isto é alteração de verdade?" (`alteracoesLote`, abaixo) contra um
  // preço que já não existe mais decidiria errado, em silêncio. Por isso o
  // par completo `{valor, decidido}` continua vivendo só em `useState`
  // (como sempre viveu) — só a projeção `{codigo: valor}` vai para o
  // storage, e o `decidido` volta a ser preenchido a partir do JSON fresco
  // assim que o produto aparece numa página carregada (efeito logo abaixo).
  // ⚠ O `false` do terceiro argumento não é detalhe: estes dois são
  // DICIONÁRIOS ({códigoDoProduto: valor digitado}), não objetos de forma
  // fixa como os filtros acima. Com a mesclagem ligada, `lerStorage` percorre
  // as chaves do padrão — que aqui é `{}` — e devolveria sempre um mapa
  // vazio, descartando tudo o que foi digitado. Era esse o defeito: o filtro
  // voltava ao usar "Voltar" e o preço digitado, não.
  const [precosATValor, setPrecosATValor] = useEstadoPersistente(
    "app_compras_precos_at_precificacao_v1", {}, false);
  const [precosVARValor, setPrecosVARValor] = useEstadoPersistente(
    "app_compras_precos_var_precificacao_v1", {}, false);
  const [precosAT, setPrecosAT] = useState(() => Object.fromEntries(
    Object.entries(precosATValor).map(([codigo, valor]) => [codigo, { valor }])));
  const [precosVAR, setPrecosVAR] = useState(() => Object.fromEntries(
    Object.entries(precosVARValor).map(([codigo, valor]) => [codigo, { valor }])));

  // Grava no storage só a projeção {codigo: valor} — nunca o `decidido` que
  // mora junto no mesmo mapa em memória (comentário acima).
  useEffect(() => {
    setPrecosATValor(Object.fromEntries(
      Object.entries(precosAT).map(([codigo, entrada]) => [codigo, entrada.valor])));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [precosAT]);
  useEffect(() => {
    setPrecosVARValor(Object.fromEntries(
      Object.entries(precosVAR).map(([codigo, entrada]) => [codigo, entrada.valor])));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [precosVAR]);

  useEffect(() => {
    api.opcoes().then(setOpcoes).catch((e) => setErro(e.detalhe));
    api.parametros().then(setParametros).catch((e) => setErro(e.detalhe));
  }, []);

  // O RECORTE, sem paginação nem ordenação. Uma definição só, usada pela
  // listagem e pela aplicação em lote: duas cópias divergiriam no primeiro
  // filtro novo que alguém acrescentasse em só um dos lados, e aí o lote
  // aplicaria num conjunto diferente do que a tela mostra.
  const filtrosAtuais = useMemo(() => ({
    departamento: departamento || null,
    comprador: comprador || null,
    status: status === "Todos" ? null : status,
    estoque: estoque || null,
    preco: preco || null,
    revenda: revenda || null,
    busca: busca || null,
    cenarioMargem: cenarioSel,
    dtUltEntDe: dtUltEntDe || null,
    dtUltEntAte: dtUltEntAte || null,
  }), [departamento, comprador, status, estoque, preco, revenda, busca, cenarioSel,
       dtUltEntDe, dtUltEntAte]);

  const [loteAberto, setLoteAberto] = useState(false);

  // Ignora resposta atrasada — ver ultimaRequisicao.js. Clicar rápido
  // fazia a consulta antiga sobrescrever a nova (Diretor, 09/10/2026).
  const novaRequisicao = useUltimaRequisicao();

  const buscar = useCallback(async () => {
    const aindaVale = novaRequisicao();
    setCarregando(true);
    setErro(null);
    try {
      const resposta = await api.produtos({
        ...filtrosAtuais,
        ordenar, dir,
        pagina,
        porPagina: POR_PAGINA,
      });
      if (!aindaVale()) return;   // chegou atrasada: outra foi pedida depois
      setDados(resposta);
    } catch (e) {
      if (!aindaVale()) return;
      setErro(e.detalhe);
      setDados(null);
    } finally {
      // Guardado também: sem isto, a resposta atrasada apaga o "Carregando"
      // da consulta que ainda está em curso.
      if (aindaVale()) setCarregando(false);
    }
  }, [filtrosAtuais, ordenar, dir, pagina, versaoDados, novaRequisicao]);

  useEffect(() => {
    const t = setTimeout(buscar, busca ? 350 : 0);
    return () => clearTimeout(t);
  }, [buscar, busca]);

  const itens = dados?.itens ?? [];

  // Recompõe o `decidido` (o outro campo de `precosAT`/`precosVAR`) a partir
  // do JSON FRESCO recém-carregado — nunca do storage, que só guarda `valor`
  // (comentário acima, onde os dois mapas nascem). Roda toda vez que a lista
  // muda (troca de página/filtro, ou o remonte da tela ao "voltar"): para
  // cada entrada que ainda NÃO TEM `decidido` capturado — as restauradas do
  // storage, que nascem só com `{valor}` — e cujo produto está na página
  // recém-carregada, preenche com `p.precoDecididoAtacadoAV`/`VarejoAV` de
  // AGORA. Uma vez preenchido (mesmo que com `null`, "não há decisão"), a
  // entrada passa a se comportar EXATAMENTE como uma capturada ao digitar
  // (`setPrecoAT`/`setPrecoVAR`, na `Tabela` abaixo) — o snapshot não é
  // sobrescrito de novo, então `alteracoesLote` decide "isto é alteração de
  // verdade?" da mesma forma nos dois casos, só que a fonte do `decidido` é
  // sempre o JSON, nunca o `sessionStorage`.
  useEffect(() => {
    if (!itens.length) return;
    setPrecosAT((mapa) => {
      let mudou = false;
      const novo = { ...mapa };
      for (const p of itens) {
        const entrada = novo[p.codigo];
        if (entrada && !("decidido" in entrada)) {
          novo[p.codigo] = { ...entrada, decidido: p.precoDecididoAtacadoAV ?? null };
          mudou = true;
        }
      }
      return mudou ? novo : mapa;
    });
    setPrecosVAR((mapa) => {
      let mudou = false;
      const novo = { ...mapa };
      for (const p of itens) {
        const entrada = novo[p.codigo];
        if (entrada && !("decidido" in entrada)) {
          novo[p.codigo] = { ...entrada, decidido: p.precoDecididoVarejoAV ?? null };
          mudou = true;
        }
      }
      return mudou ? novo : mapa;
    });
  }, [itens]);

  // O que o "Gravar todos" de fato manda: só os campos que passariam no MESMO
  // teste do botão unitário (`CelulaEdicao.podeSalvar` — valor > 0 e diferente
  // do decidido em >= R$ 0,005). A tela lista 4.558 produtos que o Diretor só
  // está OLHANDO, cada um com uma sugestão calculada; um "gravar todos"
  // literal transformaria cada sugestão em decisão humana registrada, com
  // autor e histórico — a distinção entre "o sistema calculou" e "o Diretor
  // decidiu" é o que este projeto preserva desde o início (CONTEXTO §6 regra
  // 10).
  //
  // ⚠ Depende só de `precosAT`/`precosVAR`, NUNCA de `itens` (a página atual).
  // Antes dependia de `itens`, e trocar de página fazia a barra "esquecer" as
  // edições da página anterior em silêncio — exatamente o defeito de descartar
  // edição sem avisar que este projeto vem corrigindo tela por tela. O preço
  // DECIDIDO de cada SKU foi capturado no momento da digitação (acima, em
  // `Tabela`), então a regra "isto é alteração de verdade?" não precisa mais
  // da linha estar carregada.
  const alteracoesLote = useMemo(() => {
    const codigos = new Set([...Object.keys(precosAT), ...Object.keys(precosVAR)]);
    const lista = [];
    for (const codigo of codigos) {
      const entradaAT = precosAT[codigo];
      const entradaVAR = precosVAR[codigo];
      // `parseNumeroPreco` (formato.js) — o par de `paraCampoPreco`, que é como
      // este campo nasce preenchido. `Number.isFinite` descarta vazio (`null`,
      // campo apagado) e texto inválido (`NaN`) no mesmo teste; o parser
      // ingênuo (`Number(String(v).replace(",", "."))`) lia "1.234,56" como
      // "1.234.56" → NaN → 0 em silêncio — o defeito que apagava o botão
      // "Gravar" para todo produto com preço >= R$ 1.000 (254 SKUs ativos).
      const numAT = entradaAT ? parseNumeroPreco(entradaAT.valor) : null;
      const numVAR = entradaVAR ? parseNumeroPreco(entradaVAR.valor) : null;
      const item = { codigo: Number(codigo) };
      let tem = false;
      // Reverter o campo para o valor original (voltou a bater com o
      // `decidido` capturado na digitação) não é alteração — mesma regra do
      // botão unitário, só que contra o snapshot, não contra a linha ao vivo.
      if (entradaAT && Number.isFinite(numAT) && numAT > 0 && (entradaAT.decidido == null
          || Math.abs(numAT - entradaAT.decidido) >= TOLERANCIA_PRECO_IGUAL)) {
        item.precoAtacadoAV = numAT;
        tem = true;
      }
      if (entradaVAR && Number.isFinite(numVAR) && numVAR > 0 && (entradaVAR.decidido == null
          || Math.abs(numVAR - entradaVAR.decidido) >= TOLERANCIA_PRECO_IGUAL)) {
        item.precoVarejoAV = numVAR;
        tem = true;
      }
      // Marca de "abaixo do custo", para a confirmação poder avisar (item 1b
      // do Diretor, 09/10/2026). NÃO vai no payload: `definirPrecos` monta o
      // corpo com `codigo`/`precoAtacadoAV`/`precoVarejoAV` explicitamente, e
      // este campo é só da tela. `custo` é o do cenário no instante da
      // digitação — ver os setters em `Tabela`.
      if (tem) {
        item.abaixoDoCusto =
          (item.precoAtacadoAV != null && abaixoDoCusto(item.precoAtacadoAV, entradaAT?.custo))
          || (item.precoVarejoAV != null && abaixoDoCusto(item.precoVarejoAV, entradaVAR?.custo));
        // Margem mínima (item 4 do Diretor, 09/10/2026), pelo PIOR cenário.
        // `cenarios` e `pisCofins` entram no instantâneo pela mesma razão que
        // `custo` e `decidido`: a barra de lote tem de saber julgar o preço
        // depois de a pessoa trocar de página, e `itens` é só a página atual.
        // Snapshot antigo (sem `cenarios`) devolve nível 0 — não vira alarme
        // falso nem some com o aviso de custo, que é independente deste.
        const niveis = [
          item.precoAtacadoAV != null
            ? avaliarMargem(item.precoAtacadoAV, entradaAT?.cenarios,
                            { pisCofins: entradaAT?.pisCofins, comissao: parametros?.comissao },
                            parametros).nivel : 0,
          item.precoVarejoAV != null
            ? avaliarMargem(item.precoVarejoAV, entradaVAR?.cenarios,
                            { pisCofins: entradaVAR?.pisCofins, comissao: parametros?.comissao },
                            parametros).nivel : 0,
        ];
        item.nivelMargem = Math.max(...niveis);
        lista.push(item);
      }
    }
    return lista;
  }, [precosAT, precosVAR, parametros]);

  const qtdPrecosLote = alteracoesLote.reduce(
    (s, it) => s + (it.precoAtacadoAV != null ? 1 : 0) + (it.precoVarejoAV != null ? 1 : 0), 0);

  const qtdAbaixoDoCusto = alteracoesLote.filter((it) => it.abaixoDoCusto).length;
  // Contados por ITEM, pelo pior dos dois canais — a mesma leitura do diálogo
  // de aplicação em lote, para os dois números não discordarem na mesma tela.
  const qtdAbaixoDaMargem = alteracoesLote.filter((it) => it.nivelMargem >= MARGEM_ALERTA).length;
  const qtdMargemNegativa = alteracoesLote.filter((it) => it.nivelMargem === MARGEM_NEGATIVA).length;

  // Quantos SKUs do lote NÃO estão na página visível agora — para a barra não
  // deixar o Diretor clicar "Gravar" sem saber que está incluindo edições de
  // fora do que ele está olhando.
  const codigosNaPagina = useMemo(
    () => new Set(itens.map((p) => String(p.codigo))), [itens]);
  const foraDaPaginaLote = alteracoesLote.filter(
    (it) => !codigosNaPagina.has(String(it.codigo))).length;

  const [confirmarLote, setConfirmarLote] = useState(false);
  const [gravandoLote, setGravandoLote] = useState(false);
  const [erroLote, setErroLote] = useState(null);
  const [confirmacaoLote, setConfirmacaoLote] = useState(null);

  function limparCodigosGravados(mapa, codigosGravados) {
    const novo = { ...mapa };
    for (const c of codigosGravados) delete novo[c];
    return novo;
  }

  // Manda em pedaços de até LIMITE_LOTE_PRECO — nunca deixa o Diretor perder
  // 200+ edições feitas na tela por causa de um 4xx do servidor. TODOS os
  // pedaços vão para o MESMO lote (PROMPT_ETAPA_12 §4.3): o primeiro POST não
  // leva `idLote` e o servidor cria o documento; os seguintes mandam o `id`
  // que voltou e ACRESCENTAM. Partir em N lotes produziria N documentos em
  // silêncio para quem digita no Winthor — é o defeito que esta etapa existe para matar.
  // Cada pedaço que grava com sucesso é removido de `precosAT`/`precosVAR` NA
  // HORA — se uma falha interromper a sequência no meio, os pedaços já
  // gravados não aparecem mais como pendentes, e só o que ainda não foi
  // enviado continua na tela para tentar de novo.
  async function definirPrecos() {
    setGravandoLote(true);
    setErroLote(null);
    const totalPrecosAlvo = qtdPrecosLote;
    let idLote = null;
    // Só a PRIMEIRA chamada da sequência vai sem `idLote` — é ela quem decide,
    // no servidor, entre criar um lote novo ou reaproveitar o Rascunho aberto
    // do usuário (§4.3). As fatias seguintes já mandam o `id` devolvido e
    // ACRESCENTAM a ele — não é uma segunda decisão de "criar ou reaproveitar",
    // por isso só a resposta da primeira fatia importa para o texto final.
    let loteReaproveitado = null;
    try {
      for (let i = 0; i < alteracoesLote.length; i += LIMITE_LOTE_PRECO) {
        const fatia = alteracoesLote.slice(i, i + LIMITE_LOTE_PRECO);
        const r = await api.criarOuAcrescentarLotePreco(fatia, idLote);
        idLote = r.id;
        if (i === 0) loteReaproveitado = r.loteReaproveitado ?? null;
        const codigosGravados = fatia.map((f) => String(f.codigo));
        setPrecosAT((a) => limparCodigosGravados(a, codigosGravados));
        setPrecosVAR((a) => limparCodigosGravados(a, codigosGravados));
      }
      setConfirmarLote(false);
      await buscar();
      setConfirmacaoLote({
        texto: textoConfirmacaoLote(totalPrecosAlvo, idLote, loteReaproveitado),
        idLote,
      });
    } catch (e) {
      // Falha parcial: os chunks já gravados saíram dos mapas (acima), mas a
      // tabela ainda mostra o `decidido` de ANTES da gravação. Sem rebuscar, o
      // Diretor que redigitasse naquela linha teria o snapshot velho como
      // referência, e o lote trataria a linha já gravada como alteração de
      // novo. `buscar()` também no erro, não só no sucesso.
      await buscar();
      setErroLote(e.status === 404 ? "Só a diretoria pode definir preço." : e.detalhe);
    } finally {
      setGravandoLote(false);
    }
  }

  return (
    <div className="px-4 pb-28 pt-3 md:px-6 md:pt-4">
      {confirmacaoLote && (
        <div className="mb-3 flex items-center justify-between gap-3 rounded-lg px-4 py-2.5"
             style={{ background: `${VERDE}12` }}>
          <span className="flex items-center gap-1.5 text-sm font-medium" style={{ color: VERDE }}>
            <Check size={14} aria-hidden="true" /> {confirmacaoLote.texto}
          </span>
          <div className="flex items-center gap-3">
            {/* A faixa de sucesso leva ao lote por LINK, não só texto — é o
                caminho até quem digita no Winthor que faltava (Diretor,
                09/09: "não tem muita serventia"). */}
            <Link to={`/precos-definidos/${confirmacaoLote.idLote}`}
                  className="whitespace-nowrap text-sm font-semibold underline"
                  style={{ color: VERDE }}>
              Ver lote em Preços Definidos
            </Link>
            <button type="button" onClick={() => setConfirmacaoLote(null)}
                    aria-label="Dispensar aviso" className="text-gray-400">
              <X size={14} aria-hidden="true" />
            </button>
          </div>
        </div>
      )}

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

        <FiltroEstoque valor={estoque} aoTrocar={(v) => { setEstoque(v); setPagina(1); }} />
        <FiltroPreco valor={preco} aoTrocar={(v) => { setPreco(v); setPagina(1); }} />
        <FiltroRevenda valor={revenda} aoTrocar={(v) => { setRevenda(v); setPagina(1); }} />

        {/* Fica JUNTO dos filtros, e não na barra de gravação, porque o que
            ele aplica é "o filtro atual" — o botão ao lado do recorte diz
            isso melhor do que qualquer rótulo. Item 1c do Diretor. */}
        <Campo rotulo="Em lote" largura="w-auto">
          <button type="button" onClick={() => setLoteAberto(true)}
                  disabled={!parametros}
                  title="Aplicar uma margem ou um MKP a todos os produtos do filtro atual, em todas as páginas."
                  className="whitespace-nowrap rounded-lg border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 disabled:opacity-40">
            Margem / MKP…
          </button>
        </Campo>

        <Campo rotulo="Departamento" largura="w-40">
          <Select valor={departamento} vazio="Todos" opcoes={opcoes?.departamentos ?? []}
                  aoTrocar={(v) => { setDepartamento(v); setPagina(1); }} />
        </Campo>
        {/* O backend já aceita `comprador` (GET /api/produtos) e `GET
            /api/opcoes` já devolve a lista — só faltava o campo aqui. Cabe na
            mesma fileira dos dois selects mortos de Seção/Linha, que ainda
            aguardam cadastro no Winthor. */}
        <Campo rotulo="Comprador" largura="w-40">
          <Select valor={comprador} vazio="Todos" opcoes={opcoes?.compradores ?? []}
                  aoTrocar={(v) => { setComprador(v); setPagina(1); }} />
        </Campo>
        <Campo rotulo="Seção" largura="w-40"><SelectVazio /></Campo>
        <Campo rotulo="Linha" largura="w-40"><SelectVazio /></Campo>

        <Campo rotulo="Cenário de margem" largura="w-52">
          <Select valor={cenarioSel} aoTrocar={(v) => { setCenarioSel(v); setPagina(1); }}
                  opcoes={CENARIOS.map((c) => c.id)}
                  rotulos={Object.fromEntries(CENARIOS.map((c) => [c.id, c.rotulo]))} />
        </Campo>
        <Campo rotulo="Ordenar por" largura="w-52">
          {/* Mesmo estado do cabeçalho clicável da tabela (`ordenar`/`dir`,
              `useOrdenacaoUrl` acima) — escolher aqui tira a seta de
              qualquer coluna que estivesse ativa antes, e vice-versa (§3.3).
              Quando a ordem ativa veio de uma coluna fora desta lista fixa
              (ex.: "Custo"), entra como opção sintética "Coluna: X" — sem
              isso o `<select>` ficava sem `<option>` casada (ajuste 2). */}
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

        <FiltroUltimaEntrada referencia={parametros?.data_referencia}
                             dtUltEntDe={dtUltEntDe} setDtUltEntDe={(v) => { setDtUltEntDe(v); setPagina(1); }}
                             dtUltEntAte={dtUltEntAte} setDtUltEntAte={(v) => { setDtUltEntAte(v); setPagina(1); }} />

        <div className="num ml-auto text-xs text-gray-500">
          {numero(dados?.total)} produto(s)
        </div>
      </div>
      {(dtUltEntDe || dtUltEntAte) && <AvisoSemEntrada />}

      <div className="mt-4">
        {carregando && <Carregando />}
        {!carregando && erro && <Erro mensagem={erro} aoTentarDeNovo={buscar} />}
        {!carregando && !erro && itens.length === 0 && (
          <div className="py-8 text-center text-sm text-gray-400">Nada nesse filtro.</div>
        )}
        {!carregando && !erro && itens.length > 0 && parametros && (
          <Tabela itens={itens} cenarioSel={cenarioSel} parametros={parametros}
                  ordenar={ordenar} dir={dir} aoOrdenar={aoOrdenar}
                  precosAT={precosAT} setPrecosAT={setPrecosAT}
                  precosVAR={precosVAR} setPrecosVAR={setPrecosVAR} />
        )}
      </div>

      {dados && dados.totalPaginas > 1 && (
        <Paginacao pagina={dados.pagina} total={dados.totalPaginas} aoTrocar={setPagina} />
      )}

      <p className="mt-2 text-2xs text-gray-400">
        O regime fiscal de cada produto sai de <code>dim_tributacao</code>, validado item a
        item contra a planilha. Custo e alíquota mudam com o cenário; o preço praticado hoje, não.
      </p>

      {alteracoesLote.length > 0 && (
        <BarraGravacaoLote qtdSkus={alteracoesLote.length} qtdPrecos={qtdPrecosLote}
                            foraDaPagina={foraDaPaginaLote}
                            aoAbrirConfirmacao={() => setConfirmarLote(true)} />
      )}
      {loteAberto && (
        <AplicarEmLote
          filtros={filtrosAtuais}
          parametros={parametros}
          aoFechar={() => setLoteAberto(false)}
          aoAplicar={(linhas, canal) => {
            aplicarNosMapas(linhas, canal, setPrecosAT, setPrecosVAR);
            setLoteAberto(false);
          }} />
      )}
      {confirmarLote && (
        <ConfirmarDefinirPrecos qtdSkus={alteracoesLote.length} qtdPrecos={qtdPrecosLote}
                                 abaixoDoCusto={qtdAbaixoDoCusto}
                                 abaixoDaMargem={qtdAbaixoDaMargem}
                                 margemNegativa={qtdMargemNegativa}
                                 margemAlertaMin={parametros?.margem_alerta_min}
                                 foraDaPagina={foraDaPaginaLote}
                                 gravando={gravandoLote} erro={erroLote}
                                 aoCancelar={() => { setConfirmarLote(false); setErroLote(null); }}
                                 aoConfirmar={definirPrecos} />
      )}
    </div>
  );
}

/* ------------------------------------------------------- gravação em lote --- */

function BarraGravacaoLote({ qtdSkus, qtdPrecos, foraDaPagina, aoAbrirConfirmacao }) {
  return (
    <div className="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white px-4 py-3 shadow-lg md:px-6">
      <div className="mx-auto flex max-w-app flex-wrap items-center gap-3">
        <div className="text-2xs text-gray-500">
          {numero(qtdSkus)} produto(s) com preço alterado, ainda não gravado(s)
          {foraDaPagina > 0 && (
            // O lote enxerga o mapa inteiro, não só o filtro/página atual — mas o
            // Diretor só está OLHANDO o recorte atual, e clicar "Gravar" sem saber
            // que inclui edição de fora dele é o mesmo descarte silencioso ao
            // contrário: ele acha que está gravando só o que vê. Dizer "outra
            // página" seria falso quando o que mudou foi o FILTRO (departamento,
            // busca, cenário) — o SKU editado não está em página nenhuma do
            // recorte atual, está fora do filtro. Por isso "fora do filtro atual",
            // não "em outra página".
            <span style={{ color: "#B98A2E" }}>
              {" "}· {numero(foraDaPagina)} fora do filtro atual
            </span>
          )}
        </div>
        <button type="button" onClick={aoAbrirConfirmacao}
                className="ml-auto rounded-lg px-4 py-2 text-sm font-semibold text-white"
                style={{ background: NAVY }}>
          Definir {numero(qtdPrecos)} preço{qtdPrecos > 1 ? "s" : ""}
          {foraDaPagina > 0 && ` (${numero(foraDaPagina)} fora do filtro atual)`}
        </button>
      </div>
      <p className="mx-auto mt-1 max-w-app text-2xs text-gray-400">
        {/* Etapa 12 §4.2: não existe mais botão por célula — decidir o preço e
            criar o lote em Preços Definidos são um ato só, feito aqui. */}
        Isto grava a decisão de cada célula alterada E cria (ou acrescenta a) um lote em
        Rascunho na área Preços Definidos, pronto para o arquivo da rotina 201.
      </p>
    </div>
  );
}

/* Modelo: `ConfirmarExclusao` de PedidosSalvos.jsx:219. Preço de venda real
 * exige confirmação explícita, com a contagem, antes de gravar qualquer coisa
 * — o lote não pode ser mais fácil de disparar por acidente do que um clique
 * por SKU seria. */
function ConfirmarDefinirPrecos({ qtdSkus, qtdPrecos, foraDaPagina, abaixoDoCusto = 0,
                                  abaixoDaMargem = 0, margemNegativa = 0, margemAlertaMin,
                                  gravando, erro, aoCancelar, aoConfirmar }) {
  const emLotes = qtdSkus > LIMITE_LOTE_PRECO;
  // Vender abaixo do custo pode ser decisão legítima (queima de estoque), mas
  // tem de ser DECISÃO. Com algum item nessa situação, o diálogo exige um
  // segundo gesto: a caixa marcada libera o botão. Pedido do Diretor em
  // 09/10/2026 — "destacar em vermelho e pedir confirmação ao definir".
  //
  // A MARGEM NEGATIVA entra na MESMA caixa, e não numa segunda (item 4 do
  // Diretor: "vermelho e pede confirmação ao definir, igual a abaixo do
  // custo"). Duas caixas pedindo o mesmo gesto viram duas caixas marcadas sem
  // leitura — e os dois conjuntos se sobrepõem bastante, já que todo preço
  // abaixo do custo tem margem negativa, mas não o contrário.
  const [cienteDoCusto, setCienteDoCusto] = useState(false);
  const exigeCiencia = abaixoDoCusto > 0 || margemNegativa > 0;
  const travado = exigeCiencia && !cienteDoCusto;
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 px-4"
         role="dialog" aria-modal="true" aria-labelledby="titulo-definir-precos">
      <div className="w-full max-w-sm rounded-xl bg-white p-5 shadow-lg">
        <div className="flex items-start gap-2">
          <AlertTriangle size={18} className="mt-0.5 shrink-0" style={{ color: NAVY }} aria-hidden="true" />
          <div>
            <h2 id="titulo-definir-precos" className="font-semibold text-gray-900">
              Definir {qtdPrecos} preço{qtdPrecos > 1 ? "s" : ""}?
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              {qtdSkus} produto(s), {qtdPrecos} preço{qtdPrecos > 1 ? "s" : ""}. Isto grava a
              decisão (com histórico de quem gravou) e cria um lote em Rascunho na área Preços
              Definidos — o documento que vai virar arquivo para importação na rotina 201 do
              Winthor. O preço a prazo de cada um é recalculado a partir do à vista.
            </p>
            <p className="mt-2 text-xs text-gray-500">
              Só o que você alterou — o resto da lista continua como está.
              {/* O lote vale para TODO SKU editado, mesmo que o filtro tenha
                  mudado desde a edição — é por isso que este aviso fala em "fora
                  do filtro atual", não em "outra página": trocar de departamento,
                  busca ou cenário não limpa os mapas de edição (decisão
                  deliberada), então o SKU pode não estar em página nenhuma do
                  recorte de agora. */}
              {foraDaPagina > 0 && ` ${numero(foraDaPagina)} desses produto(s) está(ão) fora do filtro atual.`}
              {/* Acima de LIMITE_LOTE_PRECO o front parte em pedaços, mas TODOS
                  vão para o MESMO lote — nunca um lote por pedaço (§4.3). */}
              {emLotes && ` Como passa de ${LIMITE_LOTE_PRECO} itens, será enviado em pedaços, todos para o MESMO lote.`}
            </p>
            {/* Amarelo: avisa, não trava. Margem abaixo do mínimo é um
                número que se quer VER antes de gravar, mas segurar o botão
                por causa dele transformaria o aviso em obstáculo diário —
                o Diretor pediu confirmação só abaixo de zero. Conta só os
                que NÃO estão no bloco vermelho, para os dois números somarem
                em vez de se sobreporem. */}
            {abaixoDaMargem - margemNegativa > 0 && (
              <p className="mt-3 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800">
                <span className="font-semibold">
                  {numero(abaixoDaMargem - margemNegativa)} produto(s) abaixo da margem mínima
                  {margemAlertaMin != null && ` (${pct(margemAlertaMin, 0)})`}
                </span>{" "}
                no pior cenário. Grava assim mesmo.
              </p>
            )}
            {exigeCiencia && (
              <label className="mt-3 flex items-start gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2">
                <input type="checkbox" checked={cienteDoCusto} className="mt-0.5"
                       onChange={(e) => setCienteDoCusto(e.target.checked)} />
                <span className="text-xs text-red-700">
                  {abaixoDoCusto > 0 && (
                    <span className="font-semibold">
                      {numero(abaixoDoCusto)} produto(s) com preço ABAIXO DO CUSTO.{" "}
                    </span>
                  )}
                  {margemNegativa > 0 && (
                    <span className="font-semibold">
                      {numero(margemNegativa)} com MARGEM NEGATIVA no pior cenário.{" "}
                    </span>
                  )}
                  Confirmo que é intencional.
                </span>
              </label>
            )}
            {erro && <p role="alert" className="mt-2 text-xs font-medium" style={{ color: RED }}>{erro}</p>}
          </div>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button type="button" onClick={aoCancelar} disabled={gravando}
                  className="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 disabled:opacity-50">
            Cancelar
          </button>
          <button type="button" onClick={aoConfirmar} disabled={gravando || travado}
                  title={travado ? "Marque a caixa acima para confirmar os preços abaixo do custo ou de margem negativa." : undefined}
                  className="flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-50"
                  style={{ background: NAVY }}>
            {gravando && <Loader2 size={13} className="animate-spin" aria-hidden="true" />}
            {gravando ? "Definindo…" : "Definir preços"}
          </button>
        </div>
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

function Tabela({ itens, cenarioSel, parametros, ordenar, dir, aoOrdenar, precosAT, setPrecosAT,
                  precosVAR, setPrecosVAR }) {
  // `coluna`/`padrao` de cada `CabecalhoOrdenavel` abaixo têm que espelhar
  // `ORDENACOES` de `app/servicos/produto.py` (§3.2/§3.4) — "custo" depende do
  // CENÁRIO escolhido (mesma coluna que `_ordem` resolve no servidor), por
  // isso ordenar por Custo enquanto o cenário muda pode reordenar a lista sem
  // a pessoa tocar em nada — é o comportamento correto, não um bug: a tela já
  // avisa embaixo que "custo, margem e MKP mudam com o cenário".
  //
  // Colunas SEM `CabecalhoOrdenavel` (Sugerido AT/VAR, Margem VAR, MKP VAR,
  // Novo preço AT/VAR): o whitelist do servidor não tem entrada para elas —
  // Margem/MKP no servidor só resolvem o cenário do ATACADO
  // (`contrato.COLUNA_MARGEM` fixa "atacado" em `_ordem`), e não existe coluna
  // de "sugerido" nem os campos de edição são coisa que se ordena (§3.1: uma
  // coluna que não tem como ordenar no servidor não fica clicável).
  const props = { ordenar, dir, aoOrdenar };
  return (
    <div className="overflow-x-auto rounded-lg border border-gray-200">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 text-2xs uppercase tracking-wide text-gray-500">
            <CabecalhoOrdenavel {...props} coluna="codigo" padrao="asc">Código</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="descricao" padrao="asc" className="min-w-[220px]">Produto</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="tributacao" padrao="asc" align="center">Tributação</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="custo" padrao="desc" align="center">Custo</CabecalhoOrdenavel>
            {/* Contexto de compra ao lado do custo — mesmo campo que a tela de
                Pedidos já recebe (`ultimaEntrada`/`qtdUltimaEntrada` de
                `contrato.produto()`), só que aqui a Precificação não desenhava
                (item 2 do Diretor, 08/09). Zero mudança de API: o JSON já
                trazia os dois campos.
                Mostra `valorEntradaUnitario` (VL_ENT_UNIT/PCEST.VALORULTENT),
                COM o frete embutido quando há — pedido do Diretor (25/09): na
                Precificação o custo do frete faz parte da decisão de preço.
                Continua ordenando por `p.vl_ent_unit` (`produto.py:ORDENACOES`),
                agora o MESMO número que a coluna exibe — antes a coluna
                reconstruía uma estimativa (`valorAntesDoCredito` sobre o
                custo) que podia divergir do que o clique ordenava. */}
            <CabecalhoOrdenavel {...props} coluna="valorNf" padrao="desc" align="center">Valor NF (c/ frete)</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="ultimaEntrada" padrao="desc" align="center">Últ. entrada</CabecalhoOrdenavel>
            {/* Etapa 15, ponto 3: EST_DISP já viaja no JSON desde a Etapa 7 —
                zero mudança de API, só a tela que não desenhava. Laranja
                para não competir com as faixas de atacado (azul) e varejo
                (verde) que organizam a leitura das 15 colunas. */}
            <CabecalhoOrdenavel {...props} coluna="estoque" padrao="desc" align="center" style={{ background: FUNDO_EST }}>Estoque</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="preco" padrao="desc" align="center" style={{ background: FUNDO_AT }}>Atacado atual</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="mkp" padrao="asc" align="center" style={{ background: FUNDO_AT }}>MKP AT</CabecalhoOrdenavel>
            <CabecalhoOrdenavel {...props} coluna="margem" padrao="asc" align="center" style={{ background: FUNDO_AT }}>Margem AT</CabecalhoOrdenavel>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT }}>Sugerido AT</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_AT_EDIT }}>Novo preço AT<br /><span className="normal-case opacity-70">(à vista → a prazo)</span></th>
            <CabecalhoOrdenavel {...props} coluna="precoVarejo" padrao="desc" align="center" style={{ background: FUNDO_VAR }}>Varejo atual</CabecalhoOrdenavel>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>MKP VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>Margem VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR }}>Sugerido VAR</th>
            <th className="px-2 py-2 text-center font-medium" style={{ background: FUNDO_VAR_EDIT }}>Novo preço VAR<br /><span className="normal-case opacity-70">(à vista → a prazo)</span></th>
          </tr>
        </thead>
        <tbody>
          {itens.map((p) => (
            <Linha key={p.codigo} p={p} cenarioSel={cenarioSel} parametros={parametros}
                   // O campo nasce com o preço já DECIDIDO (editável) quando o mapa
                   // ainda não tem entrada para o SKU E o preço decidido AINDA NÃO
                   // foi aplicado no Winthor — é a correção do item 2 do Diretor
                   // ("nem tem opção de editar"). Isto NÃO viola a regra 10 do
                   // CONTEXTO: `p.precoDecididoAtacadoAV` vem de `APP_DECISAO_PRECO`,
                   // ou seja, é o número que uma PESSOA decidiu — o oposto de nascer
                   // com `PV_SUG_*` (a sugestão do modelo), que continua proibido.
                   // Assim que o Diretor digita, o mapa ganha entrada própria
                   // (abaixo) e passa a mandar nele.
                   //
                   // Etapa 15, ponto 2: quando o preço decidido JÁ FOI APLICADO no
                   // Winthor (`precoJaAplicado`), o campo "reseta" — nasce vazio,
                   // como se não houvesse decisão pendente, porque não há mais
                   // decisão pendente (o decidido virou o vigente). A linha de apoio
                   // de `CelulaEdicao`, abaixo, passa a mostrar a data da alteração
                   // no Winthor em vez do valor decidido.
                   /* `paraCampoPreco`, não `numero()`: o campo precisa nascer no
                      mesmo formato que `parseNumeroPreco` lê de volta sem
                      ponto de milhar (formato.js) — `numero(1234, 2)` produz
                      "1.234,00", que o parser ingênuo (agora removido) lia
                      como "1.234.00" → NaN. */
                   precoAT={precosAT[p.codigo]?.valor
                     ?? (p.precoDecididoAtacadoAV != null && !precoJaAplicado(p.pvAtacado, p.precoDecididoAtacadoAV)
                          ? paraCampoPreco(p.precoDecididoAtacadoAV) : undefined)}
                   precoVAR={precosVAR[p.codigo]?.valor
                     ?? (p.precoDecididoVarejoAV != null && !precoJaAplicado(p.pvVarejo, p.precoDecididoVarejoAV)
                          ? paraCampoPreco(p.precoDecididoVarejoAV) : undefined)}
                   // A captura acontece AQUI, na digitação — não na hora de gravar em
                   // lote. Guardamos junto do valor digitado o preço DECIDIDO daquele
                   // SKU neste instante: é o que permite ao lote decidir "isto é
                   // alteração de verdade?" sem depender da página estar carregada
                   // (Diretor, 08/09/2026 — o lote sumia ao trocar de página porque
                   // dependia de `itens`, que é só a página atual).
                   // `custo` entra no instantâneo pelo MESMO motivo de
                   // `decidido`: o lote precisa saber se o preço ficou abaixo
                   // do custo mesmo depois de a pessoa trocar de página, e
                   // `itens` é só a página atual. É o custo DO CENÁRIO no
                   // instante da digitação — quem digitou viu aquele custo.
                   // `cenarios` e `pisCofins` entram no instantâneo pelo mesmo
                   // motivo que `custo`: o aviso de margem mínima (item 4 do
                   // Diretor) é julgado pelo PIOR cenário, e a barra de lote
                   // precisa refazer esse julgamento depois de a pessoa trocar
                   // de página. `cenarios` é a lista INTEIRA da praça, não o
                   // cenário escolhido — é ela que define qual é o pior.
                   setPrecoAT={(v, custo) => setPrecosAT((a) => ({
                     ...a, [p.codigo]: { valor: v, decidido: p.precoDecididoAtacadoAV, custo,
                                         cenarios: p.cenariosAtacado, pisCofins: p.pisCofinsEfetivo },
                   }))}
                   setPrecoVAR={(v, custo) => setPrecosVAR((a) => ({
                     ...a, [p.codigo]: { valor: v, decidido: p.precoDecididoVarejoAV, custo,
                                         cenarios: p.cenariosVarejo, pisCofins: p.pisCofinsEfetivo },
                   }))} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Linha({ p, cenarioSel, parametros, precoAT, precoVAR, setPrecoAT, setPrecoVAR }) {
  const at = simular({ produto: p, cenarios: p.cenariosAtacado, cenarioSel,
                       precoAtual: p.pvAtacado, precoDigitado: precoAT,
                       fatorPrazo: parametros.fator_prazo_atacado, parametros });
  const vr = simular({ produto: p, cenarios: p.cenariosVarejo, cenarioSel,
                       precoAtual: p.pvVarejo, precoDigitado: precoVAR,
                       fatorPrazo: parametros.fator_prazo_varejo, parametros });

  // Base de margem/MKP dos dois campos novos (item 1) — a MESMA `base` que
  // `simular` já monta por dentro para `calcMargem`, só exposta aqui porque
  // `CelulaEdicao` precisa dela para a conta INVERSA (`precoDeMargem`). Lida
  // de `at.cenario`/`vr.cenario`, nunca re-resolvida (§3.4 do prompt): duas
  // resoluções de cenário é como o protótipo acaba com uma alíquota na
  // sugestão e outra na margem (precificacao.js:52-57).
  const baseAT = { pisCofins: p.pisCofinsEfetivo, comissao: parametros.comissao, icmsEf: at.cenario?.icmsEf };
  const baseVAR = { pisCofins: p.pisCofinsEfetivo, comissao: parametros.comissao, icmsEf: vr.cenario?.icmsEf };

  // Custo ocupa UMA linha quando a última entrada e o custo do cenário
  // coincidem, e DUAS quando divergem. É do protótipo, e é bom: a segunda
  // linha aparece só quando há de fato duas coisas a dizer.
  // Valor NF NÃO segue mais essa divisão (25/09): passou a mostrar
  // `valorEntradaUnitario` direto — um valor só, que não depende do cenário
  // fiscal escolhido na tela — em vez de reconstruir uma estimativa
  // (`valorAntesDoCredito`) a partir de dois custos diferentes.
  const custoIgual = p.custoUltimaEntrada != null && at.custo != null
    && Math.abs(p.custoUltimaEntrada - at.custo) < 0.01;
  // Desde 08/10/2026 a coluna Valor também tem o par "últ / ger", por decisão
  // do Diretor — ver o comentário na célula, abaixo. Mesma regra de colapso do
  // Custo: UMA linha quando os dois lados coincidem (Normal e ST Recolhido sem
  // Ingrax, a maioria dos SKUs).
  const valorIgual = p.valorEntradaUnitario != null && p.valorGerencial != null
    && Math.abs(p.valorEntradaUnitario - p.valorGerencial) < 0.01;

  return (
    <tr className="border-t border-gray-100 hover:bg-gray-50">
      <td className="num px-2 py-2 text-gray-500">{p.codigo}</td>
      <td className="px-3 py-2">
        <Link to={`/produto/${p.codigo}`}
              className="block w-full text-left hover:underline">
          <div className="whitespace-nowrap font-medium text-gray-800">{p.nome}</div>
          <div className="num text-2xs text-gray-400">{p.departamento}</div>
        </Link>
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
      {/* "últ" = `valorEntradaUnitario` (VL_ENT_UNIT, com frete embutido quando
          há), o valor REAL da nota. "ger" = `valorGerencial`
          (COMPRAS_PRODUTO_CONTEXTO.VALOR_TOT_GERENCIAL): nota + ICMS-ST bruto
          + adicional de imagem bruto, ou seja, quanto o produto custou para
          entrar SEM descontar crédito nenhum.

          ⚠ Diferença em relação à coluna Custo à esquerda: lá o "ger" muda com
          `cenarioSel` (a base do ICMS-ST é o Valor em "ST s/Valor" e o Custo
          em "Oficial"/"Sem Redução"); aqui NÃO muda — o Diretor conferiu os 3
          cenários em 8 produtos e o Valor é igual nos três. Por isso esta
          célula lê `p.valorGerencial` e nunca `at.*`.

          ⚠ Não é o "Valor NF projetado" retirado em 25/09/2026: aquele
          reconstruía o valor PARA TRÁS a partir do custo e divergia da nota em
          até 34%. Este soma para frente, a partir da nota. */}
      <td className="num px-2 py-1.5 text-center text-2xs text-gray-600" style={{ minWidth: 96 }}>
        {p.valorEntradaUnitario == null ? "—" : valorIgual ? moeda(p.valorEntradaUnitario) : (
          <>
            <div>últ {moeda(p.valorEntradaUnitario)}</div>
            <div className="text-gray-400">ger {moeda(p.valorGerencial)}</div>
          </>
        )}
      </td>

      {/* Formatação idêntica a `Pedidos.jsx` (dd/mm em cima, quantidade embaixo
          em cinza mais claro) — mesmo contrato, mesma leitura nas duas telas.

          ── Item 1.16 do Diretor, 09/10/2026 ────────────────────────────────
          "Bonificação como última entrada na Precificação: 8817 com R$ 227,87."
          O WinThor grava em PCEST qualquer entrada: no 8817 a única que existe
          é um RETORNO DE REMESSA de 1 unidade a R$ 227,87, num produto cujo
          atacado é R$ 72,40. Em 423 dos 4.553 ativos a última entrada não é
          compra.

          Os NÚMEROS não mudam — custo, margem e preço sugerido continuam
          saindo do que o WinThor gravou (decisão de 09/10/2026: "só a tela").
          O que muda é a célula DIZER quando a entrada não foi compra, e
          oferecer a data da última compra quando ela existe.

          ⚠ `dtUltCompra` é nulo em 185 dos 423 — produtos que nunca tiveram
          compra na filial de estoque, e o 8817 é um deles. Nesses a célula diz
          "sem compra", que é a verdade, em vez de deixar a data do retorno
          passar por data de compra. */}
      <td className="num px-2 py-2 text-center text-2xs text-gray-500">
        {dataCompleta(p.ultimaEntrada)}
        {p.qtdUltimaEntrada != null && <div className="text-gray-400">{numero(p.qtdUltimaEntrada, 0)}</div>}
        {p.ultEntradaECompra === false && (
          <div className="mt-0.5 font-semibold text-amber-700"
               title={p.dtUltCompra
                 ? `Esta entrada não é compra (retorno, transferência ou bonificação). Última compra: ${dataCompleta(p.dtUltCompra)}.`
                 : "Esta entrada não é compra (retorno, transferência ou bonificação), e este produto não tem nenhuma compra registrada na filial de estoque."}>
            {p.dtUltCompra
              ? <>não é compra<div className="font-normal">compra {dataCompleta(p.dtUltCompra)}</div></>
              : <>não é compra<div className="font-normal">sem compra</div></>}
          </div>
        )}
      </td>

      {/* ⚠ EST_DISP já vem dividido por FATOR_EXIBICAO no dbt
          (int_produto_demanda) — não dividir de novo, erraria por 12 ou 24
          em 223 SKUs de departamento MASTER. */}
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: FUNDO_EST, color: LARANJA_EST }}>
        {quantidadeEstoque(p.estDisp)}
      </td>

      <td className="num px-2 py-2 text-center" style={{ background: FUNDO_AT }}>{moeda(p.pvAtacado)}</td>
      <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_AT }}>{mult(at.mkpAtual)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: FUNDO_AT,
                   color: at.margemAtual != null && p.margemAlvo != null && at.margemAtual < p.margemAlvo ? RED : NAVY }}>
        {pct(at.margemAtual)}
      </td>
      <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_AT }}>{moeda(at.sugerido)}</td>
      <CelulaEdicao fundo={FUNDO_AT_EDIT} sim={at} base={baseAT} cenarioSel={cenarioSel}
                    cenarios={p.cenariosAtacado} parametros={parametros}
                    valor={precoAT} aoTrocar={setPrecoAT}
                    rotulo={`Novo preço de atacado do produto ${p.codigo}`}
                    decidido={p.precoDecididoAtacadoAV}
                    aplicado={precoJaAplicado(p.pvAtacado, p.precoDecididoAtacadoAV)}
                    dataDecisao={p.precoDecididoEm} dataAplicado={p.precoAlteradoEmAtacado} />

      <td className="num px-2 py-2 text-center" style={{ background: FUNDO_VAR }}>{moeda(p.pvVarejo)}</td>
      <td className="num px-2 py-2 text-center text-gray-600" style={{ background: FUNDO_VAR }}>{mult(vr.mkpAtual)}</td>
      <td className="num px-2 py-2 text-center font-semibold"
          style={{ background: FUNDO_VAR,
                   color: vr.margemAtual != null && p.margemAlvoVarejo != null && vr.margemAtual < p.margemAlvoVarejo ? RED : NAVY }}>
        {pct(vr.margemAtual)}
      </td>
      <td className="num px-2 py-2 text-center text-gray-500" style={{ background: FUNDO_VAR }}>{moeda(vr.sugerido)}</td>
      <CelulaEdicao fundo={FUNDO_VAR_EDIT} sim={vr} base={baseVAR} cenarioSel={cenarioSel}
                    cenarios={p.cenariosVarejo} parametros={parametros}
                    valor={precoVAR} aoTrocar={setPrecoVAR}
                    rotulo={`Novo preço de varejo do produto ${p.codigo}`}
                    decidido={p.precoDecididoVarejoAV}
                    aplicado={precoJaAplicado(p.pvVarejo, p.precoDecididoVarejoAV)}
                    dataDecisao={p.precoDecididoEm} dataAplicado={p.precoAlteradoEmVarejo} />
    </tr>
  );
}

function Tributacao({ p }) {
  const cor = { ST_SUBSTITUTO: NAVY, ST_RECOLHIDO: "#7C3AED" }[p.modalidade] ?? CINZA;
  const rotulo = { ST_SUBSTITUTO: "ST Substituto", ST_RECOLHIDO: "ST Recolhido" }[p.modalidade] ?? "Normal";
  // O texto do regime vem de COMPRAS_PRODUTO_CONTEXTO. Nulo nos 5 SKUs sem
  // tributação encontrada — os mesmos do alerta TRIB; nesse caso o chip não
  // ganha `title` nenhum (nem "—"), porque tooltip vazio no hover é pior que
  // nenhum tooltip.
  //
  // O detalhe do regime mora só no `title` nativo do chip (pedido do
  // Diretor: a coluna estava larga por causa da segunda linha de 9px que
  // sempre aparecia). Sem lib nova, é o mesmo recurso que
  // `lotePrecoStatus.js` já usa com `textoConferencia`.
  // ⚠ Contrapartida real: `title` não aparece em toque — no celular, o
  // regime fiscal deixa de ficar visível. Aceito de propósito: é informação
  // secundária numa tabela de 15+ colunas que já rola de lado.
  return (
    <span className="whitespace-nowrap rounded-full px-2 py-0.5 text-2xs font-semibold"
          style={{ background: `${cor}18`, color: cor }}
          title={p.regimeFiscal || undefined}>
      {rotulo}{p.creditoPisCofins === 0 ? " · Mono" : ""}
    </span>
  );
}

/* Etapa 12 §4.2: não há mais botão nem estado de gravação POR CÉLULA — digitar
 * aqui só atualiza o mapa `precosAT`/`precosVAR` (em `Tabela`, acima); gravar
 * de verdade — e criar o lote — é o botão único do rodapé
 * (`BarraGravacaoLote`/`ConfirmarDefinirPrecos`). Antes deste ponto, cada
 * célula tinha seu próprio botão "Gravar" e um `useState` de estado que dava o
 * Defeito A (PROMPT_ETAPA_12 §2: o botão sumia depois da 1ª gravação e nunca
 * reaparecia); remover o botão daqui elimina o defeito por construção, em vez
 * de só consertá-lo. */
function CelulaEdicao({ fundo, sim, base, cenarioSel, cenarios, parametros, valor, aoTrocar,
                        rotulo, decidido, aplicado, dataDecisao, dataAplicado }) {
  // Etapa 15, ponto 2: "decidido, ainda não aplicado" é o único estado em que
  // o campo nasce preenchido e a sugestão desce para a linha de apoio — os
  // dois "efeitos" do decidido (§4.3 do prompt). Uma vez aplicado, é como se
  // não houvesse decisão pendente: mesmo tratamento visual de "sem decisão".
  const pendente = decidido != null && !aplicado;

  // Etapa 19, item 1: margem e MKP viram campos editáveis, ao lado do preço —
  // mas o ESTADO continua sendo só o preço (`valor`/`aoTrocar`, de sempre).
  // Margem e MKP não são um segundo estado: são FORMAS DE ENTRADA que escrevem
  // no mesmo mapa `precosAT`/`precosVAR` (§3.3 do prompt). `editando` guarda
  // só o texto cru do campo que a pessoa está digitando, para o cursor não
  // pular quando o valor derivado é recalculado a cada tecla.
  const [editando, setEditando] = useState(null); // null | { campo: "margem"|"mkp", texto }

  // Trocar o cenário muda custo e alíquota (§3.4): o campo dirigente volta a
  // ser o preço, que PERMANECE — só margem e MKP são recalculados sob o
  // cenário novo. Sem isto, o campo de margem continuaria mostrando o texto
  // cru de um cenário que não existe mais.
  useEffect(() => setEditando(null), [cenarioSel]);

  const custoValido = sim.custo != null && sim.custo > 0;

  function aoTrocarMargem(texto) {
    setEditando({ campo: "margem", texto });
    const pctDigitado = parseNumeroPreco(texto);
    if (!Number.isFinite(pctDigitado)) return; // vazio ou inválido: não mexe no preço
    const novoPreco = precoDeMargem(pctDigitado / 100, sim.custo, base);
    if (novoPreco != null) aoTrocar(paraCampoPreco(novoPreco), sim.custo);
  }
  function aoTrocarMKP(texto) {
    setEditando({ campo: "mkp", texto });
    const mkp = parseNumeroPreco(texto);
    if (!Number.isFinite(mkp)) return;
    const novoPreco = precoDeMKP(mkp, sim.custo);
    if (novoPreco != null) aoTrocar(paraCampoPreco(novoPreco), sim.custo);
  }

  const valorMargem = editando?.campo === "margem" ? editando.texto
    : (sim.margemNova != null ? numero(sim.margemNova * 100, 1) : "");
  const valorMKP = editando?.campo === "mkp" ? editando.texto
    : (sim.mkpNovo != null ? numero(sim.mkpNovo, 2) : "");

  // Vermelho só quando a pessoa digitou algo que não produz preço nenhum —
  // nunca ao nascer vazio. Apagar o preço de quem digitou um caractere a mais
  // é o descarte silencioso que este projeto corrige tela por tela (§3.3).
  // O motivo vem de `precoEditavel.js`, uma vez só para as duas telas: ele é o
  // `title` e, por ser não-undefined, o sinal de borda vermelha. Distingue
  // "não é número" de "acima do teto", que antes diziam a mesma coisa.
  const motivoMargem = editando?.campo === "margem"
    ? motivoMargemInvalida(editando.texto, sim.custo, base) : undefined;
  const motivoMKP = editando?.campo === "mkp"
    ? motivoMKPInvalido(editando.texto, sim.custo) : undefined;

  // ⚠ NÃO solta a edição quando o valor digitado é inválido — 09/10/2026.
  //
  // Antes, o blur limpava `editando` sempre, e aí o campo voltava a exibir o
  // valor DERIVADO do preço. Com um valor rejeitado isso produzia exatamente
  // o que o Diretor relatou: digitar 80% no 2720 e o campo "virar 8,0% sem
  // aviso". O 8,0% nem era invenção — era o dígito INTERMEDIÁRIO "8", que é
  // margem válida, tendo escrito um preço antes do "0" chegar. O vermelho
  // aparecia durante a digitação e sumia no blur, junto com a explicação.
  //
  // Segurando a edição, o campo continua mostrando "80" em vermelho, com o
  // teto no `title`, até a pessoa corrigir ou apagar. Nada é revertido às
  // escondidas e nada é descartado: o preço que o intermediário escreveu
  // continua lá, visível, e é dela a decisão de mantê-lo ou não.
  function aoSairDoCampo() {
    if (motivoMargem == null && motivoMKP == null) setEditando(null);
  }
  const margemInvalida = motivoMargem != null;
  const mkpInvalido = motivoMKP != null;
  // Preço abaixo do custo (item 1b do Diretor, 09/10/2026). Diferente do
  // vermelho de margem/MKP, este NÃO é erro: pode ser queima de estoque, e o
  // preço é gravável. É aviso — e por isso continua marcado DEPOIS do blur,
  // contra o valor que de fato está no campo, não contra o texto em edição.
  // A confirmação de "Definir preços" cobra o segundo gesto.
  const precoNoCampo = parseNumeroPreco(valor);
  const precoAbaixoDoCusto = abaixoDoCusto(precoNoCampo, sim.custo);

  // Margem mínima (item 4 do Diretor, 09/10/2026). Julgada pelo PIOR cenário
  // da praça, não pelo escolhido: no 2720 o preço de R$ 18,00 dá margem
  // positiva num cenário e -18,9% noutro, e quem grava grava o preço, não o
  // cenário. Como `precoAbaixoDoCusto`, é julgado contra o VALOR DO CAMPO e
  // não contra o texto em edição — o aviso sobrevive ao blur, porque não é
  // erro de digitação: é consequência do preço.
  //
  // Os dois avisos são independentes e podem aparecer juntos. Todo preço
  // abaixo do custo tem margem negativa, mas o contrário é falso — e é
  // justamente esse "contrário" (preço ACIMA do custo e margem negativa, pelos
  // ~34% de impostos e comissão que saem antes) o caso que o Diretor mediu e
  // que passava calado.
  const { nivel: nivelMargemCampo, motivo: motivoMargemBaixa, margem: margemPiorCampo } =
    avaliarMargem(precoNoCampo, cenarios, base, parametros);
  const margemCritica = nivelMargemCampo >= MARGEM_CRITICA;
  const margemEmAlerta = nivelMargemCampo === MARGEM_ALERTA;

  // A borda dos TRÊS campos vem daqui: preço, margem e MKP escrevem o mesmo
  // preço, então avisar só no campo onde a pessoa digitou esconderia o aviso
  // de quem entrou pela margem — e o Diretor pediu explicitamente que valesse
  // "para a digitação de preço, margem e MKP".
  const bordaAviso = (precoAbaixoDoCusto || margemCritica) ? "border-red-500"
    : margemEmAlerta ? "border-amber-500" : null;
  const tituloAviso = [
    precoAbaixoDoCusto && `Abaixo do custo do cenário (${moeda(sim.custo)}).`,
    motivoMargemBaixa,
  ].filter(Boolean).join(" ") || undefined;

  return (
    <td className="px-2 py-1.5 text-center" style={{ background: fundo, minWidth: 215 }}>
      <div className="flex flex-wrap items-center justify-center gap-1">
        <input
          type="text" inputMode="decimal" value={valor ?? ""} aria-label={rotulo}
          onChange={(e) => { setEditando(null); aoTrocar(e.target.value, sim.custo); }}
          // O placeholder é a SUGESTÃO do cenário — quando NÃO há decisão
          // pendente (nem decisão, nem decisão já aplicada): aí o campo nasce
          // vazio e o placeholder é o único jeito de mostrar a meta, sem
          // preencher por conta própria (é o ponto de decisão humana que o
          // modelo existe para preservar). Com decisão PENDENTE, o campo
          // nasce preenchido com ELA (ver `Tabela`, acima) — a sugestão desce
          // para a linha de apoio "sugerido" logo abaixo, porque um
          // placeholder não aparece atrás de um valor.
          placeholder={!pendente && sim.sugerido != null ? numero(sim.sugerido, 2) : undefined}
          title={tituloAviso}
          className={`num w-[68px] rounded-md border bg-white px-1 py-1 text-center text-sm ${
            precoAbaixoDoCusto || margemCritica ? "border-red-500 font-semibold text-red-700"
            : margemEmAlerta ? "border-amber-500 font-semibold text-amber-700"
            : "border-gray-300"}`}
        />
        <input
          type="text" inputMode="decimal" value={valorMargem} disabled={!custoValido}
          aria-label={`Margem alvo de ${rotulo}`}
          onChange={(e) => aoTrocarMargem(e.target.value)}
          onBlur={aoSairDoCampo}
          title={motivoMargem ?? tituloAviso}
          className={`num w-[40px] rounded-md border bg-white px-1 py-1 text-center text-2xs disabled:bg-gray-100 disabled:text-gray-400 ${
            margemInvalida ? "border-red-500" : bordaAviso ?? "border-gray-300"}`}
        />
        <span className="text-2xs text-gray-400">%</span>
        <input
          type="text" inputMode="decimal" value={valorMKP} disabled={!custoValido}
          aria-label={`MKP de ${rotulo}`}
          onChange={(e) => aoTrocarMKP(e.target.value)}
          onBlur={aoSairDoCampo}
          title={motivoMKP ?? tituloAviso}
          className={`num w-[40px] rounded-md border bg-white px-1 py-1 text-center text-2xs disabled:bg-gray-100 disabled:text-gray-400 ${
            mkpInvalido ? "border-red-500" : bordaAviso ?? "border-gray-300"}`}
        />
        <span className="text-2xs text-gray-400">x</span>
      </div>
      <div className="num mt-1 whitespace-nowrap text-[9px] leading-none text-gray-400">
        {sim.prazo != null
          ? `Pz ${moeda(sim.prazo)} · ${numero(sim.mkpPrazo, 2)}x/${pct(sim.margemPrazo, 0)}`
          : "Pz —"}
      </div>
      {/* O número que o aviso afirma, escrito na célula — não só no `title`.
          Um aviso que só existe ao passar o mouse não existe no celular, e a
          Precificação é usada nele. Aparece apenas quando HÁ aviso: em
          operação normal a linha não ocupa espaço nenhum. */}
      {nivelMargemCampo !== 0 && (
        <div className={`num mt-0.5 whitespace-nowrap text-[9px] font-semibold leading-none ${
          margemCritica ? "text-red-700" : "text-amber-700"}`}>
          pior cenário {pct(margemPiorCampo, 1)}
        </div>
      )}
      {/* Preço já decidido por gente, lido AO VIVO de APP_DECISAO_PRECO — só
          enquanto PENDENTE (ainda não aplicado no Winthor). A data é a da
          DECISÃO (`precoDecididoEm`/`APP_DECISAO_PRECO.ATUALIZADO_EM`), nunca
          a do Winthor — cada linha traz a data da fonte do número ao lado
          dela (§4.3/§4.5 do prompt). */}
      {pendente && (
        <div className="num mt-1 text-[9px] leading-none" style={{ color: NAVY }}>
          decidido {moeda(decidido)}{dataDecisao ? ` · ${fmtData(dataDecisao)}` : ""}
        </div>
      )}
      {/* A sugestão do cenário só vive no placeholder quando o campo está vazio
          (sem decisão pendente). Com decisão pendente, o campo já nasce
          preenchido com ela — a sugestão não desaparece, só muda de casa. */}
      {pendente && sim.sugerido != null && (
        <div className="num mt-1 text-[9px] leading-none text-gray-400">
          sugerido {moeda(sim.sugerido)}
        </div>
      )}
      {/* Aplicado: o "decidido" some — o preço decidido virou o preço vigente,
          então repeti-lo ao lado do "atual" da coluna vizinha é ruído. A data
          é a da ALTERAÇÃO NO WINTHOR (`dataAplicado`, por CANAL — nunca a
          data da decisão: 79 SKUs têm datas diferentes entre atacado e
          varejo, §4.5). Nula em 650 SKUs (226 ativos): o texto vira "preço
          aplicado", sem data — o traço não é uma data, e a linha não some
          por completo para não ficar idêntica a um SKU nunca decidido. */}
      {aplicado && (
        <div className="num mt-1 text-[9px] leading-none" style={{ color: CINZA }}>
          {dataAplicado ? `preço alterado em ${fmtData(dataAplicado)}` : "preço aplicado"}
        </div>
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
