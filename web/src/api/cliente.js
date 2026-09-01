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

export const api = {
  sessao: () => requisitar("/sessao"),
  entrar: (login, senha) =>
    requisitar("/login", { method: "POST", body: JSON.stringify({ login, senha }) }),
  sair: () => requisitar("/logout", { method: "POST" }),

  parametros: () => requisitar("/parametros"),
  opcoes: () => requisitar("/opcoes"),

  produtos: (filtros = {}) => {
    const busca = parametrosDeBusca(filtros);
    return requisitar(`/produtos${busca ? `?${busca}` : ""}`);
  },
  produto: (codigo) => requisitar(`/produtos/${codigo}`),
};
