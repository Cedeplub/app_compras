@echo off
rem ============================================================================
rem  Dashboard de Compras - Front (Vite/React) - subida para TESTE.
rem
rem  Este atalho existe porque o Vite le tailwind.config.js UMA VEZ, ao subir,
rem  e nao recarrega sozinho quando o arquivo muda. Sem um .bat para isso, o
rem  front vinha sendo subido "a mao" - e ficou OITO DIAS no ar servindo uma
rem  configuracao de Tailwind congelada (largura das telas mudou de 1400px
rem  para 1800px no codigo e no build, mas o navegador continuava recebendo
rem  1400px, porque ninguem tinha reiniciado o Vite). Se voce mudar o
rem  tailwind.config.js, precisa FECHAR e SUBIR de novo este .bat - reload de
rem  pagina no navegador nao basta.
rem
rem  Clique duas vezes. A janela fica aberta com o servidor rodando:
rem    - CTRL+C encerra (o cmd pergunta "Terminate batch job (Y/N)?" - responda S)
rem    - fechar a janela no X tambem encerra, sem pergunta
rem ============================================================================
setlocal
chcp 65001 >nul 2>&1
set PYTHONUTF8=1
cd /d "%~dp0web"
title Dashboard de Compras - FRONT teste (CTRL+C encerra)

echo.
echo  ============================================================
echo   DASHBOARD DE COMPRAS - FRONT (Vite/React) - modo teste
echo  ============================================================
echo.

rem --- Pasta web existe de verdade? ---------------------------------------
if not exist "package.json" (
    echo  [ERRO] Nao encontrei web\package.json.
    echo         Este .bat espera rodar a partir da raiz do projeto, com uma
    echo         pasta "web" ao lado dele. Confira se a pasta nao foi movida.
    goto :fim
)

rem --- npm instalado? -------------------------------------------------------
where npm >nul 2>&1
if errorlevel 1 (
    echo  [ERRO] npm nao encontrado no PATH.
    echo         Instale o Node.js ^(que traz o npm junto^) ou ajuste o PATH e
    echo         tente de novo.
    goto :fim
)

rem --- Dependencias instaladas? ----------------------------------------------
if not exist "node_modules" (
    echo  [ERRO] Faltam as dependencias do front ^(pasta node_modules ausente^).
    echo         Rode primeiro, dentro da pasta web:
    echo.
    echo             npm install
    echo.
    goto :fim
)

set PORTA=5173

rem Descobre o IPv4 da maquina em vez de chumbar um endereco: chumbar quebraria
rem em silencio no dia em que o IP mudasse. Precisa vir antes da checagem de
rem porta abaixo, que verifica o endereco exato do bind (0.0.0.0, ver
rem web\vite.config.js).
set IP_LAN=
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
  for /f "tokens=* delims= " %%b in ("%%a") do if not defined IP_LAN set IP_LAN=%%b
)
if not defined IP_LAN set IP_LAN=0.0.0.0

rem --- A porta 5173 esta livre? -----------------------------------------------
rem Mesma logica do teste.bat: so interessam entradas em 0.0.0.0 (bloqueia
rem qualquer IP) ou no IP_LAN exato; outro IP especifico nao colide. Cada uma
rem so bloqueia de verdade se o PID dono ainda estiver vivo - socket ORFAO
rem (PID morto) nao impede o bind, so avisa.
for /f "tokens=1-4 delims=|" %%A in ('powershell -NoProfile -Command "$port=%PORTA%; $lan='%IP_LAN%'; try { $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop | Where-Object { $_.LocalAddress -eq '0.0.0.0' -or $_.LocalAddress -eq $lan } } catch { $c = @() }; foreach ($x in $c) { $p = Get-Process -Id $x.OwningProcess -ErrorAction SilentlyContinue; if ($p) { Write-Output ('ALIVE|{0}|{1}|{2}' -f $x.OwningProcess,$p.ProcessName,$x.LocalAddress) } else { Write-Output ('ORPHAN|{0}|-|{1}' -f $x.OwningProcess,$x.LocalAddress) } }" 2^>nul') do (
    if "%%A"=="ALIVE" (
        echo  [ERRO] A porta %PORTA% ja esta em uso por um processo vivo.
        echo         PID %%B ^(%%C^), escutando em %%D:%PORTA%.
        echo         Provavelmente o front ja esta no ar em outra janela.
        echo.
        echo         Para encerrar esse processo:
        echo             taskkill /F /PID %%B
        echo.
        goto :fim
    )
    if "%%A"=="ORPHAN" (
        echo  [AVISO] Socket orfao em %%D:%PORTA% - PID %%B nao existe mais.
        echo          Seguindo assim mesmo; o bind abaixo deve funcionar.
        echo.
    )
)

echo  Nesta maquina ...... http://localhost:%PORTA%
echo  Na rede ............ http://%IP_LAN%:%PORTA%
echo  No celular ......... http://%IP_LAN%:%PORTA%  ^(mesma rede/Wi-Fi^)
echo.

rem --- Avisa sobre a API, sem bloquear -------------------------------------
rem O Vite faz proxy de /api para 192.168.0.50:8020 (ver web\vite.config.js).
rem Sem a API no ar, toda tela de consulta vem com erro. Isso NAO impede subir
rem o front - a pessoa pode estar subindo os dois em paralelo.
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://192.168.0.50:8020' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo  [AVISO] Nao consegui falar com a API em 192.168.0.50:8020.
    echo          Se ela ainda nao estiver no ar, rode o teste.bat da raiz.
    echo          ^(Se voce esta subindo os dois agora, pode ignorar isto.^)
    echo.
) else (
    echo  API respondendo em 192.168.0.50:8020 - OK.
    echo.
)

echo  Para encerrar: CTRL+C e responda S, ou feche esta janela no X.
echo  ------------------------------------------------------------
echo.

npm run dev

echo.
echo  ------------------------------------------------------------
echo  Servidor encerrado.

:fim
echo.
pause
endlocal
