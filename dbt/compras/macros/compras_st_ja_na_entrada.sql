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
  de int_produto_custo.sql. Em resumo: NAO soma, a menos que as tres valham
  juntas — cadastro ST_SUBSTITUTO, entrada a partir do Decreto 7.799 e
  fornecedor de fora do estado de destino.

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

  ⚠ Os alias `f` (int_produto_fiscal), `e` (int_produto_entrada_fornecedor) e
  `par` (int_parametro) sao os do select chamador. A macro depende deles de
  proposito: passar tres nomes de alias por parametro tornaria a chamada mais
  longa que a propria condicao, e ela so' tem um chamador.
  ─────────────────────────────────────────────────────────────────────────────
-#}

{% macro compras_st_ja_na_entrada() -%}
case when f.modalidade  = 'ST_SUBSTITUTO'                                  -- 1
      and e.dt_ult_ent is not null
      and e.dt_ult_ent >= par.st_beneficio_inicio                          -- 2
      and e.uf_entrada is not null
      and e.uf_entrada <> '{{ var("compras_uf_destino", "BA") }}'          -- 3
     then 0 else 1
end
{%- endmacro %}
