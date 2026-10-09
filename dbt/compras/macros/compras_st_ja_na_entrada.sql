{#-
  ─────────────────────────────────────────────────────────────────────────────
  "O ICMS-ST JA ESTA no valor de entrada deste produto?" — a condicao, escrita
  UMA vez.

  Devolve a expressao booleana (nao a coluna) que o `case` de BT, BU e
  ICMS_ST_BRUTO usam como guarda-corpo, e que a coluna `st_ja_na_entrada`
  materializa. Os quatro estao no MESMO select de int_produto_custo.sql, e em
  SQL um select nao enxerga o proprio alias — sem esta macro, a regra ficaria
  escrita quatro vezes.

  E ja ficou: ate 09/10/2026 a condicao antiga (`custo_ult_ent >
  custo_ult_ent_sem_st + 0.005`) aparecia copiada nos quatro lugares. Fechar a
  regra nas TRES condicoes significava editar as quatro copias sem errar
  nenhuma — e a quinta copia viria no proximo ajuste.

  A regra, por extenso, esta no bloco "ST JA EMBUTIDO NA ENTRADA" do cabecalho
  de int_produto_custo.sql. Em resumo, tres casos NAO somam e um soma:

    1. cadastro Normal ou ST recolhido ............... nao soma
    2. ST substituto, ultima COMPRA antes do Decreto . nao soma
    3. ST substituto, ultima COMPRA a partir dele .... SOMA
    4. sem compra nenhuma ............................ nao soma

  ⚠ A DATA E' A DA ULTIMA COMPRA, nao a de PCEST.DTULTENT. O WinThor grava em
  DTULTENT qualquer entrada - inclusive transferencia entre filiais e
  bonificacao - e olhar para ela responde pela movimentacao errada. Nos SKUs
  11, 63, 66 e 1463 a ultima entrada e' transferencia e a compra de verdade e'
  meses ou anos antes.

  ⚠ NAO HA MAIS CONDICAO DE UF. Ela existiu entre as 14h e as 20h de
  09/10/2026 e foi REPROVADA pelo Diretor de Compras com medicao propria: 215
  itens ST substituto com compra posterior ao Decreto perderam o ST por causa
  dela. A causa e' que a UF saia da ultima ENTRADA, que em 129 de 193 dos
  casos conferidos nao era compra - era transferencia de filial da BA. YPF,
  Lubrax, Ipiranga, Texaco, Petronas e Valvoline nao sao compradas na BA.
  Compra dentro do estado ja tem de estar cadastrada como ST RECOLHIDO, e
  o caso 1 a pega. Nao reintroduza a UF sem medir de novo.

  ⚠ DEVOLVE 1/0, NAO UM BOOLEANO, e isso e' a parte que importa. A forma
  natural seria `not (<as tres condicoes>)` — e ela tem um buraco: com
  `dt_ult_ent` nula, a conjuncao vale UNKNOWN, `not UNKNOWN` tambem vale
  UNKNOWN, o `when` nao dispara e o produto acaba SOMANDO um ST que talvez ja
  estivesse no preco. Em silencio, e exatamente nos 43 ativos sem data de
  ultima entrada. Um `case` nao tem esse buraco: o que nao casa com o `when`
  vai para o `else`, e o `else` e' o lado conservador (nao soma).

  Os `is not null` explicitos existem pelo mesmo motivo — para o leitor ver a
  decisao sobre o dado ausente escrita, em vez de deduzi-la do comportamento
  de tres valores logicos.

  ⚠ Os alias `f` (int_produto_fiscal), `compra` (int_produto_ultima_entrada) e
  `par` (int_parametro) sao os do select chamador. A macro depende deles de
  proposito: passar tres nomes de alias por parametro tornaria a chamada mais
  longa que a propria condicao, e ela so' tem um chamador.
  ─────────────────────────────────────────────────────────────────────────────
-#}

{% macro compras_st_ja_na_entrada() -%}
case when f.modalidade = 'ST_SUBSTITUTO'                                   -- 1
      and compra.dt_ult_ent_sem_frete is not null                          -- 3
      and compra.dt_ult_ent_sem_frete >= par.st_beneficio_inicio           -- 2
     then 0 else 1
end
{%- endmacro %}
