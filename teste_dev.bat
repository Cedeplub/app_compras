@echo off
rem ============================================================================
rem  Dashboard de Compras - AMBIENTE DE DEV ISOLADO (schema COMPRAS_DEV).
rem
rem  Versionado desde a Etapa 16 (23/09/2026): e o caminho de subida do
rem  ambiente de desenvolvimento, e um ambiente que nao sobrevive versionado
rem  nao sobrevive a troca de maquina. Antes disso vivia so em
rem  .git/info/exclude desta pasta.
rem  Sobe API + front de uma vez, em portas DIFERENTES da producao/dev
rem  tradicional (8020/5173), para nunca colidir nem confundir:
rem
rem    API ..... porta 8021, em janela separada (start)
rem    Front ... porta 5174, nesta mesma janela, com proxy para a API acima
rem
rem  Clique duas vezes. Duas janelas abrem. Fechar esta (a do front) nao
rem  fecha a da API - feche as duas no X ou CTRL+C quando terminar.
rem ============================================================================
setlocal
chcp 65001 >nul 2>&1
set PYTHONUTF8=1
cd /d "%~dp0"
title Dashboard de Compras - DEV (front, CTRL+C encerra)

echo.
echo  ============================================================
echo   DASHBOARD DE COMPRAS - AMBIENTE DE DEV (schema COMPRAS_DEV)
echo  ============================================================
echo.

if not exist ".env" (
    echo  [ERRO] Arquivo .env nao encontrado nesta pasta.
    echo         Copie .env.exemplo para .env e preencha com as credenciais
    echo         de COMPRAS_DEV ^(nao as de producao^).
    goto :fim
)

findstr /c:"ORA_SCHEMA=COMPRAS_DEV" .env >nul 2>&1
if errorlevel 1 (
    echo  [AVISO] O .env desta pasta nao tem ORA_SCHEMA=COMPRAS_DEV.
    echo          Confira se nao esta apontando sem querer para o schema de
    echo          producao ^(COMPRAS^) antes de continuar.
    echo.
    pause
)

echo  Subindo a API em segundo plano - porta 8021 ...
start "Dashboard de Compras - DEV API (CTRL+C encerra)" cmd /k ^
    "cd /d "%~dp0" && python -m uvicorn app.main:app --host 127.0.0.1 --port 8021 --reload"

echo  API ................ http://127.0.0.1:8021
echo  Front (a seguir) ... http://127.0.0.1:5174
echo.
echo  Para encerrar tudo: feche as DUAS janelas (esta e a da API), ou CTRL+C
echo  em cada uma.
echo  ------------------------------------------------------------
echo.

cd /d "%~dp0web"
set API_ALVO=http://127.0.0.1:8021
npm run dev -- --port 5174 --strictPort

echo.
echo  ------------------------------------------------------------
echo  Front encerrado. A janela da API pode continuar aberta - feche-a
echo  separadamente se quiser parar tudo.

:fim
echo.
pause
endlocal
