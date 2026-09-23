import { useEffect, useState } from "react";

/* Sobrevivência de estado de TELA entre ida-e-volta de navegação (também
 * cobre F5, porque é sessionStorage) — molde: `contexto/carrinho.jsx`, as
 * mesmas duas decisões de desenho valem aqui e não se rediscutem:
 *
 * 1. `sessionStorage`, não `localStorage`. Filtro de tela é trabalho em curso
 *    de UMA sessão, não preferência permanente — reabrir o app amanhã não
 *    deveria reaplicar sozinho o filtro de ontem. `sessionStorage` também é
 *    POR ABA: abrir o app numa aba nova não herda nem atropela o que está
 *    sendo filtrado/editado na aba onde a pessoa já está trabalhando.
 * 2. Guarda só o que a PESSOA escolheu ou digitou — filtro, página, texto de
 *    busca, valor de um campo em edição. NUNCA dado vindo da API (preço
 *    decidido, custo, margem, cobertura): esse envelhece a cada `dbt run`, e
 *    persistir um número que já não existe mais é decidir sobre dado velho.
 *    Cada tela que usa este hook para além de filtro simples (ex.: os preços
 *    digitados de `Precificacao.jsx`) projeta primeiro só o campo digitado
 *    antes de guardar — este arquivo não sabe fazer essa distinção sozinho,
 *    porque ela depende do formato de cada tela.
 *
 * Motivo do pedido (Diretor): o botão "Voltar" de uma tela de detalhe passou
 * a usar `navegar(-1)` (a página ANTERIOR de verdade, ver `LotePrecoDetalhe.jsx`
 * e `PedidoDetalhe.jsx`) — mas isso só devolve algo útil se a tela de origem
 * ainda tiver o filtro/edição que a pessoa deixou, porque ela REMONTA do
 * zero ao voltar (o React desmonta a tela ao navegar para longe dela). Sem
 * este hook, "voltar" devolvia a pessoa para a lista, mas com todo filtro
 * apagado — o mesmo descarte silencioso que este projeto vem corrigindo tela
 * por tela desde a Etapa 12/13 (ver comentário de `carrinho.jsx`).
 */

function lerStorage(chave, valorPadrao, mesclarCampos) {
  try {
    const bruto = window.sessionStorage.getItem(chave);
    if (!bruto) return valorPadrao;
    const json = JSON.parse(bruto);
    // Validação mínima: só aceita objeto plano (não array, não primitivo) —
    // lixo de uma versão anterior da tela, ou um JSON truncado, cai no
    // padrão. Quando o padrão também é um objeto plano, o resultado é
    // MESCLADO campo a campo: uma chave que falta no storage (tela nova
    // adicionou um filtro) fica com o valor padrão em vez de `undefined`, e
    // uma chave que sobra no storage (versão antiga da tela tinha um filtro
    // que esta não tem mais) é descartada — nunca vaza para o estado da tela.
    if (!json || typeof json !== "object" || Array.isArray(json)) return valorPadrao;
    // ⚠ A mesclagem SÓ vale para estado de FORMA FIXA (um objeto de filtros,
    // cujas chaves são conhecidas de antemão). Para um DICIONÁRIO — chaves
    // dinâmicas, como {códigoDoProduto: preço digitado} — ela apagaria tudo:
    // as chaves vêm de `valorPadrao`, que num dicionário é `{}`, então o laço
    // não copiaria nada e o retorno seria `{}`. Foi exatamente esse o defeito
    // relatado logo depois da Etapa 16: os filtros voltavam ao usar "Voltar",
    // e os preços digitados não. Por isso a forma é EXPLÍCITA no chamador, e
    // não inferida daqui — inferir foi o que criou o defeito.
    if (!mesclarCampos) return json;
    if (valorPadrao && typeof valorPadrao === "object" && !Array.isArray(valorPadrao)) {
      const mesclado = { ...valorPadrao };
      for (const chaveCampo of Object.keys(valorPadrao)) {
        if (chaveCampo in json) mesclado[chaveCampo] = json[chaveCampo];
      }
      return mesclado;
    }
    return json;
  } catch {
    // `sessionStorage` pode não existir (janela anônima, site data
    // bloqueado) ou o `JSON.parse` pode falhar (truncado) — os dois casos
    // caem no mesmo resultado: começa do padrão, nunca derruba a tela.
    return valorPadrao;
  }
}

function escreverStorage(chave, valor) {
  try {
    window.sessionStorage.setItem(chave, JSON.stringify(valor));
  } catch {
    // Sem storage disponível, o estado continua funcionando em memória pelo
    // resto da aba — não é motivo para quebrar a tela.
  }
}

/**
 * Estado de tela persistido em `sessionStorage`, com a mesma API de
 * `useState`. Uma chamada por PEDAÇO de estado que precise sobreviver à
 * navegação — normalmente um objeto só, com todos os filtros de uma tela.
 *
 * @param {string} chave chave de `sessionStorage`, já versionada pelo
 *   chamador (ex.: `"app_compras_filtros_precificacao_v1"`) — a versão no
 *   nome é o que permite trocar a FORMA do estado numa etapa futura sem
 *   herdar lixo da forma antiga: ela simplesmente não bate mais na chave, e
 *   o padrão novo assume.
 * @param {*} valorPadrao valor de partida, e o que volta sempre que o
 *   storage estiver vazio, corrompido, ou não bater na forma esperada.
 * @param {boolean} [mesclarCampos=true] `true` para estado de FORMA FIXA (um
 *   objeto de filtros com chaves conhecidas): o que voltar do storage é
 *   mesclado campo a campo com o padrão, então filtro novo nasce no padrão e
 *   filtro que não existe mais é descartado. `false` para DICIONÁRIO de
 *   chaves dinâmicas (ex.: {códigoDoProduto: valor digitado}), onde mesclar
 *   com um padrão `{}` apagaria todo o conteúdo — ver o comentário em
 *   `lerStorage`.
 */
export function useEstadoPersistente(chave, valorPadrao, mesclarCampos = true) {
  const [valor, setValor] = useState(() => lerStorage(chave, valorPadrao, mesclarCampos));
  useEffect(() => { escreverStorage(chave, valor); }, [chave, valor]);
  return [valor, setValor];
}
