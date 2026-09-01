@echo off
rem ============================================================================
rem  Dashboard de Compras - subida rapida para TESTE (com --reload).
rem
rem  Em producao, o app sobe como servico NSSM sem --reload (ver ETAPA 7).
rem
rem  Clique duas vezes. A janela fica aberta com o servidor rodando:
rem    - CTRL+C encerra (o cmd pergunta "Terminate batch job (Y/N)?" - responda S)
rem    - fechar a janela no X tambem encerra, sem pergunta
rem
rem  Sobe com --reload: alteracao em .py recarrega sozinha, sem parar o servidor.
rem ============================================================================
setlocal
chcp 65001 >nul 2>&1
set PYTHONUTF8=1
cd /d "%~dp0"
title Dashboard de Compras - teste (CTRL+C encerra)

echo.
echo  ============================================================
echo   DASHBOARD DE COMPRAS - modo teste
echo  ============================================================
echo.

rem --- Python instalado? --------------------------------------------------
where python >nul 2>&1
if errorlevel 1 (
    echo  [ERRO] Python nao encontrado no PATH.
    echo         Instale o Python ou ajuste o PATH e tente de novo.
    goto :fim
)

rem --- Dependencias -------------------------------------------------------
python -c "import fastapi, uvicorn, oracledb, jinja2" >nul 2>&1
if errorlevel 1 (
    echo  Faltam dependencias. Para instalar, rode:
    echo.
    echo      python -m pip install -r requirements.txt
    echo.
    goto :fim
)

rem --- Configuracao -------------------------------------------------------
if not exist ".env" (
    echo  [ERRO] Arquivo .env nao encontrado.
    echo         Copie o .env.exemplo para .env e preencha ORA_PASSWORD.
    echo.
    echo         copy .env.exemplo .env
    echo.
    echo  IMPORTANTE: sem ORA_PASSWORD preenchido, o app nao sobe de proposito.
    goto :fim
)

rem A porta sai do config.py (padrao 8020), para nao existir um segundo lugar dizendo qual e.
rem Aceita HTTP_PORT ou PORT: o config.py segue o padrao do app_relatorios, que
rem chama HTTP_PORT. Tentar so um nome faria uma porta trocada ser ignorada em
rem silencio - o .bat cairia no 8020 e o app subiria em outra.
set PORTA=8020
for /f "delims=" %%p in ('python -c "import app.config as c;print(getattr(c,'HTTP_PORT',getattr(c,'PORT',8020)))" 2^>nul') do set PORTA=%%p

rem --- A porta esta livre? ------------------------------------------------
netstat -ano | findstr /r /c:":%PORTA% .*LISTENING" >nul 2>&1
if not errorlevel 1 (
    echo  [ERRO] A porta %PORTA% ja esta em uso.
    echo         Provavelmente o app ja esta no ar em outra janela.
    echo.
    echo         Para ver qual processo:
    echo             netstat -ano ^| findstr :%PORTA%
    echo.
    goto :fim
)

set IP=127.0.0.1
for /f "delims=" %%i in ('python -c "import socket;print(socket.gethostbyname(socket.gethostname()))" 2^>nul') do set IP=%%i

echo  Nesta maquina ...... http://localhost:%PORTA%
echo  Na rede ............ http://%IP%:%PORTA%
echo.
echo  Para encerrar: CTRL+C e responda S, ou feche esta janela no X.
echo  ------------------------------------------------------------
echo.

rem Abre o navegador alguns segundos depois, ja com o servidor de pe.
start "" /min cmd /c "timeout /t 4 >nul & start "" http://localhost:%PORTA%"

rem Fica em primeiro plano: e o que faz o CTRL+C chegar no servidor.
rem
rem --host 0.0.0.0 e DELIBERADO aqui, e e o OPOSTO do que a ETAPA 7 vai fazer:
rem   TESTE (este arquivo): escuta em toda interface, para o Diretor de Compras
rem     poder abrir no CELULAR pela rede interna. Acesso por celular e requisito
rem     do projeto, nao bonus, e nao da para valida-lo escutando so em loopback.
rem   PRODUCAO (servico NSSM): escuta em 127.0.0.1, porque quem passa a expor na
rem     rede e o nginx. La o loopback e o certo.
rem Trocar isto de volta para 127.0.0.1 faz a linha "Na rede" acima virar mentira.
rem ATENCAO (01/09/2026): nesta maquina existe um SOCKET ORFAO escutando em
rem 0.0.0.0:8020 desde 25/08/2026. O processo dono (PID 2240) nao existe mais,
rem o socket nao responde a nada, e ainda assim segura a porta - o bind em
rem 0.0.0.0 falha com WinError 10048. Um bind no IP ESPECIFICO convive com ele,
rem entao e esse o caminho enquanto o orfao existir. Some com um reinicio da
rem maquina; ai da para voltar a 0.0.0.0 e apagar este bloco.
rem
rem O for/f abaixo descobre o IPv4 da maquina em vez de chumbar 192.168.0.50:
rem chumbar quebraria em silencio no dia em que o IP mudasse.
set IP_LAN=
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=* delims= " %%b in ("%%a") do if not defined IP_LAN set IP_LAN=%%b
)
if not defined IP_LAN set IP_LAN=0.0.0.0
echo Escutando em %IP_LAN%:%PORTA%
python -m uvicorn app.main:app --host %IP_LAN% --port %PORTA% --reload

echo.
echo  ------------------------------------------------------------
echo  Servidor encerrado.

:fim
echo.
pause
endlocal
