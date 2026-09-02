{#
  Cria um índice numa tabela materializada pelo dbt, de forma idempotente.

  Por que existe: a materialização `table` do dbt derruba e recria a tabela a
  cada `dbt run`. Índice criado à mão some junto no build seguinte, sem avisar —
  a tela volta a ficar lenta e ninguém liga uma coisa à outra. Declarado como
  `post_hook` do model, o índice é recriado no mesmo passo que a tabela, e passa
  a ser parte da definição dela.

  Por que é PL/SQL e não um `create index` seco: o Oracle não tem
  `create index if not exists`. Se o nome estiver ocupado por algum caminho, o
  `create` cru aborta o build inteiro por ORA-00955 — falha de manutenção
  disfarçada de falha de modelo.

  ⚠ Nada de aspas duplas nos identificadores: o Oracle maiusculiza o que não
  está entre aspas, e um nome citado em minúsculas vira outro objeto
  (CONTEXTO.md §5).

  ── ⚠ CORRIGIDO EM 02/09/2026 | era "criar se não existe", virou ────────────
  ── "derrubar e criar" ──────────────────────────────────────────────────────
  O teste era `if (select count(*) from user_indexes where index_name = <nome>)
  = 0 then create`, e isso fazia os índices OSCILAREM entre um build e o
  seguinte — medido em COMPRAS_ALERTA nesta data: dois `dbt run` seguidos
  deixaram conjuntos DIFERENTES de índices na tabela, um perdendo o que o outro
  criava.

  A causa: a materialização `table` do dbt não derruba a tabela antiga na hora.
  Ela cria a nova com nome temporário, RENOMEIA a antiga para
  `<tabela>__dbt_backup`, renomeia a nova para o nome final, roda os post_hooks
  e só DEPOIS derruba o backup. Índice acompanha a tabela na renomeação **com o
  nome original** — então, no instante em que o hook roda, `IX_X_Y` existe,
  pendurado no BACKUP. O `count(*)` achava 1, o `if` pulava a criação, e o drop
  do backup levava o índice junto. Resultado: a tabela nova ficava SEM o índice,
  e o build seguinte o criava — e perdia outro, na mesma armadilha.

  Sintoma para reconhecer: o índice existe, some, volta. Nenhum erro, nenhum
  aviso; só a tela ficando lenta em dia alternado.

  Por que "derrubar e criar" e não "checar também o table_name": porque nome de
  índice é único POR SCHEMA no Oracle, não por tabela. Filtrar por `table_name`
  faz o hook decidir corretamente que falta o índice — e aí o `create` bate no
  ORA-00955 do índice do backup, que ainda ocupa o nome. Verificado nesta data,
  com esse erro exato. Derrubar antes libera o nome, e derrubar um índice do
  backup é inócuo: aquela tabela vai deixar de existir dois passos adiante.

  O `exception when others then null` do drop cobre o caso normal (ORA-01418,
  índice não existe) — a criação logo abaixo é que não pode falhar em silêncio,
  e não está protegida.

  Custo: o índice é reconstruído a cada build. Não é desperdício novo — a tabela
  inteira já é reconstruída a cada build, e um índice de tabela que acabou de
  nascer teria de ser criado de qualquer forma.
#}

{% macro compras_indice(tabela, colunas, sufixo) %}
  {% set nome = 'IX_' ~ tabela ~ '_' ~ sufixo %}
  begin
    -- Libera o nome. Ele pode estar ocupado pelo indice do __dbt_backup, que a
    -- materializacao derruba logo em seguida - ver cabecalho.
    begin
      execute immediate 'drop index {{ nome }}';
    exception
      when others then null;  -- ORA-01418: nao existe, que e o caso comum
    end;
    execute immediate 'create index {{ nome }} on {{ tabela }} ({{ colunas }})';
  end;
{% endmacro %}
