{#
  Cria um índice numa tabela materializada pelo dbt, de forma idempotente.

  Por que existe: a materialização `table` do dbt derruba e recria a tabela a
  cada `dbt run`. Índice criado à mão some junto no build seguinte, sem avisar —
  a tela volta a ficar lenta e ninguém liga uma coisa à outra. Declarado como
  `post_hook` do model, o índice é recriado no mesmo passo que a tabela, e passa
  a ser parte da definição dela.

  Por que é PL/SQL e não um `create index` seco: o Oracle não tem
  `create index if not exists`. Se o índice sobreviver por algum caminho (uma
  materialização que faça `insert` em vez de `create as`, por exemplo), o
  `create` cru aborta o build inteiro por ORA-00955 — falha de manutenção
  disfarçada de falha de modelo.

  ⚠ Nada de aspas duplas nos identificadores: o Oracle maiusculiza o que não
  está entre aspas, e um nome citado em minúsculas vira outro objeto
  (CONTEXTO.md §5).
#}

{% macro compras_indice(tabela, colunas, sufixo) %}
  {% set nome = 'IX_' ~ tabela ~ '_' ~ sufixo %}
  declare
    ja_existe number;
  begin
    select count(*) into ja_existe
      from user_indexes
     where index_name = '{{ nome | upper }}';
    if ja_existe = 0 then
      execute immediate 'create index {{ nome }} on {{ tabela }} ({{ colunas }})';
    end if;
  end;
{% endmacro %}
