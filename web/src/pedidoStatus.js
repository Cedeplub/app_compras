/** A máquina de estados do pedido, do lado da tela.
 *
 * Rascunho → Orçamento Enviado → Fechado → Exportado, um passo por vez, com
 * desfazer simétrico (PROTOTIPO.md §2.5).
 *
 * ⚠ Isto NÃO é a regra: a regra vive no servidor, que recusa pulo de etapa com
 * 409. O que está aqui decide só o que a tela DESENHA — qual botão aparece,
 * como se chama e de que cor é. Se os dois divergirem, o pior que acontece é a
 * tela oferecer um botão que o servidor recusa, com mensagem clara. O contrário
 * — a regra morar só na tela — deixaria a transição à mercê de quem chamasse a
 * API por fora.
 */

export const STATUS = ["Rascunho", "Orçamento Enviado", "Fechado", "Exportado"];

export const COR_STATUS = {
  Rascunho: "#6B7280",
  "Orçamento Enviado": "#B98A2E",
  Fechado: "#375DA8",
  Exportado: "#15803D",
};

/** Só Rascunho e Orçamento Enviado aceitam edição (§2.6). Nos outros dois os
 *  campos viram texto — e o servidor recusa a escrita de qualquer forma. */
export const editavel = (status) =>
  status === "Rascunho" || status === "Orçamento Enviado";

/** O rótulo do botão que avança, do ponto de vista de quem clica: "Marcar
 *  enviado" diz o que vai acontecer; "Avançar status" faria a pessoa adivinhar. */
export const ROTULO_AVANCAR = {
  Rascunho: "Marcar enviado",
  "Orçamento Enviado": "Marcar fechado",
  Fechado: "Exportar Winthor",
};

export const ROTULO_VOLTAR = {
  "Orçamento Enviado": "Voltar p/ rascunho",
  Fechado: "Voltar p/ orçamento",
  Exportado: "Voltar p/ fechado",
};

export const podeAvancar = (status) => status in ROTULO_AVANCAR;
export const podeVoltar = (status) => status in ROTULO_VOLTAR;

/** De Fechado, avançar É exportar: o próprio ato de gerar o arquivo do Winthor
 *  muda o status para Exportado, na mesma transação (§2.5). A tela precisa
 *  saber disso para chamar a exportação em vez do /avancar. */
export const avancarEhExportar = (status) => status === "Fechado";
