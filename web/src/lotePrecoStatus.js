import { numero, dataHoraCarga } from "./formato.js";

/** A máquina de estados do lote de preços, do lado da tela. Espelho de
 *  `pedidoStatus.js`, aplicado ao documento que sai da diretoria em direção a
 *  quem digita o preço no Winthor (rotina 201).
 *
 * Rascunho -> Enviado, um passo só — e é o único passo que existe
 * (PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md §4.5, decisão do usuário em
 * 10/09/2026): NÃO existe status "Aplicado" de LOTE. Não há usuário no app
 * para quem aplica o preço no Winthor dar esse clique, e o sistema já tem como
 * CONFERIR a aplicação de graça, comparando o preço novo do lote com o que
 * `COMPRAS_PEDIDO` tem hoje. O que seria um terceiro status virou SITUAÇÃO POR
 * ITEM (`SITUACAO_ITEM` abaixo) — medida, nunca declarada.
 *
 * ⚠ Isto NÃO é a regra: a regra vive no servidor (`app/servicos/lote_preco.py`),
 * que recusa pulo de etapa com 409 e é quem calcula a situação de cada item
 * (join com `COMPRAS_PEDIDO`, tolerância 0,005). O que está aqui decide só o
 * que a tela DESENHA — qual botão aparece, como se chama e de que cor é. Se os
 * dois divergirem, o pior que acontece é a tela oferecer um botão que o
 * servidor recusa, com mensagem clara.
 */

export const STATUS = ["Rascunho", "Enviado"];

export const COR_STATUS = {
  Rascunho: "#6B7280",
  Enviado: "#B98A2E",
};

/** Diferente de `pedidoStatus.editavel`: aqui os DOIS status aceitam edição de
 *  item (o servidor recusa fora de Rascunho/Enviado, mas esses são os únicos
 *  dois que existem — `STATUS_EDITAVEIS` em `lote_preco.py` é o próprio
 *  domínio inteiro). Não existe um status "fechado" que vire a tabela
 *  só-leitura: o documento só some (exclusão) ou o preço aparece aplicado pela
 *  SITUAÇÃO do item, nunca por bloqueio de campo. */
export const editavel = (status) => status === "Rascunho" || status === "Enviado";

/** Só uma entrada — de Enviado não há para onde avançar. "Marcar aplicado no
 *  Winthor" do protótipo do Diretor NÃO existe aqui (ver cabeçalho do
 *  arquivo): a aplicação é medida, não clicada. */
export const ROTULO_AVANCAR = { Rascunho: "Marcar enviado" };
export const ROTULO_VOLTAR = { Enviado: "Voltar para rascunho" };

export const podeAvancar = (status) => status in ROTULO_AVANCAR;
export const podeVoltar = (status) => status in ROTULO_VOLTAR;

/* ------------------------------------------------------- situação do item --- */

/** No protótipo do Diretor, "aplicado" era um botão de confiança: alguém
 *  clica e o sistema acredita. Aqui `situacao` já chega calculada da API
 *  (`item.situacao`, `app/api/contrato.py:item_lote_preco`) — a tela só
 *  traduz a palavra em cor e rótulo, nunca reclassifica por conta própria.
 *
 *  Quatro valores (`app/servicos/lote_preco.py:_situacao_item`):
 *  - aplicado   — os canais decididos já estão no banco (verde)
 *  - pendente   — nenhum canal decidido chegou ainda (cinza neutro, espera)
 *  - parcial    — um canal aplicado e o outro ainda pendente; NÃO é
 *    divergência (âmbar — atenção, mistura sem alarme, distinto do cinza de
 *    "nada aconteceu" e do vermelho de "aconteceu errado")
 *  - divergente — o banco foi para um terceiro valor que ninguém pediu
 *    (vermelho, alarme de verdade) */
export const COR_SITUACAO = {
  aplicado: "#15803D",
  pendente: "#6B7280",
  parcial: "#B98A2E",
  divergente: "#DE434B",
};

export const ROTULO_SITUACAO = {
  aplicado: "Aplicado",
  pendente: "Pendente",
  parcial: "Parcial",
  divergente: "Divergente",
};

/* ------------------------------------------------------- confirmação de POST --- */

/** Texto da confirmação depois de `POST /lotes-preco`, usado tanto pelo rodapé
 *  da Precificação quanto pelo botão de `DecisaoSKU` (PROMPT_ETAPA_12 §4.2, o
 *  ajuste de 10/09/2026: um SKU decidido ali também cria/soma a um lote — não
 *  fica só na tela, o beco sem saída de que o Diretor reclamou).
 *
 * `loteReaproveitado` só chega preenchido quando a chamada foi feita SEM
 * `idLote` (o servidor decidiu, sozinho e dentro da transação, entre abrir um
 * documento novo ou reaproveitar o Rascunho já aberto do usuário —
 * `app/servicos/lote_preco.py`, `app/api/contrato.py:lote_preco`). Ausente ou
 * `null` (ex.: uma fatia intermediária de um lote grande, que já sabe que está
 * ACRESCENTANDO ao id devolvido pela fatia anterior — não é o servidor quem
 * fica em silêncio, é quem chama que não perguntou) cai no terceiro caso:
 * mensagem neutra, que não afirma "criado" nem "acrescentado" porque a tela
 * não sabe qual dos dois aconteceu. */
export function textoConfirmacaoLote(qtd, idLote, loteReaproveitado) {
  const s = qtd > 1 ? "s" : "";
  if (loteReaproveitado === true) {
    return `${numero(qtd)} preço${s} acrescentado${s} ao lote #${idLote}, que já estava em Rascunho.`;
  }
  if (loteReaproveitado === false) {
    return `${numero(qtd)} preço${s} definido${s} — lote #${idLote} criado em Rascunho.`;
  }
  return `${numero(qtd)} preço${s} definido${s} no lote #${idLote}.`;
}

/** "conferido com os dados de hoje às 06:05" (ou "de 09/09 às 06:05", se mais
 *  velho que ontem) — a idade da conferência de aplicação, formada com o
 *  MESMO formatador que o carimbo do cabeçalho usa para o mesmo carimbo de
 *  carga (`dataHoraCarga`, em `formato.js`) — `GET /api/atualizacao`, embutido
 *  em toda resposta de lote pela rota. Sem esta frase, um preço aplicado às
 *  10h aparece como pendente às 11h e o indicador perde a credibilidade em uma
 *  semana (PROMPT_ETAPA_12 §4.5).
 *
 *  Ao contrário do cabeçalho, aqui não precisa de "em" antes de data
 *  explícita: o "de" desta frase já faz esse papel ("dados de 09/09 às
 *  06:05"), por isso usamos sempre `info.texto`, nunca `info.relativo`. */
export function textoConferencia(atualizacao) {
  const info = dataHoraCarga(atualizacao?.fim);
  if (!info) return null;
  return `conferido com os dados de ${info.texto}`;
}
