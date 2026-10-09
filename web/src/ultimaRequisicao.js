import { useCallback, useRef } from "react";

/** Ignora a resposta que chegar ATRASADA.
 *
 *  O defeito que isto corrige, relatado pelo Diretor de Compras em
 *  09/10/2026: "no Monitoramento, clicando rápido em 'ano anterior', aparece
 *  2019 com os números de 2021 (R$ 269,0 mi em vez de R$ 185,8 mi)".
 *
 *  A causa é `setDados(await api.algo(...))`: cada clique dispara uma
 *  consulta, e quem escreve na tela é quem CHEGAR, não quem foi pedido por
 *  último. Com uma varredura de 2,1 milhões de linhas por trás, dois cliques
 *  seguidos terminam fora de ordem com facilidade — e o resultado é o pior
 *  tipo de erro: o número é plausível, o rótulo diz outro período, e nada na
 *  tela avisa.
 *
 *  Uso — três linhas, sempre as mesmas:
 *
 *      const novaRequisicao = useUltimaRequisicao();
 *      ...
 *      const aindaVale = novaRequisicao();     // esta passa a ser a atual
 *      try {
 *        const r = await api.algo(...);
 *        if (!aindaVale()) return;             // outra foi pedida depois
 *        setDados(r);
 *      } catch (e) {
 *        if (!aindaVale()) return;
 *        setErro(e.detalhe);
 *      } finally {
 *        if (aindaVale()) setCarregando(false);
 *      }
 *
 *  ⚠ O `finally` TAMBÉM é guardado, e esse é o detalhe que se esquece: sem
 *  ele, a resposta atrasada apaga o "Carregando" da consulta que ainda está
 *  em curso, e a tela fica mostrando dado velho com cara de pronto.
 *
 *  Por que um contador e não o `cancelado` de `useEffect`: a busca destas
 *  telas também é chamada pelo botão "tentar de novo" do componente de erro,
 *  fora de qualquer efeito. O contador vale nos dois caminhos; a limpeza do
 *  efeito, só num deles. */
export function useUltimaRequisicao() {
  const atual = useRef(0);
  return useCallback(() => {
    const meu = ++atual.current;
    return () => meu === atual.current;
  }, []);
}
