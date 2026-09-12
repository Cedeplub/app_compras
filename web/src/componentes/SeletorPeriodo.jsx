import { ChevronLeft, ChevronRight } from "lucide-react";
import { GRANULARIDADES, rotuloPeriodo } from "../periodo.js";

/* Seletor de período — porte de `SeletorPeriodo` (.jsx linha 380).
 *
 * Diferença de fundo: no protótipo ele é decorativo. Navega no tempo e o número
 * não muda, porque os arrays são estáticos (§8). Aqui cada troca recalcula o
 * intervalo e refaz a consulta.
 *
 * O botão "avançar" fica desabilitado no período corrente: não há dado no
 * futuro, e deixar clicar levaria a uma tela vazia que parece defeito.
 */

const NAVY = "#375DA8";

export default function SeletorPeriodo({ granularidade, setGranularidade,
                                         offset, setOffset, referencia }) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
        {GRANULARIDADES.map((g) => (
          <button key={g} type="button" aria-pressed={granularidade === g}
                  onClick={() => { setGranularidade(g); setOffset(0); }}
                  style={granularidade === g ? { background: NAVY, color: "white" } : {}}
                  className="rounded-md px-3 py-1.5 text-xs font-medium text-gray-500">
            {g}
          </button>
        ))}
      </div>

      <div className="flex items-center gap-1">
        <button type="button" onClick={() => setOffset(offset - 1)}
                aria-label="Período anterior"
                className="rounded-md border border-gray-300 p-1.5 text-gray-600">
          <ChevronLeft size={14} aria-hidden="true" />
        </button>
        <span className="min-w-[130px] text-center text-sm font-semibold text-gray-800">
          {referencia ? rotuloPeriodo(granularidade, offset, referencia) : "—"}
        </span>
        <button type="button" onClick={() => setOffset(offset + 1)} disabled={offset >= 0}
                aria-label="Próximo período"
                className="rounded-md border border-gray-300 p-1.5 text-gray-600 disabled:opacity-30">
          <ChevronRight size={14} aria-hidden="true" />
        </button>
      </div>
    </div>
  );
}
