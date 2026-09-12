--------------------------------------------------------------------------------
-- 01_usuario_compras.sql
--
-- REGISTRO, NAO EXECUCAO PENDENTE. O usuario COMPRAS ja foi criado pelo DBA em
-- produção (192.168.0.98:1521/WINT) e o estado abaixo foi conferido em
-- 2026-08-19 (ver diagnóstico da etapa 0). Este script existe para que o
-- mesmo estado possa ser reproduzido em outro ambiente (ex.: uma futura base
-- de homologação) ou auditado linha a linha. Rodar contra o ambiente onde o
-- usuario COMPRAS ja existe é seguro: os GRANT são idempotentes e o CREATE
-- USER é protegido para não falhar se o usuário já existir (ORA-01920).
--
-- Rodar como um usuário com privilégio de administrar contas (ex.: SYSTEM ou
-- um DBA nominal), nunca como o próprio COMPRAS.
--
-- A senha NUNCA fica em texto neste arquivo. `&senha` é substituída na hora
-- da execução. Conecte com `sqlplus /nolog` e depois `connect system` (ou o
-- DBA nominal), informando a senha do DBA na hora, interativamente — nunca
-- `sqlplus usuario/senha` na linha de comando: isso deixa a senha do DBA
-- visível em `tasklist`/`ps` e no histórico do shell. `SET VERIFY OFF` abaixo
-- evita que o SQL*Plus ecoe a senha nova (`&senha`) em claro nas linhas
-- `old:`/`new:` de substituição; `ACCEPT ... HIDE` evita ecoá-la enquanto é
-- digitada.
--------------------------------------------------------------------------------

set verify off
accept senha char prompt 'Senha para o novo usuario COMPRAS: ' hide

whenever sqlerror exit sql.sqlcode

--------------------------------------------------------------------------------
-- 1. Usuário e cota
--------------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe from dba_users where username = 'COMPRAS';
    if v_existe = 0 then
        execute immediate 'create user compras identified by "&senha" ' ||
                           'default tablespace users temporary tablespace temp';
    end if;
end;
/

-- Confere que o usuário existe antes de prosseguir: se o CREATE USER acima
-- falhou por qualquer motivo que a PL/SQL tenha engolido silenciosamente
-- (não deveria, com WHENEVER SQLERROR EXIT no topo, mas é barato conferir),
-- o script para aqui em vez de seguir concedendo os 27 GRANTs seguintes para
-- um usuário que não existe.
declare
    v_existe number;
begin
    select count(*) into v_existe from dba_users where username = 'COMPRAS';
    if v_existe = 0 then
        raise_application_error(-20000,
            'CREATE USER COMPRAS falhou ou nao foi executado - script interrompido antes dos GRANTs.');
    end if;
end;
/

-- Quota confirmada em produção: USERS, ilimitada (MAX_BYTES = -1).
alter user compras quota unlimited on users;

--------------------------------------------------------------------------------
-- 2. Privilégios de sistema
--
-- Conferidos em produção em 2026-08-19:
--   CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE,
--   CREATE SEQUENCE, CREATE SYNONYM  -> previstos no plano, necessários para
--   o schema COMPRAS existir e a aplicação/dbt criarem e usarem objetos APP_*.
--
--   CREATE CREDENTIAL, CREATE JOB    -> concedidos pelo DBA além do previsto
--   no plano original. Avaliação (oracle-dba): não fazem parte do desenho
--   atual do projeto. Nem o dbt (roda fora do banco, via processo externo)
--   nem o dashboard (grava via oracledb/DML comum) precisam de
--   DBMS_SCHEDULER dentro do schema COMPRAS. CREATE CREDENTIAL em particular
--   permite guardar credenciais de SO para jobs externos — superfície de
--   ataque desnecessária para um schema que deveria só orquestrar leitura do
--   CEDEP e escrita em APP_*. Não os removo aqui porque o DBA pode ter um
--   uso planejado (ex.: um job agendado dentro do próprio banco para
--   recalcular algo, ou para expirar sessões antigas via DBMS_SCHEDULER em
--   vez de um agendador externo). Recomendo confirmar o motivo com o DBA e,
--   se não houver uso concreto em 30 dias, revogar (ver sql/99_revogar.sql,
--   que já inclui o revoke dos dois).
--------------------------------------------------------------------------------
grant create session    to compras;
grant create table      to compras;
grant create view       to compras;
grant create procedure  to compras;
grant create sequence   to compras;
grant create synonym    to compras;
grant create job        to compras;  -- extra do DBA, ver avaliação acima
grant create credential to compras;  -- extra do DBA, ver avaliação acima

--------------------------------------------------------------------------------
-- 3. SELECT nominal nas 19 tabelas do CEDEP usadas pelo plano dbt
--
-- Nenhum GRANT de escrita (INSERT/UPDATE/DELETE) no CEDEP em nenhuma tabela,
-- em nenhuma hipótese — é a fronteira estrutural do projeto (CONTEXTO.md §2).
--------------------------------------------------------------------------------
grant select on cedep.pcprodut        to compras;
grant select on cedep.pcest           to compras;
grant select on cedep.pcprodfilial    to compras;
grant select on cedep.pctabtrib       to compras;
grant select on cedep.pctribut        to compras;
grant select on cedep.pctribpiscofins to compras;
grant select on cedep.pctabpr         to compras;
grant select on cedep.pcfornec        to compras;
grant select on cedep.pcdepto         to compras;
grant select on cedep.pcsecao         to compras;
grant select on cedep.pcmov           to compras;
grant select on cedep.pcmovcomple     to compras;
grant select on cedep.pcnfsaid        to compras;
grant select on cedep.pcnfent         to compras;
grant select on cedep.pcestcom        to compras;
grant select on cedep.pcclient        to compras;
grant select on cedep.pcfilial        to compras;
grant select on cedep.pcregiao        to compras;
grant select on cedep.pchistest       to compras;

--------------------------------------------------------------------------------
-- Conferência rápida (rodar como COMPRAS, não como quem executou acima):
--   select count(*) from cedep.pcprodut;           -- deve retornar
--   update cedep.pcprodut set descricao = descricao where codprod = 1;
--                                                    -- deve falhar ORA-01031
--------------------------------------------------------------------------------
