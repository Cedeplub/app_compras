import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, Loader2, Percent } from "lucide-react";
import { api } from "../api/cliente.js";
import { numero, paraCampoPreco, parseNumeroPreco } from "../formato.js";
import { precoDeMargem, precoDeMKP } from "../precoEditavel.js";

/* Aplicar margem ou MKP a TODOS os itens do filtro — item 1c do Diretor de
 * Compras, 09/10/2026:
 *
 *   "opção de aplicar margem ou MKP para todos os itens do filtro atual
 *    (ex.: departamento + Ativo), preenchendo a sugestão de alteração de
 *    todos, em todas as páginas e não só na tela. Mostrar quantos itens serão
 *    alterados antes de aplicar, pular itens sem custo e manter como rascunho
 *    até 'Definir preços'."
 *
 * ── O que isto NÃO faz, e é o mais importante ────────────────────────────────
 * NÃO GRAVA NADA. Preenche os mesmos mapas `precosAT`/`precosVAR` que a
 * digitação manual preenche, como RASCUNHO. A gravação continua sendo
 * "Definir preços", com a mesma confirmação (inclusive o aviso de preço
 * abaixo do custo) e o mesmo lote. Quem aplicar em lote e fechar a aba sem
 * definir não mudou preço nenhum.
 *
 * ── Por que a contagem vem antes ─────────────────────────────────────────────
 * Um filtro amplo alcança os 4.552 ativos. O Diretor não pediu um teto, pediu
 * para VER quantos serão alterados — e é melhor assim: um corte arbitrário
 * aplicaria em parte do filtro e esconderia o resto, que é pior do que não
 * aplicar. Por isso a busca acontece ao ABRIR o diálogo, e a contagem
 * recalcula a cada tecla, sem ir ao servidor de novo.
 *
 * ── Por que o servidor resolve o cenário ─────────────────────────────────────
 * `custoAT`/`icmsEfAT` já vêm resolvidos por praça (`contrato.base_precificacao`,
 * que replica `cenarioVisivel`). Resolver de novo aqui seria uma segunda
 * implementação da mesma regra — e é assim que nasce uma tela que precifica
 * com um custo e exibe outro (`precificacao.js:52-57`).
 */

const NAVY = "#375DA8";

export default function AplicarEmLote({ filtros, parametros, aoAplicar, aoFechar }) {
  const [base, setBase] = useState(null);
  const [erro, setErro] = useState(null);
  const [tipo, setTipo] = useState("margem");   // "margem" | "mkp"
  const [canal, setCanal] = useState("atacado"); // "atacado" | "varejo" | "ambos"
  const [texto, setTexto] = useState("");

  // Uma busca só, ao abrir. A partir dela tudo é aritmética local: digitar no
  // campo não volta ao servidor, senão cada tecla dispararia uma varredura do
  // filtro inteiro.
  useEffect(() => {
    let vivo = true;
    api.basePrecificacao(filtros)
      .then((r) => { if (vivo) setBase(r); })
      .catch((e) => { if (vivo) setErro(e.detalhe ?? "Falha ao carregar o filtro."); });
    return () => { vivo = false; };
    // `filtros` é recriado a cada render do pai; a chave é o conteúdo, e o
    // diálogo só existe enquanto estiver aberto — reabrir é que busca de novo.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const valor = parseNumeroPreco(texto);
  const valorValido = Number.isFinite(valor) && valor > 0;

  /* O resultado da aplicação, por item: o preço de cada praça ou `null`.
   *
   * `null` acontece por dois motivos distintos, e a contagem os separa porque
   * dizem coisas diferentes para quem decide:
   *   * SEM CUSTO — o item não tem como ser precificado (51 ativos hoje no
   *     cenário ST s/Valor). É o "pular itens sem custo" do pedido;
   *   * ACIMA DO TETO — a margem pedida não existe naquele cenário. Não é
   *     defeito do item, é do valor digitado, e some ao baixar a margem. */
  const resultado = useMemo(() => {
    if (!base || !valorValido || !parametros) return null;
    const comissao = parametros.comissao;
    const linhas = [];
    let semCusto = 0;
    let acimaDoTeto = 0;

    for (const it of base.itens) {
      const precos = {};
      let algum = false;
      let faltouCusto = false;
      let passouDoTeto = false;

      for (const [praca, custo, icmsEf] of [
        ["atacado", it.custoAT, it.icmsEfAT],
        ["varejo", it.custoVAR, it.icmsEfVAR],
      ]) {
        if (canal !== "ambos" && canal !== praca) continue;
        if (custo == null || custo <= 0) { faltouCusto = true; continue; }
        const preco = tipo === "margem"
          ? precoDeMargem(valor / 100, custo,
                          { pisCofins: it.pisCofinsEfetivo, comissao, icmsEf })
          : precoDeMKP(valor, custo);
        if (preco == null) { passouDoTeto = true; continue; }
        precos[praca] = { preco, custo };
        algum = true;
      }

      if (algum) linhas.push({ codigo: it.codigo, precos, item: it });
      else if (faltouCusto) semCusto += 1;
      else if (passouDoTeto) acimaDoTeto += 1;
    }
    return { linhas, semCusto, acimaDoTeto };
  }, [base, valorValido, valor, tipo, canal, parametros]);

  const carregando = base == null && erro == null;

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 px-4"
         role="dialog" aria-modal="true" aria-labelledby="titulo-lote-margem">
      <div className="w-full max-w-md rounded-xl bg-white p-5 shadow-lg">
        <div className="flex items-start gap-2">
          <Percent size={18} className="mt-0.5 shrink-0" style={{ color: NAVY }} aria-hidden="true" />
          <div className="min-w-0 flex-1">
            <h2 id="titulo-lote-margem" className="font-semibold text-gray-900">
              Aplicar a todos os itens do filtro
            </h2>
            <p className="mt-1 text-sm text-gray-600">
              Preenche o campo de preço de cada produto do filtro atual — em todas as
              páginas, não só nesta. Fica como rascunho: nada é gravado até você
              clicar em “Definir preços”.
            </p>

            <div className="mt-3 flex flex-wrap items-center gap-2">
              <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
                {[["margem", "Margem %"], ["mkp", "MKP"]].map(([id, rot]) => (
                  <button key={id} type="button" aria-pressed={tipo === id}
                          onClick={() => setTipo(id)}
                          style={tipo === id ? { background: NAVY, color: "white" } : {}}
                          className="rounded-md px-3 py-1.5 text-xs font-medium text-gray-500">
                    {rot}
                  </button>
                ))}
              </div>
              <div className="flex gap-1 rounded-lg bg-gray-100 p-0.5">
                {[["atacado", "Atacado"], ["varejo", "Varejo"], ["ambos", "Ambos"]].map(([id, rot]) => (
                  <button key={id} type="button" aria-pressed={canal === id}
                          onClick={() => setCanal(id)}
                          style={canal === id ? { background: NAVY, color: "white" } : {}}
                          className="rounded-md px-3 py-1.5 text-xs font-medium text-gray-500">
                    {rot}
                  </button>
                ))}
              </div>
              <input type="text" inputMode="decimal" value={texto} autoFocus
                     onChange={(e) => setTexto(e.target.value)}
                     aria-label={tipo === "margem" ? "Margem alvo, em %" : "MKP alvo"}
                     placeholder={tipo === "margem" ? "20" : "1,91"}
                     className="num w-20 rounded-md border border-gray-300 px-2 py-1.5 text-center text-sm" />
              <span className="text-xs text-gray-400">{tipo === "margem" ? "%" : "x"}</span>
            </div>

            <div className="mt-3 rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-600">
              {carregando && (
                <span className="flex items-center gap-1.5">
                  <Loader2 size={12} className="animate-spin" aria-hidden="true" />
                  Carregando o filtro…
                </span>
              )}
              {erro && <span className="text-red-700">{erro}</span>}
              {base && !valorValido && (
                <>O filtro tem <span className="num font-semibold">{numero(base.total)}</span>{" "}
                produto(s). Digite {tipo === "margem" ? "a margem" : "o MKP"} para ver quantos
                serão alterados.</>
              )}
              {base && valorValido && resultado && (
                <>
                  <div>
                    <span className="num font-semibold text-gray-900">
                      {numero(resultado.linhas.length)}
                    </span>{" "}
                    produto(s) serão preenchidos, de {numero(base.total)} no filtro.
                  </div>
                  {resultado.semCusto > 0 && (
                    <div className="mt-0.5 text-gray-500">
                      {numero(resultado.semCusto)} pulado(s) por não ter custo no cenário.
                    </div>
                  )}
                  {resultado.acimaDoTeto > 0 && (
                    <div className="mt-0.5 text-red-700">
                      {numero(resultado.acimaDoTeto)} pulado(s): a margem pedida passa do teto
                      do cenário deles.
                    </div>
                  )}
                </>
              )}
            </div>

            {base && valorValido && resultado?.linhas.length > 0 && (
              <p className="mt-2 flex items-start gap-1.5 text-2xs text-gray-500">
                <AlertTriangle size={12} className="mt-0.5 shrink-0" aria-hidden="true" />
                Isto substitui o que já estiver digitado nesses produtos.
              </p>
            )}
          </div>
        </div>

        <div className="mt-4 flex justify-end gap-2">
          <button type="button" onClick={aoFechar}
                  className="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700">
            Cancelar
          </button>
          <button type="button"
                  disabled={!resultado || resultado.linhas.length === 0}
                  onClick={() => aoAplicar(resultado.linhas, canal)}
                  className="rounded-md px-3 py-1.5 text-sm font-semibold text-white disabled:opacity-50"
                  style={{ background: NAVY }}>
            Preencher {resultado ? numero(resultado.linhas.length) : ""} preço(s)
          </button>
        </div>
      </div>
    </div>
  );
}

/** O par de `AplicarEmLote`: transforma o resultado nos mapas de preço.
 *
 *  Fica aqui, ao lado de quem produz o resultado, para a forma de
 *  `{valor, decidido, custo}` ser escrita num lugar só — ela é a mesma dos
 *  setters de `Precificacao.jsx` e um desencontro entre as duas faria
 *  `alteracoesLote` deixar de reconhecer o que o lote preencheu. */
export function aplicarNosMapas(linhas, canal, setPrecosAT, setPrecosVAR) {
  if (canal !== "varejo") {
    setPrecosAT((mapa) => {
      const novo = { ...mapa };
      for (const l of linhas) {
        const p = l.precos.atacado;
        if (p) {
          novo[l.codigo] = { valor: paraCampoPreco(p.preco),
                             decidido: l.item.precoDecididoAtacadoAV, custo: p.custo };
        }
      }
      return novo;
    });
  }
  if (canal !== "atacado") {
    setPrecosVAR((mapa) => {
      const novo = { ...mapa };
      for (const l of linhas) {
        const p = l.precos.varejo;
        if (p) {
          novo[l.codigo] = { valor: paraCampoPreco(p.preco),
                             decidido: l.item.precoDecididoVarejoAV, custo: p.custo };
        }
      }
      return novo;
    });
  }
}
