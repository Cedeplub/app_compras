import { createContext, useCallback, useContext, useEffect, useState } from "react";

/* Carrinho do pedido em construção — sobrevive à troca de tela e ao F5.
 * Molde: `contexto/atualizacao.jsx`.
 *
 * Etapa 13, §6.2 (`PROMPT_ETAPA_13_NAVEGACAO_E_TABELAS.md`). O pedido do
 * Diretor foi "abrir um produto para visualizar informações, sem sair da
 * página de pedidos que está sendo criado" — e a causa por trás do pedido é
 * maior do que só "faltava aba nova": SAIR da tela de Pedidos (ainda que na
 * mesma aba, ida e volta) zerava o carrinho inteiro, porque ele vivia em
 * `useState({})` dentro de `Pedidos.jsx`, sem contexto nem storage nenhum.
 * `historico/PLANO_v2_20260901.md` §3 (Etapa 9) já registrava "o carrinho
 * sobrevive à troca de tela" como diferença deliberada do protótipo — ficou
 * por fazer até aqui.
 *
 * Duas decisões de desenho, já tomadas no prompt desta etapa:
 *
 * 1. `sessionStorage`, não `localStorage`. O carrinho é trabalho em curso de
 *    UMA sessão, não preferência permanente — `localStorage` faria o carrinho
 *    de terça reaparecer na quinta, com preço e cobertura de outro build do
 *    dbt. E `sessionStorage` é POR ABA, que é exatamente o comportamento
 *    certo aqui: a aba nova que o Diretor abre para ver o produto não herda
 *    nem atropela o carrinho da aba onde ele está montando o pedido.
 * 2. Guarda só `{codigo: quantidadeDigitada}`. NUNCA preço, custo, margem ou
 *    cobertura — esses envelhecem no próximo `dbt run`, e reidratar um número
 *    velho de storage seria decisão tomada sobre dado que já não existe mais.
 *    Ao montar a tela, os números frescos vêm sempre da API; do storage só
 *    volta o que a pessoa efetivamente digitou.
 */

const CHAVE_STORAGE = "app_compras_carrinho_v1";

const CarrinhoContexto = createContext(null);

// Validação mínima do que volta do storage: só um objeto plano
// {codigo: quantidade}, com valores string/number. Qualquer outra forma —
// lixo de uma versão anterior da tela, array, JSON truncado — vira carrinho
// vazio. `sessionStorage` também pode simplesmente não existir (janela
// anônima, site data bloqueado); o `try/catch` cobre os dois casos com o
// mesmo resultado: começa vazio, nunca derruba a tela.
function lerStorage() {
  try {
    const bruto = window.sessionStorage.getItem(CHAVE_STORAGE);
    if (!bruto) return {};
    const json = JSON.parse(bruto);
    if (!json || typeof json !== "object" || Array.isArray(json)) return {};
    const limpo = {};
    for (const [codigo, qtd] of Object.entries(json)) {
      if (typeof qtd === "string" || typeof qtd === "number") limpo[codigo] = qtd;
    }
    return limpo;
  } catch {
    return {};
  }
}

function escreverStorage(carrinho) {
  try {
    window.sessionStorage.setItem(CHAVE_STORAGE, JSON.stringify(carrinho));
  } catch {
    // Se não der para gravar (quota, storage desabilitado), o carrinho
    // continua funcionando em memória pelo resto da aba — não é motivo para
    // quebrar a tela de Pedidos.
  }
}

export function CarrinhoProvider({ children }) {
  // Inicialização preguiçosa: lê o storage uma vez, no primeiro render — é o
  // que faz o F5 devolver o carrinho, e não só a navegação interna (que já
  // funcionaria com contexto puro, sem storage nenhum).
  const [carrinho, setCarrinho] = useState(lerStorage);

  useEffect(() => { escreverStorage(carrinho); }, [carrinho]);

  const limparCarrinho = useCallback(() => setCarrinho({}), []);

  return (
    <CarrinhoContexto.Provider value={{ carrinho, setCarrinho, limparCarrinho }}>
      {children}
    </CarrinhoContexto.Provider>
  );
}

export function useCarrinho() {
  const contexto = useContext(CarrinhoContexto);
  if (!contexto) throw new Error("useCarrinho precisa estar dentro de CarrinhoProvider");
  return contexto;
}
