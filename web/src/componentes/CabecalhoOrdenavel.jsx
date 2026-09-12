import { useCallback } from "react";
import { useSearchParams } from "react-router-dom";
import { ChevronDown, ChevronUp } from "lucide-react";

/* Etapa 13, ponto 4 (PROMPT_ETAPA_13 §3.4) — pedido do Diretor: "Onde há
 * tabela, deve ser possível reordenar clicando na coluna, em crescente e
 * decrescente, como o padrão em algumas aplicações/relatórios".
 *
 * Um componente só, usado por TODA tabela do sistema — paginada ou não. A
 * diferença entre as duas mora em QUEM `aoOrdenar` avisa, não neste
 * componente:
 *   - lista PAGINADA (Precificação, Pedidos, Alertas — `/api/produtos`;
 *     Preços Definidos — `/api/lotes-preco`; Pedidos Salvos — `/api/pedidos`):
 *     `aoOrdenar` manda `ordenar`/`dir` para o SERVIDOR e volta para a
 *     página 1. Ordenar no cliente uma lista paginada ordenaria só os itens
 *     da página atual — o defeito medido no PROMPT §3.1: a pior margem do
 *     catálogo continuaria na página 7 enquanto a coluna diz "ordenado por
 *     margem". `useOrdenacaoUrl` (abaixo) é o meio pronto para este caso.
 *   - lista SEM paginação (Monitoramento, Entradas, itens de um pedido/lote):
 *     `aoOrdenar` só reordena o array em memória — `ordenarLista` (abaixo)
 *     faz a comparação, com a MESMA regra de nulo por último que o servidor
 *     usa (`nulls last` em produto._ordem), para o cliente não inventar um
 *     critério diferente do SQL.
 *
 * Coluna que não tem como ser ordenada no servidor NÃO recebe este
 * componente — melhor uma coluna que não ordena do que uma que ordena
 * errado (§3.1). Cada uso deste componente documenta, no arquivo que o usa,
 * contra qual entrada de `ORDENACOES` (produto.py/pedido.py/lote_preco.py)
 * a chave `coluna` corresponde.
 */

/** Cabeçalho de coluna clicável.
 *
 * - `coluna`: a chave que vai para `ordenar` (produto/pedido/lote de preço) —
 *   tem que existir no whitelist do backend (`ORDENACOES_VALIDAS`), senão o
 *   servidor devolve 422.
 * - `padrao`: direção do PRIMEIRO clique nesta coluna ("asc" | "desc") — tem
 *   que ser a MESMA que o backend usa como direção padrão daquela coluna
 *   (`ORDENACOES` em `produto.py`/`pedido.py`/`lote_preco.py`), senão o
 *   primeiro clique inverte sozinho e parece um bug de "clicou ao contrário".
 * - `ordenar`/`dir`: o estado ATUAL da lista inteira (não só desta coluna) —
 *   é assim que clicar numa coluna "desliga" a seta de qualquer outra, e que
 *   o mesmo estado é compartilhado com o `SeletorOrdenacao` de cada tela
 *   (PROMPT §3.3): as duas UI escrevem no mesmo par `[ordenar, dir]`.
 * - `aoOrdenar(coluna, dir)`: chamado ao clicar. Nunca há um terceiro clique
 *   que "desliga" — a lista está sempre ordenada por algo.
 * - `as="th"` (padrão): célula de `<table>`, com `aria-sort` no `<th>` — é o
 *   atributo que torna a tabela navegável por leitor de tela. `as="button"`:
 *   só o botão, sem `<th>` em volta — para reusar o MESMO componente em
 *   listas de cartão sem `<table>` (Preços Definidos, Pedidos Salvos), sem
 *   inventar um segundo componente de ordenação para elas.
 */
export default function CabecalhoOrdenavel({
  coluna, padrao = "asc", ordenar, dir, aoOrdenar,
  align = "left", as = "th", className = "", style, children,
}) {
  const ativa = ordenar === coluna;
  const direcaoAtual = ativa ? (dir === "asc" || dir === "desc" ? dir : padrao) : null;

  function clicar() {
    // Coluna ainda não ativa: primeiro clique usa a direção PADRÃO dela, não
    // a direção que a coluna anterior deixou — "margem" abre em pior
    // primeiro mesmo que a coluna anterior estivesse em "asc".
    if (!ativa) { aoOrdenar(coluna, padrao); return; }
    aoOrdenar(coluna, direcaoAtual === "asc" ? "desc" : "asc");
  }

  const justificar = align === "right" ? "justify-end" : align === "center" ? "justify-center" : "justify-start";
  const alinhamentoTexto = align === "right" ? "text-right" : align === "center" ? "text-center" : "text-left";

  const Seta = direcaoAtual === "asc" ? ChevronUp : ChevronDown;

  // `w-full` só faz sentido dentro do `<th>` (§3.4: "o `<th>` inteiro é o
  // alvo do clique") — como botão solto (listas de cartão, `as="button"`),
  // esticar a 100% quebraria o layout do contêiner flex que o chama.
  const botao = (
    <button type="button" onClick={clicar}
            aria-label={`Ordenar por ${typeof children === "string" ? children : coluna}`}
            className={`flex items-center gap-1 whitespace-nowrap font-medium ${
              as === "th" ? "w-full" : ""} ${justificar} ${
              ativa ? "text-gray-800" : "text-gray-500 hover:text-gray-700"}`}>
      {children}
      {ativa && <Seta size={11} aria-hidden="true" className="shrink-0" />}
    </button>
  );

  if (as === "button") return botao;

  return (
    <th aria-sort={ativa ? (direcaoAtual === "asc" ? "ascending" : "descending") : undefined}
        style={style}
        className={`px-2 py-2 font-medium ${alinhamentoTexto} ${className}`}>
      {botao}
    </th>
  );
}

/** Ordenação NO CLIENTE — só para lista SEM paginação (§3.1). `extrator(item)`
 *  devolve o valor a comparar; nulo/undefined vai sempre para o fim, nas duas
 *  direções — a mesma regra do `nulls last` que o servidor aplica em
 *  `produto._ordem`, para o cliente nunca inventar um critério diferente do
 *  SQL (ex.: produto sem cobertura calculada encabeçando a lista em "menor
 *  primeiro"). Devolve um array NOVO — nunca muta `itens`. */
export function ordenarLista(itens, extrator, dir) {
  const copia = [...itens];
  copia.sort((a, b) => {
    const va = extrator(a);
    const vb = extrator(b);
    const nulaA = va == null;
    const nulaB = vb == null;
    if (nulaA && nulaB) return 0;
    if (nulaA) return 1;
    if (nulaB) return -1;
    const cmp = typeof va === "string" || typeof vb === "string"
      ? String(va).localeCompare(String(vb), "pt-BR", { numeric: true })
      : va < vb ? -1 : va > vb ? 1 : 0;
    return dir === "asc" ? cmp : -cmp;
  });
  return copia;
}

/** Estado de ordenação de uma lista PAGINADA, sincronizado com a URL
 *  (`?ordenar=...&dir=...`) — mesmo motivo do `<Link>` no resto da navegação
 *  desta etapa: ordenou, achou, manda o link; recarregar mantém a ordem.
 *
 *  `aoTrocarPagina`, se passado, volta a lista para a página 1 a cada troca
 *  de ordenação — manter a página 12 com outra ordenação mostraria um pedaço
 *  arbitrário do meio do novo resultado (§3.4). */
export function useOrdenacaoUrl(padraoOrdenar, padraoDir, aoTrocarPagina) {
  const [searchParams, setSearchParams] = useSearchParams();
  const ordenar = searchParams.get("ordenar") || padraoOrdenar;
  const dir = searchParams.get("dir") || padraoDir;

  const aoOrdenar = useCallback((coluna, direcao) => {
    setSearchParams((prev) => {
      const p = new URLSearchParams(prev);
      p.set("ordenar", coluna);
      p.set("dir", direcao);
      return p;
    }, { replace: true });
    aoTrocarPagina?.(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setSearchParams]);

  // Ajuste 1 do revisor (13/09) — telas com ORDEM COMPOSTA padrão (hoje só
  // Alertas: severidade → curva ABC → soma, "prioridade") não têm coluna
  // correspondente a clicar de volta (§3.3: "o que é ordem composta fica no
  // seletor"), e nem sempre a tela tem espaço para o seletor completo de
  // Pedidos/Precificação. `resetar` tira os dois parâmetros da URL — não os
  // aponta de volta para `padraoOrdenar`/`padraoDir`, porque `ordenar`/`dir`
  // já caem no padrão quando o parâmetro não existe (linhas acima); remover
  // é o estado IDÊNTICO a "nunca ordenou por outra coisa", não uma cópia dele.
  const resetar = useCallback(() => {
    setSearchParams((prev) => {
      const p = new URLSearchParams(prev);
      p.delete("ordenar");
      p.delete("dir");
      return p;
    }, { replace: true });
    aoTrocarPagina?.(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setSearchParams]);

  return { ordenar, dir, aoOrdenar, resetar };
}
