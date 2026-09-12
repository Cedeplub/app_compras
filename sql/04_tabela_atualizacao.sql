--------------------------------------------------------------------------------
-- 04_tabela_atualizacao.sql
--
-- Cria APP_ATUALIZACAO no schema COMPRAS: uma linha por execucao do dbt.
--
-- Por que existe: ate aqui o sistema sabe ate onde o dado vai
-- (COMPRAS_PARAMETRO.DATA_REFERENCIA), mas nao sabe QUANDO o dbt rodou -
-- nao havia timestamp de execucao em lugar nenhum. dbt/atualizar.py grava
-- uma linha aqui a cada execucao (manual ou agendada) e a API le a ultima
-- linha para carimbar o cabecalho da tela.
--
-- Contrato travado com dois outros agentes (dbt/atualizar.py e a API):
-- nomes e tipos de coluna nao podem mudar sem quebrar os dois.
--
-- APP_* e prefixo do app: o dbt LE esta tabela (para decidir o proximo
-- registro) e ESCREVE nela via atualizar.py, mas nunca a cria nem a derruba
-- (CONTEXTO.md §2) - quem cria/altera o schema e sempre este script.
--
-- Idempotente: cada CREATE TABLE/INDEX e precedido de checagem em
-- USER_TABLES/USER_INDEXES, entao rodar de novo nao derruba dado.
--
-- Rodar conectado como COMPRAS.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 1. APP_ATUALIZACAO — registro de cada execucao do dbt.
--
-- STATUS distingue CONCLUIDO de CONCLUIDO_COM_AVISO de proposito: dbt run
-- pode passar e dbt test reprovar, e nesse caso o dado esta fresco - o que
-- existe e um aviso, nao uma carga que nao aconteceu (em 24/08 o dbt test
-- ja terminou com 1 warn de 263). Colapsar isso em FALHOU enganaria quem le
-- o cabecalho da tela.
--
-- SOLICITADO_POR e nullable e sem FK para APP_USUARIO de proposito: a
-- Tarefa Agendada nao tem usuario do app, e rodar_dbt.bat grava o
-- %USERNAME% do Windows, que nao e login do app.
--
-- MENSAGEM e VARCHAR2(500), nao CLOB, de proposito: e o texto curto de um
-- tooltip/title, nao o log inteiro - o log completo fica em ARQUIVO_LOG.
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from user_tables where table_name = 'APP_ATUALIZACAO';
    if v_existe = 0 then
        execute immediate q'[
            create table app_atualizacao (
                id_atualizacao   number         generated always as identity,
                origem           varchar2(10)   not null,
                solicitado_por   varchar2(60),
                inicio           timestamp      default systimestamp not null,
                fim              timestamp,
                status           varchar2(20)   not null,
                duracao_seg      number(6),
                fase_falha       varchar2(10),
                mensagem         varchar2(500),
                arquivo_log      varchar2(300),
                constraint pk_app_atualizacao primary key (id_atualizacao),
                constraint ck_app_atualizacao_origem check (origem in ('MANUAL','AGENDADO')),
                constraint ck_app_atualizacao_status check (status in ('EM_ANDAMENTO','CONCLUIDO','CONCLUIDO_COM_AVISO','FALHOU')),
                constraint ck_app_atualizacao_fase   check (fase_falha is null or fase_falha in ('seed','run','test'))
            )
        ]';
    end if;
end;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from user_indexes where index_name = 'IX_APP_ATUALIZACAO_INICIO';
    if v_existe = 0 then
        execute immediate
            'create index ix_app_atualizacao_inicio on app_atualizacao (inicio desc)';
    end if;
end;
/

comment on table app_atualizacao is
    'Registro de cada execucao do dbt (dbt/atualizar.py), uma linha por execucao. A API le a ultima linha (ORDER BY INICIO DESC, servido pelo indice IX_APP_ATUALIZACAO_INICIO) para carimbar o cabecalho da tela com quando o dado foi atualizado pela ultima vez. So cresce; nunca alterada nem apagada apos concluida, exceto o proprio UPDATE que fecha a linha (FIM/STATUS/DURACAO_SEG/...) ao final da execucao que a abriu.';
comment on column app_atualizacao.id_atualizacao is
    'Chave tecnica sequencial (IDENTITY, GENERATED ALWAYS - nunca aceita id explicito em uso normal).';
comment on column app_atualizacao.origem is
    'MANUAL = disparado por um clique na tela ou pelo rodar_dbt.bat; AGENDADO = disparado pela Tarefa Agendada do Windows (06:00 e 13:00).';
comment on column app_atualizacao.solicitado_por is
    'Login de quem solicitou a execucao. NULL quando ORIGEM=AGENDADO (a Tarefa Agendada nao tem usuario). Quando ORIGEM=MANUAL via rodar_dbt.bat, grava o %USERNAME% do Windows - que nao e login do app; por isso nao ha FK para APP_USUARIO.';
comment on column app_atualizacao.inicio is
    'Timestamp de inicio da execucao do dbt. Default SYSTIMESTAMP no INSERT que abre a linha.';
comment on column app_atualizacao.fim is
    'Timestamp de termino da execucao. NULL enquanto STATUS=EM_ANDAMENTO.';
comment on column app_atualizacao.status is
    'EM_ANDAMENTO enquanto roda; CONCLUIDO = dbt run e dbt test passaram; CONCLUIDO_COM_AVISO = dbt run passou mas dbt test reprovou algum teste - o dado esta fresco, so ha um aviso a mostrar (nao confundir com FALHOU); FALHOU = a execucao nao completou (erro em seed, run ou test antes de terminar).';
comment on column app_atualizacao.duracao_seg is
    'Duracao da execucao em segundos, calculada como FIM - INICIO ao fechar a linha. NULL enquanto EM_ANDAMENTO.';
comment on column app_atualizacao.fase_falha is
    'Comando dbt em que a falha ocorreu: seed, run ou test (minusculo, e o nome do comando dbt). NULL quando STATUS nao e FALHOU.';
comment on column app_atualizacao.mensagem is
    'Ultimas linhas uteis do erro, truncadas em 500 caracteres - texto curto para um tooltip/title, nao o log inteiro. NULL em execucao sem erro. O log completo fica em ARQUIVO_LOG.';
comment on column app_atualizacao.arquivo_log is
    'Caminho do arquivo de log completo desta execucao, em dbt/logs_execucao/.';
