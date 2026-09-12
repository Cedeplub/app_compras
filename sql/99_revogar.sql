--------------------------------------------------------------------------------
-- 99_revogar.sql
--
-- Desfaz por completo o que 01_usuario_compras.sql e 02_tabelas_app.sql
-- criaram. Rodar como um usuário com privilégio de administrar contas (ex.:
-- SYSTEM ou um DBA nominal), nunca como o próprio COMPRAS — o DROP USER
-- precisa ser feito de fora.
--
-- ATENÇÃO: a seção 2 (DROP USER CASCADE) apaga todas as tabelas APP_* e todo
-- dado nelas, sem retorno. Só rodar em desligamento definitivo do projeto ou
-- em ambiente descartável (ex.: recriar do zero uma base de testes). Para
-- apenas revogar acesso ao CEDEP sem apagar dado da aplicação, rode só as
-- seções 1 e 3 e pare — deixe a seção 2, a seção 4 e o DROP USER final
-- comentados.
--
-- A PARTIR DA ETAPA 1, o schema COMPRAS também tem objetos criados pelo dbt
-- (views/tabelas com prefixo stg_, int_, dim_, fat_ — CONTEXTO.md §2). Este
-- script NUNCA os derruba (é vedado: o dbt é dono desses objetos, não este
-- script de administração de conta). Consequência prática: com esses objetos
-- presentes, `DROP USER COMPRAS` (sem CASCADE) falha com ORA-01922 "USER ...
-- MUST BE CASCADE"; e mesmo `DROP USER COMPRAS CASCADE` os apaga junto (é
-- exatamente o que a seção 2 avisa). Se o objetivo for só limpar os objetos
-- do dbt sem tocar em APP_* nem apagar o usuário, isso é feito por fora deste
-- script (ex.: `dbt run` numa branch vazia, ou DROP nominal de cada objeto
-- stg_/int_/dim_/fat_ — nunca um DROP genérico que possa alcançar APP_*).
--------------------------------------------------------------------------------

whenever sqlerror continue

--------------------------------------------------------------------------------
-- 1. Corta acesso imediatamente. Revogar CREATE SESSION (seção 2) só impede
--    sessões NOVAS — uma sessão já aberta continua válida até desconectar.
--    Para garantir que ninguém continue usando uma conexão já estabelecida,
--    trava a conta.
--------------------------------------------------------------------------------
alter user compras account lock;

--------------------------------------------------------------------------------
-- 2. Apaga o usuário inteiro (schema COMPRAS e todas as tabelas APP_*
--    dentro dele, e — se existirem objetos do dbt, ver aviso acima —
--    obrigatoriamente também eles, por causa do CASCADE). Comentado por
--    padrão: descomente linha a linha só quando o objetivo for realmente
--    destruir o schema.
--------------------------------------------------------------------------------
-- drop user compras cascade;

--------------------------------------------------------------------------------
-- 3. Revoga privilégios e GRANTs sem apagar o usuário nem os dados — desfaz
--    exatamente o que 01_usuario_compras.sql concedeu, mantendo o schema e
--    as tabelas APP_* (e os objetos do dbt, se existirem) intactos.
--------------------------------------------------------------------------------
revoke select on cedep.pcprodut        from compras;
revoke select on cedep.pcest           from compras;
revoke select on cedep.pcprodfilial    from compras;
revoke select on cedep.pctabtrib       from compras;
revoke select on cedep.pctribut        from compras;
revoke select on cedep.pctribpiscofins from compras;
revoke select on cedep.pctabpr         from compras;
revoke select on cedep.pcfornec        from compras;
revoke select on cedep.pcdepto         from compras;
revoke select on cedep.pcsecao         from compras;
revoke select on cedep.pcmov           from compras;
revoke select on cedep.pcmovcomple     from compras;
revoke select on cedep.pcnfsaid        from compras;
revoke select on cedep.pcnfent         from compras;
revoke select on cedep.pcestcom        from compras;
revoke select on cedep.pcclient        from compras;
revoke select on cedep.pcfilial        from compras;
revoke select on cedep.pcregiao        from compras;
revoke select on cedep.pchistest       from compras;

revoke create credential from compras;
revoke create job        from compras;
revoke create synonym    from compras;
revoke create sequence   from compras;
revoke create procedure  from compras;
revoke create view       from compras;
revoke create table      from compras;
revoke create session    from compras;

--------------------------------------------------------------------------------
-- 4. Desfaz as tabelas APP_* criadas por 02_tabelas_app.sql, sem apagar o
--    usuário. Ordem inversa de dependência (FKs primeiro). Comentado por
--    padrão pelo mesmo motivo da seção 2: isto apaga dado de negócio e de
--    login. Descomente só se o objetivo for esse. Isto NÃO derruba objetos
--    do dbt (stg_/int_/dim_/fat_) — ver aviso no cabeçalho do arquivo.
--------------------------------------------------------------------------------
-- drop table compras.app_auditoria purge;
-- drop table compras.app_sessao purge;
-- drop table compras.app_usuario purge;
-- drop table compras.app_decisao_pedido purge;
-- drop table compras.app_decisao_preco_hist purge;
-- drop table compras.app_decisao_preco purge;

--------------------------------------------------------------------------------
-- 5. Só depois de 2 (ou de 3+4, se o schema for esvaziado manualmente por
--    fora), remova a cota e o usuário, se esse for mesmo o objetivo:
--------------------------------------------------------------------------------
-- alter user compras quota 0 on users;
-- drop user compras;

whenever sqlerror exit sql.sqlcode
