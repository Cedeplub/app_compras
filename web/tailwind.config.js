/** Tokens de design extraídos de v2/prototipo/PROTOTIPO.md §6.
 *
 *  O protótipo usa esses hex inline, espalhados pelas 3.660 linhas. Aqui eles
 *  ganham nome uma vez. Trocar o vermelho da marca passa a ser uma linha, e a
 *  cor deixa de ser um literal que ninguém sabe se é o mesmo dos outros lugares.
 */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx}"],
  theme: {
    extend: {
      colors: {
        navy: "#375DA8",         // marca: cabeçalho, botão primário, classe A
        vermelho: "#DE434B",     // ação decisiva, ruptura, margem baixa, S/VEND
        ambar: "#B98A2E",        // aviso: orçamento enviado, baixo/alto giro
        verde: "#15803D",        // sucesso: exportado, confirmação
        "verde-claro": "#16A34A",// botão "Enviado ✓"
        roxo: "#7C3AED",         // badge ST Recolhido
        "cinza-neutro": "#6B7280",// rascunho, modalidade Normal, texto de apoio
        "cinza-oliva": "#8A8578",// alerta "sem giro"
        amarelo: "#FBBF24",      // barra do ano anterior no mini-gráfico
        "azul-destaque": "#1D4ED8", // coluna EST+PED
        "roxo-destaque": "#7E22CE", // coluna Cobertura/Alvo
      },
      maxWidth: {
        // §6: o app tem duas larguras de container, e a tela de Decisão do SKU
        // tem a sua própria, menor que a do resto.
        //
        // `app` subiu de 1400px para 1800px (item 3 do Diretor, 08/09): em
        // telas de 1600px+ a Precificação (15 colunas) e Pedidos (17 colunas)
        // ficavam com as colunas da direita cortadas dentro do
        // `overflow-x-auto` da tabela, enquanto sobrava margem branca dos dois
        // lados do container. Preferi um teto maior a um fluido com padding
        // porque o conteúdo que sofre é TABULAR (linhas de produto), não
        // prosa — não há ganho de legibilidade em limitar a largura de uma
        // tabela como se fosse texto corrido, e um valor fixo mantém a barra
        // fixa do carrinho (`Pedidos.jsx`) alinhada com o mesmo cálculo
        // simples de sempre (`mx-auto max-w-app`).
        app: "1800px",
        sku: "1100px",
      },
      fontSize: {
        // §6 lista 12 tamanhos usados em `text-[Npx]` avulso, sem escala
        // nomeada. Aqui viram escala: quem escreve tela nova escolhe um degrau
        // em vez de inventar um 13,5px que só existe naquele componente.
        "2xs": ["10px", { lineHeight: "13px" }],
        xs: ["11px", { lineHeight: "15px" }],
        sm: ["12px", { lineHeight: "16px" }],
        base: ["13px", { lineHeight: "18px" }],
        md: ["14px", { lineHeight: "20px" }],
        lg: ["16px", { lineHeight: "22px" }],
        xl: ["18px", { lineHeight: "24px" }],
      },
    },
  },
  plugins: [],
};
