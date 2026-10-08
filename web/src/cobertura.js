/** Cobertura projetada, em meses, somando uma quantidade AINDA NÃO GRAVADA.
 *
 *  ⚠ CONTEXTO.md regra 6. `estPend` e `mediaJanela` chegam da API já DIVIDIDOS
 *  por FATOR_EXIBICAO (int_produto_demanda.sql:138,142,171,201) — estão em
 *  unidade de EXIBIÇÃO. O campo onde se digita a quantidade também é em
 *  unidade de exibição (o rótulo abaixo dele diz "caixas"). Portanto NÃO se
 *  multiplica a quantidade por fatorExibicao aqui: foi essa multiplicação que
 *  fez o item 2808 mostrar 39,5 meses onde o certo eram 7,0 (item 1.12 do
 *  Diretor, 08/10/2026; medido em 103 dos 973 itens de pedido gravados, erro
 *  mediano de 15,77 meses).
 *
 *  ⚠ `estPend` JÁ INCLUI `estDisp` (int_produto_demanda.sql:201; medido em
 *  8.944 de 8.944 linhas de COMPRAS_PEDIDO). Somar os dois conta o estoque
 *  duas vezes — era o segundo defeito de DecisaoSKU.jsx:89.
 *
 *  Multiplicar por fatorExibicao continua CERTO para valor, peso e litros
 *  (Pedidos.jsx:167-175): são medidas absolutas, por unidade real.
 */
export function coberturaComPedido(p, quantidadeDigitada) {
  const qtd = Number(String(quantidadeDigitada ?? "").replace(",", ".")) || 0;
  if (qtd <= 0) return null;
  if (!p?.mediaJanela) return null;
  return (Number(p.estPend || 0) + qtd) / p.mediaJanela;
}
