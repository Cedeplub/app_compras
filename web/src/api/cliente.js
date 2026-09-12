/** Único ponto de contato com o FastAPI.
 *
 *  Concentrado num arquivo pelo mesmo motivo que `app/core/database.py` é o
 *  único que fala com o Oracle: a regra "sessão expirada leva ao login" tem de
 *  existir uma vez, não em cada tela — e é verificável abrindo um arquivo só.
 */

export class ErroApi extends Error {
  constructor(status, detalhe) {
    super(detalhe);
    this.status = status;
    this.detalhe = detalhe;
  }
}

/** Disparado quando a sessão morre. `App` escuta e manda para o login.
 *  Redirecionar daqui direto (`location.href = ...`) faria a tela perder
 *  qualquer coisa que a pessoa tivesse digitado, sem aviso — que é justamente
 *  o defeito de descartar edição em silêncio que o protótipo tem (§8). */
export const SESSAO_EXPIROU = "sessao-expirou";

/** O `detail` de um 422 do pydantic é uma LISTA de objetos `{loc, msg, type}`,
 *  não uma string. Passar isso direto para `{erro}` num JSX quebra a árvore
 *  inteira ("Objects are not valid as a React child") — tela branca em vez de
 *  mensagem feia. Normalizado aqui, uma vez, para toda tela que usa `ErroApi`. */
function detalheLegivel(detail) {
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((d) => (typeof d === "string" ? d : d?.msg ?? JSON.stringify(d)))
      .join(" ");
  }
  if (detail && typeof detail === "object") return detail.msg ?? JSON.stringify(detail);
  return String(detail);
}

async function requisitar(caminho, opcoes = {}) {
  let resposta;
  try {
    resposta = await fetch(`/api${caminho}`, {
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      ...opcoes,
    });
  } catch {
    // Falha de rede não tem status HTTP. Sem este ramo, a tela mostraria
    // "undefined" — e o protótipo não tem estado de erro nenhum (§8), então
    // é uma lacuna que o MVP precisa fechar em toda tela.
    throw new ErroApi(0, "Sem conexão com o servidor. Tente de novo em instantes.");
  }

  if (resposta.status === 401) {
    window.dispatchEvent(new CustomEvent(SESSAO_EXPIROU));
    throw new ErroApi(401, "Sessão expirada.");
  }

  if (!resposta.ok) {
    let detalhe = `Erro ${resposta.status}.`;
    try {
      const corpo = await resposta.json();
      if (corpo?.detail) detalhe = detalheLegivel(corpo.detail);
    } catch {
      /* resposta sem corpo JSON: fica a mensagem genérica */
    }
    throw new ErroApi(resposta.status, detalhe);
  }

  return resposta.status === 204 ? null : resposta.json();
}

const parametrosDeBusca = (filtros) => {
  const p = new URLSearchParams();
  for (const [chave, valor] of Object.entries(filtros)) {
    if (valor === null || valor === undefined || valor === "" || valor === false) continue;
    // Arrays viram chave repetida (?tipoAlerta=a&tipoAlerta=b), que é o que o
    // FastAPI espera em `Query(default=None)` de lista.
    if (Array.isArray(valor)) valor.forEach((v) => p.append(chave, v));
    else p.append(chave, String(valor));
  }
  return p.toString();
};

let _parametros = null;

export const api = {
  sessao: () => requisitar("/sessao"),
  entrar: (login, senha) =>
    requisitar("/login", { method: "POST", body: JSON.stringify({ login, senha }) }),
  sair: () => requisitar("/logout", { method: "POST" }),

  // Memorizado: os parâmetros do modelo só mudam com `dbt seed`, e cada tela
  // que recalcula margem precisa deles. Sem cache, abrir Precificação e depois
  // Decisão do SKU faria duas consultas idênticas.
  parametros: () => (_parametros ??= requisitar("/parametros").catch((e) => {
    _parametros = null;    // falhou: a próxima tentativa refaz, não fica presa no erro
    throw e;
  })),
  opcoes: () => requisitar("/opcoes"),

  produtos: (filtros = {}) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/produtos${busca ? `?${busca}` : ""}`);
  },
  produto: (codigo) => requisitar(`/produtos/${codigo}`),

  /** Grava a decisão humana de preço. Só à vista — o a prazo é derivado do
   *  fator, e a API recusa com 422 quem tentar mandá-lo, para não criar duas
   *  verdades sobre o mesmo preço. Devolve o produto já atualizado. */
  gravarPreco: (codigo, corpo) =>
    requisitar(`/produtos/${codigo}/preco`, { method: "POST", body: JSON.stringify(corpo) }),

  /** Grava um LOTE de decisões de preço (até 200 itens, teto do servidor —
   *  ver LIMITE_LOTE_PRECO em Precificacao.jsx). Mesma restrição de perfil do
   *  unitário, mesma transação única no servidor: tudo ou nada. */
  gravarPrecoLote: (itens) =>
    requisitar("/produtos/preco", { method: "POST", body: JSON.stringify({ itens }) }),

  // ------------------------------------------- monitoramento e entradas ---
  opcoesMonitoramento: () => requisitar("/monitoramento/opcoes"),

  /** O período vai como INTERVALO de datas, calculado em `periodo.js`. O
   *  servidor soma o que recebe e não reinterpreta calendário — quem sabe o que
   *  "essa semana" significa, e onde ela é parcial, é o seletor da tela. */
  monitoramento: (filtros) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/monitoramento${busca ? `?${busca}` : ""}`);
  },
  entradas: (filtros) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/entradas${busca ? `?${busca}` : ""}`);
  },

  // ------------------------------------------------------------- pedidos ---
  /** Salva o carrinho. O servidor cria UM pedido por fornecedor — é exigência
   *  do formato de importação do Winthor (rotina 220). */
  salvarCarrinho: (itens) =>
    requisitar("/pedidos", { method: "POST", body: JSON.stringify({ itens }) }),

  pedidos: (filtros = {}) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/pedidos${busca ? `?${busca}` : ""}`);
  },
  pedido: (id) => requisitar(`/pedidos/${id}`),

  gravarItemPedido: (id, codigo, corpo) =>
    requisitar(`/pedidos/${id}/itens/${codigo}`, { method: "PUT", body: JSON.stringify(corpo) }),
  removerItemPedido: (id, codigo) =>
    requisitar(`/pedidos/${id}/itens/${codigo}`, { method: "DELETE" }),

  avancarPedido: (id) => requisitar(`/pedidos/${id}/avancar`, { method: "POST" }),
  voltarPedido: (id) => requisitar(`/pedidos/${id}/voltar`, { method: "POST" }),
  excluirPedido: (id) => requisitar(`/pedidos/${id}`, { method: "DELETE" }),

  // -------------------------------------------------------- atualização ---
  atualizacao: () => requisitar("/atualizacao"),
  dispararAtualizacao: () => requisitar("/atualizacao", { method: "POST" }),

  /** Zera o cache de `parametros` (linha 68/79). Sem isso, depois de uma
   *  carga do dbt a tela continuaria calculando margem com o `FATOR_PRAZO` e
   *  a `DATA_REFERENCIA` da carga ANTERIOR — os parâmetros só existem em
   *  memória porque `_parametros` é privado do módulo, e nada os invalidava
   *  sozinho. Chamado pelo contexto de atualização assim que uma execução
   *  termina bem. */
  limparCacheParametros: () => { _parametros = null; },

  /** Exportações são DOWNLOAD, não JSON: `requisitar` desmontaria o arquivo
   *  tentando fazer `.json()` dele. Por isso o caminho separado, devolvendo o
   *  blob e o nome que o servidor mandou no Content-Disposition. O miolo mora
   *  em `baixarArquivo` (abaixo) — extraído daqui na Etapa 12 para o lote de
   *  preços (dois arquivos: Excel de conferência e os dois xlsx da rotina 201)
   *  usar o MESMO tratamento de `Content-Disposition`, em vez de duplicá-lo. */
  baixarExportacao: (id, formato) => baixarArquivo(`/pedidos/${id}/exportar/${formato}`, `pedido_${id}.xlsx`),

  // --------------------------------------------------------- lote de preço ---
  // Etapa 12: o lote de preços como documento (v2/PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md).
  // Escrita (criar/editar/remover/avançar/excluir) é `diretoria` no servidor —
  // decidir preço é o único ponto de decisão humana do modelo. Ler/exportar é
  // só `login`: baixar o arquivo para levar a quem digita no Winthor não é decidir preço.

  lotesPreco: (filtros = {}) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/lotes-preco${busca ? `?${busca}` : ""}`);
  },
  lotePreco: (id) => requisitar(`/lotes-preco/${id}`),

  /** `idLote` ausente cria um lote novo em Rascunho; presente, ACRESCENTA os
   *  itens a um Rascunho existente — é assim que a tela parte uma gravação de
   *  mais de `LIMITE_LOTE_PRECO` itens em vários pedidos HTTP para o MESMO
   *  documento (nunca um lote por pedaço, PROMPT_ETAPA_12 §4.3). Grava a
   *  decisão em APP_DECISAO_PRECO e cria/atualiza o documento na MESMA
   *  transação do servidor — ou tudo, ou nada (§4.2). */
  criarOuAcrescentarLotePreco: (itens, idLote, observacao) =>
    requisitar("/lotes-preco", {
      method: "POST",
      body: JSON.stringify({ itens, idLote: idLote ?? null, observacao: observacao ?? null }),
    }),

  gravarItemLotePreco: (idLote, codigo, corpo) =>
    requisitar(`/lotes-preco/${idLote}/itens/${codigo}`, { method: "PUT", body: JSON.stringify(corpo) }),
  removerItemLotePreco: (idLote, codigo) =>
    requisitar(`/lotes-preco/${idLote}/itens/${codigo}`, { method: "DELETE" }),

  avancarLotePreco: (id) => requisitar(`/lotes-preco/${id}/avancar`, { method: "POST" }),
  voltarLotePreco: (id) => requisitar(`/lotes-preco/${id}/voltar`, { method: "POST" }),
  excluirLotePreco: (id) => requisitar(`/lotes-preco/${id}`, { method: "DELETE" }),

  /** Excel de conferência (todas as colunas, inclusive "Entra no arquivo 201?"
   *  — PROMPT_ETAPA_12 §4.6). Vale para qualquer status; é o que o Diretor
   *  manda olhar antes de decidir alguma coisa. */
  baixarExcelLotePreco: (id) => baixarArquivo(`/lotes-preco/${id}/exportar/excel`, `lote_preco_${id}.xlsx`),

  /** O arquivo pronto pra rotina 201 do Winthor: 2 colunas, sem cabeçalho,
   *  `COD_FAB` na coluna A (§4.6) — nunca o `CODIGO` interno. `canal` é
   *  "atacado" (região 2) ou "varejo" (região 1); baixar não muda o status do
   *  lote (§4.7 — são dois arquivos, marcar "enviado" é um clique à parte). */
  baixar201LotePreco: (id, canal) =>
    baixarArquivo(`/lotes-preco/${id}/exportar/201?canal=${canal}`, `winthor_201_${canal}_${id}.xlsx`),
};

/** Miolo comum de download por blob + `Content-Disposition`, para nenhuma
 *  tela ter seu próprio parsing do nome de arquivo (Etapa 12 — extraído de
 *  `baixarExportacao`, que era o único usuário até aqui). `nomePadrao` só
 *  entra se o servidor não mandar `Content-Disposition` com nome nenhum. */
async function baixarArquivo(caminho, nomePadrao) {
  const resp = await fetch(`/api${caminho}`, { credentials: "same-origin" });
  if (!resp.ok) {
    let detalhe = `Erro ${resp.status}.`;
    try {
      const corpo = await resp.json();
      if (corpo?.detail) detalhe = detalheLegivel(corpo.detail);
    } catch { /* sem corpo JSON */ }
    throw new ErroApi(resp.status, detalhe);
  }
  const disp = resp.headers.get("Content-Disposition") ?? "";
  const nome = /filename\*?=(?:UTF-8'')?"?([^";]+)/i.exec(disp)?.[1] ?? nomePadrao;
  return { blob: await resp.blob(), nome: decodeURIComponent(nome) };
}
