import { useState } from "react";
import { diasAntes } from "../periodo.js";

const NAVY = "#375DA8";
const PRESETS = [30, 60, 90];

/* Filtro por data da última entrada (item 1 do Diretor, 08/09/2026).
 * Novos em GET /api/produtos: `dtUltEntDe`/`dtUltEntAte`, ambos opcionais e
 * independentes, YYYY-MM-DD.
 *
 * O caso de uso pedido foi "filtrar por data da última entrada", mas o que o
 * Diretor faz com isso é achar o que NÃO entra há muito tempo — então o
 * controle principal é um atalho relativo ("30+/60+/90+ dias sem entrada"),
 * que mexe só em `dtUltEntAte` (deixa `dtUltEntDe` vazio: sem limite
 * inferior, é "há pelo menos N dias", não uma janela fechada). Dois campos de
 * data crus, atrás de "Personalizado", cobrem o caso residual de intervalo
 * exato — sem competir em peso visual com o atalho que resolve 90% do uso.
 *
 * "Hoje" é a DATA DO DADO (`parametros.data_referencia`), igual ao resto do
 * app: os atalhos têm de contar a partir do dia que os números realmente
 * cobrem, não do relógio de quem está olhando a tela.
 */
export default function FiltroUltimaEntrada({
  referencia, dtUltEntDe, setDtUltEntDe, dtUltEntAte, setDtUltEntAte,
}) {
  const [aberto, setAberto] = useState(false);
  const ativo = Boolean(dtUltEntDe || dtUltEntAte);
  const presetAtivo = referencia && !dtUltEntDe
    ? PRESETS.find((n) => dtUltEntAte === diasAntes(referencia, n))
    : undefined;

  function aplicarPreset(n) {
    if (!referencia) return;
    setDtUltEntDe("");
    setDtUltEntAte(diasAntes(referencia, n));
  }

  function limpar() {
    setDtUltEntDe("");
    setDtUltEntAte("");
    setAberto(false);
  }

  return (
    <div>
      <div className="mb-1 text-xs text-gray-500">Última entrada</div>
      <div className="flex flex-wrap items-center gap-1.5">
        <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
          <button type="button" aria-pressed={!ativo} onClick={limpar}
                  style={!ativo ? { background: NAVY, color: "white" } : {}}
                  className="rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500">
            Todos
          </button>
          {PRESETS.map((n) => (
            <button key={n} type="button" aria-pressed={presetAtivo === n}
                    disabled={!referencia} onClick={() => aplicarPreset(n)}
                    style={presetAtivo === n ? { background: NAVY, color: "white" } : {}}
                    className="rounded-md px-2.5 py-1.5 text-xs font-medium text-gray-500 disabled:opacity-40">
              {n}+ dias
            </button>
          ))}
        </div>
        <button type="button" onClick={() => setAberto((a) => !a)}
                aria-expanded={aberto}
                className="text-xs font-medium text-gray-400 underline underline-offset-2">
          Personalizado
        </button>
      </div>
      {aberto && (
        <div className="mt-1.5 flex items-center gap-1.5">
          <input type="date" value={dtUltEntDe} onChange={(e) => setDtUltEntDe(e.target.value)}
                 aria-label="Última entrada, a partir de"
                 className="rounded-lg border border-gray-200 px-2 py-1 text-xs text-gray-700" />
          <span className="text-xs text-gray-400">até</span>
          <input type="date" value={dtUltEntAte} onChange={(e) => setDtUltEntAte(e.target.value)}
                 aria-label="Última entrada, até"
                 className="rounded-lg border border-gray-200 px-2 py-1 text-xs text-gray-700" />
        </div>
      )}
    </div>
  );
}

/* Produto com DT_ULT_ENT nulo (nunca teve entrada) some de QUALQUER filtro por
 * intervalo, mesmo o mais largo — matematicamente correto (nulo não cai
 * dentro de intervalo nenhum), mas é exatamente o tipo de coisa que faz
 * alguém achar que "sumiu produto".
 *
 * Cheguei a escrever esta linha com um número fixo ("423 dos 8.841 SKUs") —
 * medido uma vez no banco. Errado por dois motivos: o número muda sozinho (o
 * catálogo cresce todo dia, então envelhece sem aviso) e ele aparece logo
 * abaixo do filtro de Departamento, onde a leitura natural é "423 sumiram
 * deste recorte" — falso, é uma contagem global do catálogo inteiro, não do
 * filtro atual. A API não tem um parâmetro "só quem não tem entrada" (só
 * `>=`/`<`, que nulo nunca satisfaz), então uma contagem por-filtro exigiria
 * rota nova no servidor.
 *
 * Preferi resolver sem depender de número nenhum: a frase abaixo é
 * inequivocamente global ("em nenhum filtro por data", não "neste recorte") e
 * não envelhece, porque não promete uma contagem que ninguém está mantendo
 * atualizada. */
export function AvisoSemEntrada() {
  return (
    <p className="mt-1 text-2xs text-gray-400">
      Produtos que nunca tiveram entrada registrada não aparecem em nenhum
      filtro por data de última entrada, inclusive este — não é um efeito do
      departamento ou dos demais filtros acima.
    </p>
  );
}
