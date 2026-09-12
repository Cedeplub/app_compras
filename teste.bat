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

rem Descobre o IPv4 da maquina em vez de chumbar 192.168.0.50: chumbar
rem quebraria em silencio no dia em que o IP mudasse. Precisa vir antes da
rem checagem de porta abaixo, que verifica o endereco exato do bind.
set IP_LAN=
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=* delims= " %%b in ("%%a") do if not defined IP_LAN set IP_LAN=%%b
)
if not defined IP_LAN set IP_LAN=0.0.0.0

rem --- A porta esta livre no endereco em que vamos dar bind? ---------------
rem netstat/findstr sao frageis aqui (o PID e a ultima coluna, o endereco vem
rem em formatos diferentes), entao a checagem e feita via PowerShell.
rem So interessam entradas em 0.0.0.0 (bloqueia qualquer IP) ou no IP_LAN
rem exato (o endereco do nosso bind); outro IP especifico nao colide. Cada
rem uma delas so bloqueia de verdade se o PID dono ainda estiver vivo: socket
rem ORFAO (PID morto) nao impede o bind, so avisa - foi por causa de um
rem orfao assim, visto em 01/09/2026 em 0.0.0.0:8020 (PID 2240, morto), que o
rem bind abaixo usa o IP_LAN especifico em vez de 0.0.0.0. Sem checar se o
rem PID esta vivo, esse orfao bloquearia o script para sempre.
for /f "tokens=1-4 delims=|" %%A in ('powershell -NoProfile -Command "$port=%PORTA%; $lan='%IP_LAN%'; try { $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq $lan } } catch { $c = @() }; foreach ($x in $c) { $p = Get-Process -Id $x.OwningProcess -ErrorAction SilentlyContinue; if ($p) { Write-Output ('ALIVE|{0}|{1}|{2}' -f $x.OwningProcess,$p.ProcessName,$x.LocalAddress) } else { Write-Output ('ORPHAN|{0}|-|{1}' -f $x.OwningProcess,$x.LocalAddress) } }" 2^>nul') do (
    if "%%A"=="ALIVE" (
        echo  [ERRO] A porta %PORTA% ja esta em uso por um processo vivo.
        echo         PID %%B ^(%%C^), escutando em %%D:%PORTA%.
        echo         Provavelmente o app ja esta no ar em outra janela.
        echo.
        echo         Para encerrar esse processo:
        echo             taskkill /F /PID %%B
        echo.
        goto :fim
    )
    if "%%A"=="ORPHAN" (
        echo  [AVISO] Socket orfao em %%D:%PORTA% - PID %%B nao existe mais.
        echo          Por isso o bind abaixo usa o IP especifico, nao 0.0.0.0.
        echo.
    )
)

echo  Nesta maquina ...... http://localhost:%PORTA%
echo  Na rede ............ http://%IP_LAN%:%PORTA%
echo.
echo  Para encerrar: CTRL+C e responda S, ou feche esta janela no X.
echo  ------------------------------------------------------------
echo.

rem Abre o navegador alguns segundos depois, ja com o servidor de pe.
start "" /min cmd /c "timeout /t 4 >nul & start "" http://localhost:%PORTA%"

rem Fica em primeiro plano: e o que faz o CTRL+C chegar no servidor.
rem
rem --host %IP_LAN% e DELIBERADO aqui, e e o OPOSTO do que a ETAPA 7 vai fazer:
rem   TESTE (este arquivo): escuta em toda interface da rede local, para o
rem     Diretor de Compras poder abrir no CELULAR pela rede interna. Acesso
rem     por celular e requisito do projeto, nao bonus, e nao da para
rem     valida-lo escutando so em loopback.
rem   PRODUCAO (servico NSSM): escuta em 127.0.0.1, porque quem passa a expor
rem     na rede e o nginx. La o loopback e o certo.
rem Trocar isto para 127.0.0.1 faz a linha "Na rede" acima virar mentira.
echo Escutando em %IP_LAN%:%PORTA%
python -m uvicorn app.main:app --host %IP_LAN% --port %PORTA% --reload

echo.
echo  ------------------------------------------------------------
echo  Servidor encerrado.

:fim
echo.
pause
endlocal
