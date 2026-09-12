@echo off
chcp 65001 >nul
set PYTHONUTF8=1
setlocal enabledelayedexpansion

rem ============================================================================
rem  Invólucro fino que invoca dbt/atualizar.py
rem
rem  IMPORTANTE: Toda a lógica de seed, run, test, trava de exclusão, registro
rem  em banco, cópia de logs, etc. migrou para atualizar.py. Este arquivo vale
rem  apenas para validar Python/dbt e repassar argv.
rem
rem  Se dois caminhos de atualização (este .bat + agendado + botão POST) fizessem
rem  lógica duplicada, eles divergiriam. Aqui existe apenas uma: no Python.
rem ============================================================================

cd /d "%~dp0"

rem === Python instalado? ===
where python >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python nao encontrado no PATH.
    echo O que fazer: Verifique a instalacao do Python ou ajuste PATH e tente de novo.
    exit /b 1
)

rem === dbt.exe existe? ===
if not exist "env_server\Scripts\dbt.exe" (
    echo [ERRO] dbt.exe nao encontrado: env_server\Scripts\dbt.exe
    echo O que fazer: Verifique o ambiente virtual em %CD%\env_server
    exit /b 1
)

rem === Invocar atualizar.py ===
rem %USERNAME% entre aspas: usuario Windows com espaco no nome (ex.: "Joao Silva")
rem quebrava o argparse sem isto.
python "%~dp0atualizar.py" --origem manual --por "%USERNAME%" %*
exit /b !errorlevel!
