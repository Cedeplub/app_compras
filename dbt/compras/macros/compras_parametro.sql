{#-
  ─────────────────────────────────────────────────────────────────────────────
  Leitura de um parametro do seed_parametros ja PIVOTADO em linha unica.

  Existe para que int_parametro.sql seja uma lista legivel de nomes de negocio
  em vez de 21 repeticoes de to_number(...) com mascara e NLS. Nao ha regra de
  negocio aqui - a regra (quais parametros valem) esta no model.

  VALOR e VARCHAR2 no seed porque a coluna guarda numero E texto na mesma
  celula (MEDIDA_PEDIDO = 'LITROS'). A conversao precisa de mascara + NLS
  explicito: sem 'NLS_NUMERIC_CHARACTERS', uma sessao com virgula decimal
  (pt-BR e o default deste servidor em varias ferramentas) transformaria
  '0.0925' em erro ou em 925. Constante fiscal virando 925 e exatamente o tipo
  de defeito que o projeto nao pode ter.
  ─────────────────────────────────────────────────────────────────────────────
-#}

{% macro compras_parametro_num(nome) -%}
max(case when parametro = '{{ nome }}'
         then to_number(valor, '9999999999D9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''')
    end)
{%- endmacro %}


{% macro compras_parametro_txt(nome) -%}
max(case when parametro = '{{ nome }}' then valor end)
{%- endmacro %}
