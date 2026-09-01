{# ─────────────────────────────────────────────────────────────────────────
   Recorte temporal do relatorio mensal (query_mensal.py / compras_mensal.py).

   var('compras_meses_historico', 24) meses, contados para tras a partir do
   PRIMEIRO DIA DO MES CORRENTE (TRUNC(SYSDATE,'MM')), intervalo SEMIABERTO:
   >= inicio AND < fim. O BETWEEN do arquivo original perdia lancamento do
   ultimo dia com hora diferente de 00:00 - por isso o limite superior e
   exclusivo aqui tambem.

   Deliberadamente NAO usa o macro filtro_periodo do powerbi_dbt: aquele tem
   'hoje' como default de BIND (silencioso, dependente do dia em que RODOU o
   dbt sem ninguem pedir). Aqui o uso de SYSDATE e o proprio CONTRATO do
   relatorio mensal - "os N meses que terminam no mes corrente" - entao a
   dependencia do dia do build e intencional e documentada, nao acidental.
   ───────────────────────────────────────────────────────────────────────── #}

{% macro compras_periodo_inicio() %}
add_months(trunc(sysdate, 'MM'), -({{ var('compras_meses_historico', 24) }} - 1))
{%- endmacro %}

{% macro compras_periodo_fim() %}
add_months(trunc(sysdate, 'MM'), 1)
{%- endmacro %}
