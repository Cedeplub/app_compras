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
      if (corpo?.detail) detalhe = corpo.detail;
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

  /** Exportações são DOWNLOAD, não JSON: `requisitar` desmontaria o arquivo
   *  tentando fazer `.json()` dele. Por isso o caminho separado, devolvendo o
   *  blob e o nome que o servidor mandou no Content-Disposition. */
  baixarExportacao: async (id, formato) => {
    const resp = await fetch(`/api/pedidos/${id}/exportar/${formato}`, { credentials: "same-origin" });
    if (!resp.ok) {
      let detalhe = `Erro ${resp.status}.`;
      try { detalhe = (await resp.json())?.detail ?? detalhe; } catch { /* sem corpo JSON */ }
      throw new ErroApi(resp.status, detalhe);
    }
    const disp = resp.headers.get("Content-Disposition") ?? "";
    const nome = /filename\*?=(?:UTF-8'')?"?([^";]+)/i.exec(disp)?.[1] ?? `pedido_${id}.xlsx`;
    return { blob: await resp.blob(), nome: decodeURIComponent(nome) };
  },
};
