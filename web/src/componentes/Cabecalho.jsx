import { useEffect, useRef, useState } from "react";
import { Link, NavLink } from "react-router-dom";
import { AlertTriangle, FileText, Info, LogOut, Menu, PackagePlus, RefreshCw, Save, Tag } from "lucide-react";
import logoCedep from "../logo-cedep.png";
import { useAtualizacao } from "../contexto/atualizacao.jsx";
import { dataHoraCarga } from "../formato.js";

/* Cabeçalho e menu de áreas — porte de `Header` e `MenuArea`
 * (v2/prototipo/painel_cedep_prototipo_2.jsx, linhas 414 e 456).
 *
 * A navegação tem DOIS níveis, e o cabeçalho é onde o de cima mora:
 *   área  →  Painel · Pedidos · Pedidos Salvos · Precificação   (menu ☰ daqui)
 *   aba   →  Alertas · Monitoramento · Entradas                 (só dentro do
 *            Painel, na BarraAbas)
 *
 * A primeira versão desta tela achatou os dois níveis numa fileira de seis
 * abas, o que fazia "Alertas" e "Pedidos" parecerem irmãos quando um é aba do
 * Painel do Dia e o outro é uma área inteira.
 *
 * Etapa 13 (§4, ponto 3 do Diretor): a partir de `lg:` (1024px) as áreas
 * também aparecem em linha, na própria faixa navy (`BarraAreas`, abaixo) — mas
 * o ☰ NÃO some: ele é o único lugar com espaço para o subtítulo de cada área
 * ("Decisão de compra — visão ampla"), que a faixa não comporta. Abaixo de
 * `lg`, cinco rótulos não cabem bem (medido — e a Etapa 12 acabou de somar o
 * quinto), então o ☰ continua sendo o único caminho. A `BarraAreas` fica na
 * MESMA faixa navy do cabeçalho — a `BarraAbas` (aba do Painel) é branca, um
 * nível visualmente abaixo — de propósito: achatar as duas num estilo só é
 * exatamente o erro que o comentário acima registra.
 */

export const AREAS = [
  { id: "painel", para: "/painel/alertas", rotulo: "Painel",
    sub: "Alertas · Monitoramento · Entradas", icone: AlertTriangle },
  { id: "pedidos", para: "/pedidos", rotulo: "Pedidos",
    sub: "Decisão de compra — visão ampla", icone: PackagePlus },
  { id: "pedidos_salvos", para: "/pedidos-salvos", rotulo: "Pedidos Salvos",
    sub: "Status, orçamento e envio pro Winthor", icone: FileText },
  { id: "precificacao", para: "/precificacao", rotulo: "Precificação",
    sub: "Decisão de preço — visão ampla", icone: Tag },
  // Etapa 12: o lote de preços como documento (PROMPT_ETAPA_12_PRECOS_DEFINIDOS.md
  // §6.3). Ícone Save, como no `.jsx` novo do Diretor (painel_cedep_prototipo_090926,
  // linha 421) — é o mesmo "salvar/gravar" que o resto do app usa para preço.
  { id: "precos_definidos", para: "/precos-definidos", rotulo: "Preços Definidos",
    sub: "Lotes de preço para importação no Winthor", icone: Save },
];

const NAVY = "#375DA8";
const VERMELHO = "#DE434B";

export default function Cabecalho({ titulo, subtitulo, areaAtual, usuario, aoSair }) {
  // Uma leitura só do contexto aqui em cima: o carimbo (ícone + botão, dentro
  // da faixa navy) e a faixa de aviso (abaixo da faixa de marca) mostram a
  // MESMA classificação, então é a mesma chamada que alimenta os dois — não
  // duas leituras de `useAtualizacao()` que podiam divergir por um instante.
  const ctxAtualizacao = useAtualizacao();
  const aviso = classificarAviso(ctxAtualizacao);

  return (
    // ⚠ `relative z-30` é o que faz o menu ☰ abrir POR CIMA da barra de abas.
    //
    // A barra de abas é `sticky z-20`. O painel do menu tinha `z-20` também, mas
    // o empate não era o problema: o bloco da barra de ferramentas usa
    // `relative z-[1]` (necessário para o logo ficar sobre o corte diagonal), e
    // isso cria um CONTEXTO DE EMPILHAMENTO — dentro dele, o `z-20` do menu vale
    // só contra os irmãos ali dentro, nunca contra algo de fora. O menu poderia
    // pedir z-9999 e continuaria por baixo.
    //
    // Elevar a RAIZ do cabeçalho resolve de vez: o subárvore inteira, menu
    // incluído, passa a pintar acima da barra. Mexer no z-index do menu não
    // resolveria — foi a primeira coisa que pareceu certa e não era.
    <div className="relative z-30">
      <div className="relative flex items-center justify-between py-3 pl-6 pr-4"
           style={{ background: NAVY }}>
        {/* O corte diagonal branco que entra na faixa navy é a assinatura visual
            da marca no protótipo — o logo repousa sobre ele. As proporções
            (132px de largura, vértice a 76%) são as do original. */}
        <div className="absolute bottom-0 left-0 top-0 bg-white"
             style={{ width: 132, clipPath: "polygon(0 0, 100% 0, 76% 100%, 0 100%)" }}
             aria-hidden="true" />
        {/* Etapa 13, §5 — clicar no logo vai para o Painel. O `z-[1]` que
            fazia o logo pintar sobre o corte diagonal migra para o `<Link>`:
            se ficasse só no `<img>`, o link herdaria posição estática e
            voltaria a pintar por baixo do corte branco (o mesmo raciocínio
            do comentário sobre `relative z-30`, acima). */}
        <Link to="/painel/alertas" aria-label="Ir para o painel"
              className="relative z-[1] flex items-center">
          <img src={logoCedep} alt="CEDEP" className="h-8 w-auto" />
        </Link>

        {/* `z-[1]`: mesmo contexto de empilhamento do logo e do bloco da
            direita — precisa pintar sobre o corte diagonal como os dois. */}
        <BarraAreas areaAtual={areaAtual} />

        <div className="relative z-[1] flex items-center gap-2">
          <CarimboAtualizacao ctx={ctxAtualizacao} aviso={aviso} />
          {/* Os botões Smartphone/Monitor do protótipo NÃO foram portados: eles
              existem porque lá a troca mobile↔mesa é um booleano manual e o
              arquivo simula os dois tamanhos numa janela só. Aqui a
              responsividade é de CSS — quem decide o formato é a largura real
              da tela, então o alternador não teria função. */}
          <MenuArea areaAtual={areaAtual} />
          <BotaoSair usuario={usuario} aoSair={aoSair} />
        </div>
      </div>

      {/* Faixa de marca: 3px, metade navy, metade vermelha. */}
      <div className="flex h-[3px]" aria-hidden="true">
        <div className="flex-1" style={{ background: NAVY }} />
        <div className="flex-1" style={{ background: VERMELHO }} />
      </div>

      <FaixaAviso aviso={aviso} />

      <div className="px-4 pb-1 pt-3 md:px-6">
        <h1 className="text-[17px] font-semibold leading-tight text-gray-900">{titulo}</h1>
        {subtitulo && <p className="mt-0.5 text-sm text-gray-500">{subtitulo}</p>}
      </div>
    </div>
  );
}

// Contraste sobre o navy `#375DA8` — o âmbar de fundo claro (`#F59E0B`,
// `amber-500`) não passa em texto pequeno sobre essa cor. Este é o mesmo tom
// usado em avisos sobre navy no resto do app.
const AMBAR_SOBRE_NAVY = "#FBBF24";

/* Classifica o estado da atualização em "info" (a ação certa é esperar) ou
 * "alerta" (a ação certa é desconfiar — nada vai acontecer até alguém olhar).
 * Uma função só, chamada uma vez em `Cabecalho`, porque o carimbo (ícone no
 * botão) e a `FaixaAviso` (linha visível abaixo da faixa de marca) têm de
 * concordar sobre qual dos quatro casos está ativo — duas classificações
 * independentes já divergiram de outras telas por um instante de re-render.
 *
 * Prioridade replica a do `title` que existia antes desta correção: um erro
 * de uma AÇÃO recém-tentada (clique) fala mais alto que o estado de fundo. */
function classificarAviso({ estado, emAndamento, erro, avisoConfirmacao }) {
  const bloqueadoPorJanela = !emAndamento && estado?.podeAtualizar === false;
  const falhou = estado?.status === "FALHOU";

  if (erro) {
    // 409 (já rodando) e 429 (atualizado há poucos minutos): a própria API
    // dizendo "espere", não uma falha — o usuário não precisa se preocupar,
    // só aguardar a janela. 404/500/rede (status 0) são o caso real: algo
    // quebrou e não vai se resolver sozinho.
    const info = erro.status === 409 || erro.status === 429;
    return { tipo: info ? "info" : "alerta", texto: erro.mensagem };
  }
  if (avisoConfirmacao) {
    // O caso mais grave dos quatro: o clique travou o botão por até 90s e o
    // processo aparentemente nem chegou a existir. Ver `LIMITE_CONFIRMACAO_MS`
    // em `contexto/atualizacao.jsx`.
    return { tipo: "alerta", texto: avisoConfirmacao };
  }
  if (bloqueadoPorJanela) {
    const texto = estado?.proximaLiberacaoEm != null
      ? `Atualizado há poucos minutos. Nova atualização liberada em ${estado.proximaLiberacaoEm} min.`
      : "Atualizado há poucos minutos.";
    return { tipo: "info", texto };
  }
  if (falhou) {
    // `estado.mensagem` vem da carga que rodou de verdade e falhou (dbt) —
    // pode ser longa, então a `FaixaAviso` que a mostra não trunca: quebra
    // linha em vez de esconder informação de diagnóstico.
    return { tipo: "alerta", texto: estado?.mensagem ?? "A última atualização falhou." };
  }
  return { tipo: null, texto: null };
}

/* Linha visível abaixo da faixa de marca — a superfície que faltava. Um
 * `title` (tooltip) só aparece no hover depois de ~1s e NUNCA no celular, que
 * é o dispositivo que este projeto trata como requisito. Sem isto, clicar e
 * falhar era visualmente idêntico a clicar e nada acontecer (o relato que
 * motivou esta correção). Some sozinha: `aviso` vem de `classificarAviso`,
 * que reflete o estado do contexto — assim que um GET ou um clique seguinte
 * resolve a situação, o próximo render já não tem texto para mostrar aqui. */
function FaixaAviso({ aviso }) {
  if (!aviso?.texto) return null;
  const alerta = aviso.tipo === "alerta";
  return (
    <div role={alerta ? "alert" : "status"}
         className={`flex items-start gap-2 px-4 py-1.5 text-xs md:px-6 ${
           alerta ? "bg-red-50 text-red-700" : "bg-blue-50 text-blue-700"
         }`}>
      {alerta
        ? <AlertTriangle size={14} className="mt-0.5 shrink-0" aria-hidden="true" />
        : <Info size={14} className="mt-0.5 shrink-0" aria-hidden="true" />}
      <span className="leading-snug">{aviso.texto}</span>
    </div>
  );
}

// A Tarefa Agendada roda 06:00 e 13:00 todos os dias — o maior intervalo
// NORMAL entre duas cargas bem-sucedidas é 17h (13:00 até 06:00 do dia
// seguinte). Se uma carga inteira for pulada (ex.: a das 13:00 falha e
// ninguém percebe), o intervalo salta para 24h (a próxima 06:00 vem no dia
// seguinte). O limiar fica ENTRE os dois: alto o bastante para nunca disparar
// sobre o intervalo normal de 17h (com folga para um atraso comum de rede/
// dbt), baixo o bastante para avisar horas antes de completar as 24h de uma
// carga perdida, e não no dia seguinte quando já é tarde para agir.
const LIMIAR_CARGA_ATRASADA_HORAS = 20;

/* Não existe no protótipo (§8: `HOJE` é `new Date(2026, 7, 28)` chumbado, e
 * não há noção nenhuma de "carga do dbt"). Substitui o antigo `DataDeHoje`,
 * que imprimia a data do DISPOSITIVO ao lado de números que podiam ser de
 * dias atrás.
 *
 * O pedido literal do Diretor foi "coloca a hora da atualização" — o carimbo
 * chegou a existir liderando com `dataReferencia` (o último dia com VENDA) e
 * deixando a hora da carga como fragmento sem data no fim da frase
 * ("atualizado 06:05", sem dizer de que dia), o que fazia a carga de hoje e a
 * de anteontem, ambas às 06:05, imprimirem o MESMO texto. Agora o eixo é
 * `estado.fim` — quando a carga terminou de rodar —, sempre com data OU
 * "hoje"/"ontem" explícitos; `dataReferencia` vira contexto no `title`. */
function CarimboAtualizacao({ ctx, aviso }) {
  const { estado, emAndamento, carregando, atualizar } = ctx;

  const falhou = estado?.status === "FALHOU";
  const info = dataHoraCarga(estado?.fim);

  // Idade da CARGA (não do último dia com venda — ver comentário do
  // componente). É o que decide o âmbar: `dataReferencia` atrasa um dia por
  // natureza (só fecha depois que o dia termina), então usá-la aqui fazia o
  // cabeçalho ficar âmbar todo dia, logo depois de uma carga bem-sucedida —
  // um alarme que sempre toca deixa de ser lido.
  const idadeCargaHoras = estado?.fim
    ? (Date.now() - new Date(estado.fim).getTime()) / 3_600_000
    : null;
  const cargaAtrasada = idadeCargaHoras !== null && idadeCargaHoras > LIMIAR_CARGA_ATRASADA_HORAS;

  // `podeAtualizar`/`proximaLiberacaoEm` vêm prontos do backend, calculados
  // com o relógio do BANCO — não recalcule a janela de 10min aqui com
  // `new Date()` do navegador, que é exatamente o desalinho que motivou o
  // backend a mudar de relógio. Só vale quando não há carga em andamento (o
  // otimismo local já cobre esse caso e tem prioridade).
  const bloqueadoPorJanela = !emAndamento && estado?.podeAtualizar === false;
  const emAmbar = aviso.tipo === "alerta" || cargaAtrasada;

  // Texto principal: sempre "Atualizado ...", com data OU "hoje"/"ontem" e a
  // hora — nunca só a hora solta (o defeito relatado). Quando não há `fim`
  // confiável (carga travada sem nunca concluir, ou banco recém-instalado
  // sem carga nenhuma), não inventamos horário: dizemos o que sabemos, sem
  // afirmar um dado que não existe.
  const textoCompleto = emAndamento
    ? "Atualizando…"
    : info
      ? `Atualizado ${info.relativo ? info.texto : `em ${info.texto}`}`
      : falhou
        ? "Última atualização falhou"
        : "Sem atualização registrada";
  // Celular: "Atualizado" é a palavra mais dispensável — o ícone de
  // atualizar ao lado já dá o verbo — então o compacto mostra só o valor
  // ("hoje 06:05", "11/09 06:05"), do mesmo jeito que o compacto antigo já
  // não repetia "Dados de".
  const textoCompacto = emAndamento
    ? "Atualizando…"
    : info
      ? info.curto
      : falhou
        ? "falhou"
        : "sem dados";

  // O último dia com VENDA (`dataReferencia`) responde uma pergunta diferente
  // ("até quando vão os números") e continua existindo — só que em segundo
  // plano, no `title`, nunca mais na manchete. `aviso.texto` (erro/falha/
  // janela) vem primeiro por ser a informação mais urgente; as duas, quando
  // as duas existem, ficam separadas por travessão para não empilhar sem
  // pontuação.
  const infoReferencia = estado?.dataReferencia
    ? `Último dia com venda: ${dataCurta(estado.dataReferencia)}`
    : null;
  const tituloCarimbo = [aviso.texto, infoReferencia].filter(Boolean).join(" — ") || undefined;

  // O `title` do BOTÃO continua sendo sobre a AÇÃO (o que acontece se
  // clicar), papel distinto do título do texto acima (o que já aconteceu).
  let dicaBotao = aviso.texto;
  if (!dicaBotao) {
    // `estado?.inicio` só é confiável quando o SERVIDOR confirmou (senão é o
    // início da execução ANTERIOR, e mostraria um horário errado enquanto
    // ainda estamos no otimismo local).
    if (emAndamento) {
      const hora = estado?.emAndamento ? horaCurta(estado?.inicio) : null;
      dicaBotao = hora ? `Atualização em andamento desde ${hora}` : "Atualização em andamento";
    } else {
      dicaBotao = "Atualizar dados agora";
    }
  }

  const desabilitado = emAndamento || carregando || bloqueadoPorJanela;
  const cor = emAmbar ? AMBAR_SOBRE_NAVY : "rgba(255,255,255,0.7)";

  return (
    <div className="flex items-center gap-1.5 text-xs" style={{ color: cor }}>
      <span className="num" title={tituloCarimbo}>
        <span className="hidden sm:inline">{textoCompleto}</span>
        <span className="sm:hidden">{textoCompacto}</span>
      </span>
      {/* Não usamos o atributo `disabled`: em muitos navegadores um
          `<button disabled>` simplesmente não dispara `title` (nem hover nem
          toque), e o `title` é a ÚNICA superfície de explicação que este
          carimbo tem no celular, onde o texto do rótulo some. `aria-disabled`
          mantém o botão focável e o motivo legível; o clique é neutralizado
          no próprio handler. */}
      <button type="button" onClick={desabilitado ? undefined : atualizar}
              aria-disabled={desabilitado} title={dicaBotao} aria-label="Atualizar dados"
              className={`rounded-full bg-white/15 p-2 ${desabilitado ? "cursor-not-allowed opacity-60" : ""}`}>
        <RefreshCw size={14} className={emAndamento ? "animate-spin" : ""}
                   style={{ color: emAndamento ? "white" : cor }} aria-hidden="true" />
      </button>
    </div>
  );
}

function horaCurta(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function dataCurta(iso) {
  if (!iso) return "—";
  const [, mes, dia] = iso.split("-");
  return `${dia}/${mes}`;
}

/* Etapa 13, §4 — as cinco áreas em linha, só a partir de `lg:`. Reusa a MESMA
 * lista `AREAS` que o `MenuArea` já usa (nenhuma segunda lista) e o mesmo
 * critério de "ativo" — comparar `areaAtual` (calculado em `App.jsx` por
 * PREFIXO de rota), não o `NavLink` isolado, porque uma rota como
 * `/pedidos-salvos/7` precisa acender "Pedidos Salvos" e o `NavLink` sozinho
 * só sabe igualdade de caminho exato. */
function BarraAreas({ areaAtual }) {
  return (
    <nav aria-label="Áreas" className="relative z-[1] hidden items-center gap-1 lg:flex">
      {AREAS.map((a) => {
        const ativo = areaAtual === a.id;
        return (
          <NavLink key={a.id} to={a.para}
                   aria-current={ativo ? "page" : undefined}
                   className="rounded-full px-3 py-1.5 text-xs font-medium text-white/70 transition-colors hover:text-white hover:bg-white/10"
                   style={ativo ? { background: "rgba(255,255,255,0.18)", color: "#fff" } : undefined}>
            {a.rotulo}
          </NavLink>
        );
      })}
    </nav>
  );
}

function MenuArea({ areaAtual }) {
  const [aberto, setAberto] = useState(false);
  const caixa = useRef(null);

  // Fechar com Esc e ao clicar fora. O protótipo cobre o clique fora com um
  // `fixed inset-0` invisível, mas não trata Esc — quem navega por teclado fica
  // preso no menu.
  useEffect(() => {
    if (!aberto) return;
    const aoTeclar = (e) => { if (e.key === "Escape") setAberto(false); };
    const aoClicar = (e) => { if (caixa.current && !caixa.current.contains(e.target)) setAberto(false); };
    document.addEventListener("keydown", aoTeclar);
    document.addEventListener("mousedown", aoClicar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      document.removeEventListener("mousedown", aoClicar);
    };
  }, [aberto]);

  return (
    <div className="relative" ref={caixa}>
      <button type="button" onClick={() => setAberto((v) => !v)}
              aria-expanded={aberto} aria-haspopup="menu" aria-label="Menu de áreas"
              className="rounded-full bg-white/15 p-2">
        <Menu size={16} className="text-white" aria-hidden="true" />
      </button>

      {aberto && (
        <div role="menu"
             className="absolute right-0 top-11 z-20 w-64 rounded-xl border border-gray-200 bg-white py-1.5 shadow-lg">
          {AREAS.map((a) => {
            const Icone = a.icone;
            const ativo = areaAtual === a.id;
            return (
              <NavLink key={a.id} to={a.para} role="menuitem"
                       onClick={() => setAberto(false)}
                       className="flex w-full items-center gap-2.5 px-3 py-2.5 text-left"
                       style={ativo ? { background: `${NAVY}0D` } : undefined}>
                <Icone size={16} color={ativo ? NAVY : "#9CA3AF"} aria-hidden="true" />
                <span>
                  <span className="block text-[12.5px] font-medium"
                        style={{ color: ativo ? NAVY : "#374151" }}>{a.rotulo}</span>
                  <span className="block text-2xs text-gray-400">{a.sub}</span>
                </span>
              </NavLink>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* Não existe no protótipo, porque lá não há login. Aqui há sessão, perfil e
 * auditoria — e uma tela que não oferece saída obriga a fechar o navegador. */
function BotaoSair({ usuario, aoSair }) {
  return (
    <button type="button" onClick={aoSair}
            title={`Sair — ${usuario?.nome ?? ""}`}
            className="flex items-center gap-1.5 rounded-full bg-white/15 px-2.5 py-2 text-xs font-medium text-white">
      <LogOut size={14} aria-hidden="true" />
      <span className="hidden sm:inline">Sair</span>
    </button>
  );
}
