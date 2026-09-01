@echo off
setlocal
chcp 65001 >nul 2>&1
set PYTHONUTF8=1
cd /d "%~dp0"

echo Teste 1: Lendo porta do app/config.py (deve ser 8020)
set PORTA=8020
for /f "delims=" %%p in ('python -c "import app.config;print(app.config.PORT)" 2^>nul') do set PORTA=%%p
echo Porta lida: %PORTA%
echo.

echo Teste 2: Sem o app/config.py, deve manter o padrao 8020
set PORTA=8020
for /f "delims=" %%p in ('python -c "import nonexistent;print(1)" 2^>nul') do set PORTA=%%p
echo Porta (com fallback): %PORTA%
echo.

endlocal
