{# ─────────────────────────────────────────────────────────────────────────
   Recorte temporal do relatorio mensal (query_mensal.py / compras_mensal.py).

   var('compras_meses_historico', 96) meses, contados para tras a partir do
   PRIMEIRO DIA DO MES CORRENTE (TRUNC(SYSDATE,'MM')), intervalo SEMIABERTO:
   >= inicio AND < fim. O BETWEEN do arquivo original perdia lancamento do
   ultimo dia com hora diferente de 00:00 - por isso o limite superior e
   exclusivo aqui tambem.

   ⚠ O DEFAULT 96 aqui TEM de ser o mesmo que o de int_periodo_mensal.sql, que
   usa a mesma var para `qtd_meses`. Os dois so' sao lidos se alguem remover a
   var do dbt_project.yml - e, nesse dia, defaults diferentes desacoplariam
   data_inicio de qtd_meses, que e' exatamente o risco documentado no cabecalho
   daquele model (MED12 NULL -> sugestao de compra a menos, em silencio).

   Deliberadamente NAO usa o macro filtro_periodo do powerbi_dbt: aquele tem
   'hoje' como default de BIND (silencioso, dependente do dia em que RODOU o
   dbt sem ninguem pedir). Aqui o uso de SYSDATE e o proprio CONTRATO do
   relatorio mensal - "os N meses que terminam no mes corrente" - entao a
   dependencia do dia do build e intencional e documentada, nao acidental.
   ───────────────────────────────────────────────────────────────────────── #}

{% macro compras_periodo_inicio() %}
add_months(trunc(sysdate, 'MM'), -({{ var('compras_meses_historico', 96) }} - 1))
{%- endmacro %}

{% macro compras_periodo_fim() %}
add_months(trunc(sysdate, 'MM'), 1)
{%- endmacro %}
