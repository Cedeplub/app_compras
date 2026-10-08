const NAVY = "#375DA8";

const OPCOES = [
  { valor: "", rotulo: "Todos" },
  { valor: "com", rotulo: "Com preço" },
  { valor: "sem", rotulo: "Sem preço" },
];

/* Filtro "com/sem preço" (Etapa 19, item 3) — só em `Precificacao.jsx`, ao
 * lado de `FiltroEstoque`. Cópia estrutural dele (mesmo molde de botões em
 * pílula); `Pedidos.jsx` não recebe este filtro — não foi pedido (§5.2 do
 * prompt).
 *
 * `valor` é "" (todos, ausente na chamada à API), "com" ou "sem" — nunca um
 * terceiro estado. "Sem preço" é `PV_ATACADO = 0` (nunca nulo nos 8.944 SKUs
 * medidos) — o corte é só pelo ATACADO: entre os ativos, "sem atacado" e
 * "sem varejo" são o MESMO conjunto de 205 SKUs (medido em 08/10/2026), então
 * um critério composto por canal mudaria zero linhas e só acrescentaria
 * complexidade (§5.1 do prompt).
 */
export default function FiltroPreco({ valor, aoTrocar }) {
  return (
    <div>
      <div className="mb-1 text-xs text-gray-500">Preço</div>
      <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
        {OPCOES.map((o) => (
          <button key={o.valor} type="button" aria-pressed={valor === o.valor}
                  onClick={() => aoTrocar(o.valor)}
                  style={valor === o.valor ? { background: NAVY, color: "white" } : {}}
                  className="rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500">
            {o.rotulo}
          </button>
        ))}
      </div>
    </div>
  );
}
