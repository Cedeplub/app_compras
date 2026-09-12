import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import { api } from "../api/cliente.js";

/* Estado da carga do dbt (carimbo de frescor + botão "Atualizar"), visível a
 * qualquer tela através do cabeçalho e usado pelas telas de leitura para
 * rebuscar sozinhas quando uma carga termina.
 *
 * Só existe montado dentro da sessão: `App.jsx` só renderiza este provider
 * (junto do Cabeçalho e das rotas) depois que `usuario` está setado — antes
 * disso a tela de Login nem monta a árvore. Não há prop "habilitado" porque a
 * própria posição no JSX já resolve isso.
 */

const AtualizacaoContexto = createContext(null);

// CONCLUIDO_COM_AVISO é sucesso — o dado está fresco, só houve aviso no
// `dbt test`. A diferença é só de `title` na tela, nunca de comportamento.
const STATUS_SUCESSO = new Set(["CONCLUIDO", "CONCLUIDO_COM_AVISO"]);

// Depois do clique, quanto tempo esperamos o GET confirmar (`emAndamento:
// true`, ou uma execução concluída mais nova que o clique) antes de desistir
// do estado otimista. O `Popen` no backend só faz fork-e-retorna: o processo
// filho ainda precisa importar `oracledb`, subir o modo thick e abrir o pool
// antes de gravar a linha EM_ANDAMENTO — isso já levou vários segundos em
// medição. 90s é folga generosa sobre isso; se nem assim confirmar, o
// processo provavelmente morreu ao nascer.
const LIMITE_CONFIRMACAO_MS = 90_000;

export function AtualizacaoProvider({ children }) {
  const [estado, setEstado] = useState(null);
  const [carregando, setCarregando] = useState(true);
  const [erro, setErro] = useState(null);
  const [versaoDados, setVersaoDados] = useState(0);

  // Estado OTIMISTA: setado no instante em que o POST responde 202, antes de
  // qualquer GET confirmar. Sem ele, o intervalo entre o clique e o filho
  // gravar EM_ANDAMENTO (importar oracledb, abrir o pool...) aparece como
  // botão habilitado — a pessoa acha que não funcionou e clica de novo, e o
  // segundo clique dispara um SEGUNDO build de verdade (a trava de arquivo do
  // `atualizar.py` impediria o desastre, mas é a última linha de defesa, não
  // a primeira).
  const [disparando, setDisparando] = useState(false);
  const [avisoConfirmacao, setAvisoConfirmacao] = useState(null);

  // Momento do clique (epoch ms) — usado tanto para comparar com `fim` de uma
  // execução (uma carga tão rápida que terminou entre um poll e outro, sem
  // nunca vermos `emAndamento: true` no meio) quanto para o timeout de 90s.
  // Não é estado: mudar isso não deve re-renderizar sozinho.
  const disparadoEmRef = useRef(null);
  const timeoutDisparoRef = useRef(null);

  // Não é estado: só serve para detectar a TRANSIÇÃO emAndamento true→false
  // entre duas consultas. Em `state` faria re-render à toa a cada poll.
  const emAndamentoAntes = useRef(false);

  const limparOtimista = useCallback(() => {
    disparadoEmRef.current = null;
    setDisparando(false);
    if (timeoutDisparoRef.current) {
      clearTimeout(timeoutDisparoRef.current);
      timeoutDisparoRef.current = null;
    }
  }, []);

  const consultar = useCallback(async () => {
    try {
      const novo = await api.atualizacao();

      if (disparadoEmRef.current) {
        const fimNovoMs = novo.fim ? new Date(novo.fim).getTime() : null;
        const confirmouEmAndamento = novo.emAndamento;
        const confirmouConcluida = fimNovoMs !== null && fimNovoMs > disparadoEmRef.current;

        if (confirmouEmAndamento || confirmouConcluida) {
          limparOtimista();
          if (confirmouConcluida && !confirmouEmAndamento && STATUS_SUCESSO.has(novo.status)) {
            // O filho subiu, rodou e terminou entre um poll e outro — rápido
            // demais para o poll flagrar `EM_ANDAMENTO` no meio. Ainda assim é
            // uma carga nova de verdade, então os parâmetros do modelo podem
            // ter mudado; se não fosse por este ramo, a transição normal (logo
            // abaixo) nunca veria o `true→false` e a rebusca das telas não
            // dispararia.
            api.limparCacheParametros();
            setVersaoDados((v) => v + 1);
          }
        }
        // Nem confirmou, nem passou do timeout ainda: continua otimista —
        // o `setTimeout` armado em `atualizar()` cuida do abandono em 90s.
      }

      if (emAndamentoAntes.current && !novo.emAndamento && STATUS_SUCESSO.has(novo.status)) {
        // A carga que estava rodando acabou de terminar bem: os parâmetros do
        // modelo (FATOR_PRAZO, DATA_REFERENCIA...) podem ter mudado, e o cache
        // de `api.parametros()` não tem como saber sozinho. `versaoDados` é o
        // sinal para as telas de leitura rebuscarem.
        api.limparCacheParametros();
        setVersaoDados((v) => v + 1);
      }
      emAndamentoAntes.current = novo.emAndamento;
      setEstado(novo);
      setErro(null);
    } catch (e) {
      // 401 já dispara SESSAO_EXPIROU em `cliente.js` e leva ao login; aqui só
      // evita que o carimbo fique preso em "carregando" para sempre.
      //
      // Guardamos `status` junto da mensagem (não só a string) porque quem lê
      // isso — `Cabecalho.jsx` — precisa separar "espere um pouco" (409/429)
      // de "algo quebrou" (404/500/rede) para decidir se o aviso é informativo
      // ou um alarme. Perder o `status` aqui já causou o defeito relatado:
      // sem ele, a única superfície do erro virava `title` de tooltip.
      setErro({ status: e.status, mensagem: e.detalhe });
    } finally {
      setCarregando(false);
    }
  }, [limparOtimista]);

  // Consulta inicial.
  useEffect(() => { consultar(); }, [consultar]);

  // Enquanto uma carga está em andamento — confirmada pelo servidor OU ainda
  // só otimista — repete a cada 10s; deixou de estar, para. O provider vive a
  // sessão inteira — sem este cleanup o intervalo sobreviveria a navegações e
  // se multiplicaria.
  useEffect(() => {
    if (!estado?.emAndamento && !disparando) return undefined;
    const id = setInterval(consultar, 10_000);
    return () => clearInterval(id);
  }, [estado?.emAndamento, disparando, consultar]);

  // Ao voltar o foco da janela: outra aba pode ter disparado a atualização, ou
  // o agendamento do dbt (06h/13h) pode ter rodado com a tela em segundo plano.
  useEffect(() => {
    const aoVisibilidade = () => { if (document.visibilityState === "visible") consultar(); };
    window.addEventListener("focus", consultar);
    document.addEventListener("visibilitychange", aoVisibilidade);
    return () => {
      window.removeEventListener("focus", consultar);
      document.removeEventListener("visibilitychange", aoVisibilidade);
    };
  }, [consultar]);

  // Limpeza do timeout de 90s ao desmontar o provider (fim de sessão).
  useEffect(() => () => {
    if (timeoutDisparoRef.current) clearTimeout(timeoutDisparoRef.current);
  }, []);

  const atualizar = useCallback(async () => {
    setErro(null);
    setAvisoConfirmacao(null);
    try {
      await api.dispararAtualizacao();
    } catch (e) {
      // 409 (já rodando) e 429 (rodou há menos de 10 min): o `detail` já vem
      // em português, pronto para a tela mostrar — nunca `alert()`. Não entra
      // no estado otimista: o POST não criou processo nenhum.
      setErro({ status: e.status, mensagem: e.detalhe });
      await consultar();
      return;
    }

    // POST 202: o processo filho só EXISTE a partir de agora — ele ainda vai
    // importar oracledb, subir o modo thick e abrir o pool antes de gravar a
    // linha EM_ANDAMENTO. Não esperamos o GET decidir sozinho (ele chegaria
    // cedo demais e traria a linha ANTERIOR, com `emAndamento: false`):
    // assumimos aqui, localmente, que há uma carga em andamento.
    const agora = Date.now();
    disparadoEmRef.current = agora;
    setDisparando(true);

    if (timeoutDisparoRef.current) clearTimeout(timeoutDisparoRef.current);
    timeoutDisparoRef.current = setTimeout(() => {
      // Saída de segurança: se em 90s o GET nunca confirmou `emAndamento` nem
      // uma execução concluída mais nova que o clique, o `Popen` provavelmente
      // morreu ao nascer (import falhou, pool não abriu...). Abandona o
      // estado otimista com um aviso — melhor isso que "Atualizando…" eterno.
      if (disparadoEmRef.current === agora) {
        limparOtimista();
        setAvisoConfirmacao(
          "Não foi possível confirmar o início da atualização. Tente novamente em instantes."
        );
      }
    }, LIMITE_CONFIRMACAO_MS);

    await consultar();
  }, [consultar, limparOtimista]);

  // `emAndamento` que a tela usa é a UNIÃO do que o servidor confirma com o
  // otimismo local — nunca só um dos dois. Só o servidor faria o botão
  // reabilitar cedo demais (a corrida descrita acima); só o otimismo nunca
  // saberia quando uma carga de OUTRA aba, ou do agendamento 06h/13h, começou.
  const emAndamento = !!estado?.emAndamento || disparando;

  return (
    <AtualizacaoContexto.Provider
      value={{ estado, emAndamento, carregando, erro, avisoConfirmacao, atualizar, versaoDados }}
    >
      {children}
    </AtualizacaoContexto.Provider>
  );
}

export function useAtualizacao() {
  const contexto = useContext(AtualizacaoContexto);
  if (!contexto) throw new Error("useAtualizacao precisa estar dentro de AtualizacaoProvider");
  return contexto;
}
