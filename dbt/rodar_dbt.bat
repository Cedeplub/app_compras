@echo off
chcp 65001 > nul
set PYTHONUTF8=1
setlocal enabledelayedexpansion

REM ============================================================
REM  Execucao Completa do dbt (seed + run + test)
REM  Correcoes ao run_dbt.bat do powerbi_dbt:
REM  - Sem tee (nao existe no Windows)
REM  - Erro real do dbt eh propagado (sem PowerShell wrapper)
REM  - Codigo de saida nao eh forcado a 0
REM ============================================================

cd /d "%~dp0"

REM === Configuracoes ===
REM Absoluto: o script faz cd para o projeto adiante, e caminho relativo
REM faria os deactivate apontarem para dbt\compras\env_server, que nao existe.
set VENV=%~dp0env_server
set DBT_PROJECT=%CD%\compras
set LOG_DIR=logs_execucao
set TARGET=prod

REM === Aceitar alvo como argumento ===
if not "%~1"=="" (
    set TARGET=%~1
)

REM === Zerar o log interno do dbt ANTES do build ===
REM O dbt APENDA em compras\logs\dbt.log indefinidamente. Sem zerar aqui, o log
REM desta execucao sairia com o historico inteiro de todas as execucoes anteriores
REM (ja chegou a 3,2 MB com 30 builds) e nao daria para saber o que e desta rodada.
if exist "compras\logs\dbt.log" del /q "compras\logs\dbt.log"

REM === Criar diretorio de logs ===
mkdir "%LOG_DIR%" 2>nul

REM === Gerar timestamp ===
for /f "tokens=*" %%i in ('powershell -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set TIMESTAMP=%%i
set LOG_FILE=%LOG_DIR%\dbt_%TIMESTAMP%.log

echo [%time%] === INICIANDO EXECUCAO DBT (alvo: %TARGET%) ===

REM === Validar diretorios ===
if not exist "%VENV%\Scripts\activate.bat" (
    echo ERRO: Ambiente virtual nao encontrado
    echo O que fazer: Verifique se o venv em %VENV% existe.
    exit /b 1
)

if not exist "%DBT_PROJECT%" (
    echo ERRO: Projeto dbt nao encontrado
    echo O que fazer: Verifique se o diretorio compras existe.
    exit /b 1
)

REM === Ativar ambiente virtual ===
call "%VENV%\Scripts\activate.bat" > nul 2>&1
if !errorlevel! neq 0 (
    echo ERRO: Falha ao ativar ambiente virtual
    exit /b 1
)

REM === Navegar para o projeto ===
cd /d "!DBT_PROJECT!"
if !errorlevel! neq 0 (
    echo ERRO: Nao foi possivel navegar para %DBT_PROJECT%
    call "%VENV%\Scripts\deactivate.bat" > nul 2>&1
    exit /b 1
)

set START_TIME=%time%

echo [%time%] === ETAPA 1: DBT SEED ===
dbt seed --target %TARGET%
set SEED_EXIT=!errorlevel!

if !SEED_EXIT! neq 0 (
    echo.
    echo ERRO: dbt seed falhou com codigo !SEED_EXIT!
    echo O que fazer: Verifique o log em %CD%\logs\dbt.log
    call "%VENV%\Scripts\deactivate.bat" > nul 2>&1
    exit /b !SEED_EXIT!
)

echo [%time%] === ETAPA 2: DBT RUN ===
dbt run --target %TARGET%
set RUN_EXIT=!errorlevel!

if !RUN_EXIT! neq 0 (
    echo.
    echo ERRO: dbt run falhou com codigo !RUN_EXIT!
    echo O que fazer: Verifique o log em %CD%\logs\dbt.log
    call "%VENV%\Scripts\deactivate.bat" > nul 2>&1
    exit /b !RUN_EXIT!
)

echo [%time%] === ETAPA 3: DBT TEST ===
dbt test --target %TARGET%
set TEST_EXIT=!errorlevel!

if !TEST_EXIT! neq 0 (
    echo.
    echo ERRO: dbt test falhou com codigo !TEST_EXIT!
    echo O que fazer: Verifique o log em %CD%\logs\dbt.log
    call "%VENV%\Scripts\deactivate.bat" > nul 2>&1
    exit /b !TEST_EXIT!
)

set END_TIME=%time%

REM === Copiar log do dbt para diretorio com timestamp ===
if exist "logs\dbt.log" (
    copy "logs\dbt.log" "..\!LOG_FILE!" > nul 2>&1
    if errorlevel 1 echo  AVISO: nao foi possivel gravar o log da execucao em ..\!LOG_FILE!
)

REM === Imprimir resumo ===
echo.
echo ============================================================
echo  RESUMO DA EXECUCAO
echo ============================================================
echo  Alvo:      %TARGET%
echo  Inicio:    %START_TIME%
echo  Fim:       %END_TIME%
echo  Resultado: SUCESSO
echo  dbt seed:  OK
echo  dbt run:   OK
echo  dbt test:  OK
echo  Log:       %CD%\..\!LOG_FILE!
echo ============================================================
echo.

REM === Limpar logs com mais de 30 dias ===
forfiles /P "..\%LOG_DIR%" /M dbt_*.log /D -30 /C "cmd /c del @path" 2>nul

REM === Encerrar ===
call "%VENV%\Scripts\deactivate.bat" > nul 2>&1
endlocal

exit /b 0
