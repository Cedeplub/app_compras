const NAVY = "#375DA8";

const OPCOES = [
  { valor: "S", rotulo: "Revenda" },
  { valor: "N", rotulo: "Não revenda" },
  { valor: "", rotulo: "Todos" },
];

/* Filtro "é de revenda?" — item 1.17 do Diretor de Compras, 09/10/2026:
 * "item que não é de venda na Precificação: 6326 display".
 *
 * ⚠ NASCE EM "Revenda", e é o único filtro desta tela que não nasce em
 * "Todos". A Precificação existe para DECIDIR PREÇO, e material de apoio não
 * tem preço a decidir — aparecer ali é ruído em toda página. Por isso
 * "Revenda" vem primeiro na lista e "Todos" por último: a ordem das pílulas
 * diz qual é o estado normal.
 *
 * Esconde 67 dos 4.553 ativos (medido em 09/10/2026), então a contagem da tela
 * passa a 4.486. "Todos" devolve os 4.553, sem mexer em código — era a
 * condição para o filtro poder nascer ligado.
 *
 * ── O que este filtro NÃO resolve, e é o essencial ──────────────────────────
 * Ele lê PCPRODUT.REVENDA, o único campo do cadastro que separa mercadoria de
 * material de apoio. O 6326, que motivou o item, NÃO está marcado: tem
 * TIPOMERC 'L', REVENDA 'S' e TIPOPROD 1 — idênticos ao 2720 e ao 1689, que
 * são produtos de verdade. O cadastro não o distingue de nada.
 *
 * Decidido com o usuário em 09/10/2026: o painel filtra o que o cadastro
 * marca, e marcar o 6326 é do cadastro. Classificar aqui por descrição
 * ("DISPLAY", "EXPOSITOR") seria uma segunda verdade sobre o que é vendável,
 * mantida por ninguém e errando em silêncio no primeiro produto que tivesse
 * "display" no nome e fosse mercadoria.
 */
export default function FiltroRevenda({ valor, aoTrocar }) {
  return (
    <div>
      <div className="mb-1 text-xs text-gray-500">Revenda</div>
      <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
        {OPCOES.map((o) => (
          <button key={o.valor} type="button" aria-pressed={valor === o.valor}
                  onClick={() => aoTrocar(o.valor)}
                  style={valor === o.valor ? { background: NAVY, color: "white" } : {}}
                  className="whitespace-nowrap rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500">
            {o.rotulo}
          </button>
        ))}
      </div>
    </div>
  );
}
