const NAVY = "#375DA8";

const OPCOES = [
  { valor: "", rotulo: "Todos" },
  { valor: "com", rotulo: "Com estoque" },
  { valor: "sem", rotulo: "Sem estoque" },
];

/* Filtro "com/sem estoque" (Etapa 15, ponto 4) — compartilhado por Pedidos.jsx
 * e Precificacao.jsx, as duas telas que chamam GET /api/produtos. Molde:
 * FiltroUltimaEntrada.jsx e o grupo "Status" das duas telas (mesmo padrão
 * visual de botões em pílula).
 *
 * `valor` é "" (todos, ausente na chamada à API), "com" ou "sem" — nunca um
 * terceiro estado: o corte no servidor é `EST_DISP > 0` / `<= 0`, uma
 * partição do universo, e a tela não inventa recorte que o servidor não sabe
 * fazer.
 */
export default function FiltroEstoque({ valor, aoTrocar }) {
  return (
    <div>
      <div className="mb-1 text-xs text-gray-500">Estoque</div>
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
