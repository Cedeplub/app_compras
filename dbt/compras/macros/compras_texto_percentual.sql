{#-
  ─────────────────────────────────────────────────────────────────────────────
  Percentual em TEXTO dos alertas AV (CHECK_DEVOLUCAO_ALTA), CL
  (CHECK_MARGEM_INSTAVEL) e DB (CHECK_MARGEM_INSTAVEL_VAREJO).

  ── ⚠ MELHORIA A4 | uma casa decimal, com VÍRGULA (divergência DELIBERADA) ───
  Registro: MELHORIAS.md item A4, aprovado em 21/08/2026; CONTEXTO.md §6.0.
  Não reverter para "fechar o validador".

  O QUE A PLANILHA FAZ. As três fórmulas escrevem TEXT(<razao>,"0.0%"), que em
  en-US significa "uma casa decimal". Mas o xlsx foi salvo com locale pt-BR, e
  ali o "." do código de formato é o separador de MILHAR, não o decimal.
  Resultado real, conferido célula a célula contra a aba `pedido`: o Excel
  imprime o percentual INTEIRO, com no mínimo DOIS dígitos —
  0,01 -> "01%", 0,11 -> "11%", 0 -> "00%", -0,02 -> "-02%",
  3,6167 -> "362%". Nenhuma das 2.180 células de alerta com percentual tem casa
  decimal.

  POR QUE ISSO FALHA. O alerta de margem crítica deixa de distinguir 5,0% de
  5,9% — a faixa inteira sai como "05%". Quem lê perde exatamente a resolução
  que faz a frase "MARGEM CRITICA" valer alguma coisa. E o padding de dois
  dígitos ("05%") não é intenção de ninguém: é o mesmo efeito colateral da
  máscara mal lida (os dois "0" de "0.0" viram dois dígitos INTEIROS).

  O QUE PASSAMOS A FAZER. Imprimir o que "0.0%" quis dizer, nas convenções
  brasileiras: **um dígito inteiro no mínimo, exatamente uma casa decimal,
  vírgula como separador decimal**. 0,105 -> "10,5%", 0,0549 -> "5,5%",
  0 -> "0,0%", -0,02 -> "-2,0%", 3,6167 -> "361,7%".

  ⚠ Duas mudanças de texto, não uma, e as duas são propositais:
    1. ganha a casa decimal (o objetivo);
    2. perde o zero à esquerda ("05%" -> "5,5%"), porque o padding era artefato
       da máscara mal lida e nenhuma leitura de "0.0" produz dois dígitos
       inteiros. Manter "05,5%" seria preservar metade do defeito.

  Vírgula e não ponto: o público é brasileiro e o resto da planilha é pt-BR.
  Por isso o NLS_NUMERIC_CHARACTERS vem EXPLÍCITO na chamada — sem ele o
  elemento `D` seguiria o NLS da SESSÃO, e o mesmo build sairia com "10.5%"
  ou "10,5%" conforme quem conectou. Constante de formatação não pode depender
  de ambiente.

  `round(x * 100, 1)` (metade para longe do zero) é o mesmo critério de
  arredondamento de exibição do Excel.

  LIMITE CONHECIDO, sem efeito na base atual: a partir de 1000% o Excel pt-BR
  aplicaria o agrupamento de milhar ("1.234,5%") e esta máscara não
  ("1234,5%"). O maior valor da base é 600% (TX_DEVOLUCAO_3M) e a maior margem
  é 362%, então nenhuma célula alcança o caso. Se algum dia alcançar, é aqui
  que se corrige — em um lugar só, para os três alertas.
  ─────────────────────────────────────────────────────────────────────────────
-#}

{% macro compras_texto_percentual(expressao) -%}
to_char(
    round(({{ expressao }}) * 100, 1),
    'FM999999990D0',
    'NLS_NUMERIC_CHARACTERS = '',.'''
) || '%'
{%- endmacro %}
