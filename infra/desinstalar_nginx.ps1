# ============================================================================
# Remove o vhost do Dashboard de Compras do nginx desta maquina.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File infra\desinstalar_nginx.ps1
#
# O que faz, NESTA ordem (nunca fora dela):
#   1. Backup do nginx.conf atual -> nginx.conf.bkp-desinstalar-<AAAAMMDD>
#      (backup extra, alem do que instalar_nginx.ps1 ja fez - nunca custa)
#   2. Remove a linha "include compras.conf;" de dentro do http{}
#   3. Roda "nginx -t"
#      Se o -t falhar: restaura o backup deste passo (nginx.conf volta a
#      incluir compras.conf) e NAO recarrega. O compras.conf NAO e removido
#      neste caso - continua no disco, coerente com o include restaurado.
#   4. SO SE o -t passar: remove C:\nginx\conf\compras.conf
#      (so agora, porque o arquivo so pode sumir depois que a config sem o
#      include ja foi provada valida - nunca antes. Um compras.conf orfao no
#      disco, sem include apontando pra ele, e inofensivo; um include
#      apontando pra um arquivo ja removido, se o -t tivesse falhado com o
#      arquivo ja apagado, deixaria o nginx sem subir no proximo reload/boot -
#      e ai gestaosac.cdp.lub e dre.cdp.lub cairiam junto.)
#   5. "nginx -s reload"
# ============================================================================

$NginxDir     = "C:\nginx"
$NginxConf    = Join-Path $NginxDir "conf\nginx.conf"
$NginxExe     = Join-Path $NginxDir "nginx.exe"
$VhostDestino = Join-Path $NginxDir "conf\compras.conf"
$DataHoje     = Get-Date -Format "yyyyMMdd"
$Backup       = Join-Path $NginxDir "conf\nginx.conf.bkp-desinstalar-$DataHoje"

Write-Host ""
Write-Host "========================================================================="
Write-Host " DESINSTALAR VHOST NGINX - compras.cdp.lub"
Write-Host "========================================================================="
Write-Host ""

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Host " [ERRO] Este script precisa rodar como Administrador."
    Write-Host " O que fazer: clique com o botao direito em PowerShell e escolha 'Executar como Administrador'."
    Exit 1
}

if (-not (Test-Path $NginxConf)) {
    Write-Host " [ERRO] Nao encontrei $NginxConf."
    Exit 1
}

# --- 1. Backup, sempre, antes de qualquer mudanca -------------------------
Copy-Item $NginxConf $Backup -Force
Write-Host " Backup criado: $Backup"

# --- 2. Remove a linha include ---------------------------------------------
$Conteudo = Get-Content $NginxConf -Raw
$NovoConteudo = $Conteudo -replace "[ \t]*include[ \t]+compras\.conf;\r?\n?", ""
if ($NovoConteudo -ne $Conteudo) {
    Set-Content -Path $NginxConf -Value $NovoConteudo -NoNewline
    Write-Host " Linha 'include compras.conf;' removida de nginx.conf."
} else {
    Write-Host " nginx.conf nao tinha o include - nada a remover ali."
}

# --- 3. Testa ANTES de remover o arquivo (NAO OPCIONAL) --------------------
# Ordem critica: so removemos compras.conf depois que o nginx.conf SEM o
# include ja foi provado valido. Enquanto o arquivo ainda existe no disco,
# qualquer falha aqui e revertida so restaurando o nginx.conf - o compras.conf
# nao precisa de rollback porque nunca foi tocado.
Write-Host ""
Write-Host " Rodando 'nginx -t'..."
$TesteSaida = & $NginxExe -t -p $NginxDir -c "conf\nginx.conf" 2>&1
Write-Host $TesteSaida
$TesteOk = ($LASTEXITCODE -eq 0)

if (-not $TesteOk) {
    Write-Host ""
    Write-Host " [ERRO] 'nginx -t' falhou apos remover o include. Restaurando o backup e NAO recarregando."
    Copy-Item $Backup $NginxConf -Force
    Write-Host " compras.conf NAO foi removido - nginx.conf restaurado ainda o referencia."
    Write-Host " O que fazer: confira $Backup a mao antes de tentar de novo."
    Exit 1
}

# --- 4. So agora, com a config ja provada valida, remove o vhost -----------
if (Test-Path $VhostDestino) {
    Remove-Item $VhostDestino -Force
    Write-Host " Removido: $VhostDestino"
}

# --- 5. So recarrega se o -t passou ---------------------------------------
# Mesmo raciocinio do instalar_nginx.ps1 (ver comentario la e infra/README.md):
# nesta maquina o "-s reload" costuma falhar com "Access is denied" porque o
# servico roda como LocalSystem e esta sessao de Administrador nao consegue
# sinalizar o evento Global\ngx_reload_<pid>. Aqui o risco de nao perceber e
# MAIOR que na instalacao: se o reload falhar em silencio, o vhost some do
# disco mas continua respondendo na memoria do nginx - parece desinstalado e
# nao esta. Por isso a mesma checagem de exit code + o mesmo fallback
# (Restart-Service, so quando o erro reconhecido aparecer) + a mesma
# confirmacao por processo novo.
$ProcessosAntes = Get-Process nginx -ErrorAction SilentlyContinue | Select-Object Id, StartTime

Write-Host ""
Write-Host " 'nginx -t' passou. Recarregando..."
$ReloadSaida = & $NginxExe -s reload -p $NginxDir -c "conf\nginx.conf" 2>&1
$ReloadExit  = $LASTEXITCODE

if ($ReloadExit -ne 0) {
    Write-Host " [AVISO] 'nginx -s reload' terminou com codigo $ReloadExit :"
    Write-Host " $ReloadSaida"

    if ($ReloadSaida -match "Access is denied" -or $ReloadSaida -match "ngx_reload_") {
        Write-Host ""
        Write-Host " Causa conhecida nesta maquina (ver infra/README.md): o servico roda como"
        Write-Host " LocalSystem e esta sessao nao consegue sinalizar o evento de reload."
        Write-Host " Aplicando o fallback: 'Restart-Service Nginx -Force' (o config ja foi"
        Write-Host " validado pelo 'nginx -t' acima, entao reiniciar e seguro)."
        Restart-Service Nginx -Force
        Start-Sleep -Seconds 1
    } else {
        Write-Host ""
        Write-Host " [ERRO] O reload falhou por um motivo que NAO e o 'Access is denied'"
        Write-Host " conhecido nesta maquina. NAO vou reiniciar o servico as cegas."
        Write-Host " O que fazer: rode 'C:\nginx\nginx.exe -s reload' a mao, leia o erro, e so"
        Write-Host "              entao decida corrigir ou reiniciar o servico manualmente."
        Write-Host " ATENCAO: ate isso ser resolvido, o vhost pode ter sumido do disco mas"
        Write-Host "          continuar respondendo - NAO considere isto desinstalado."
        Exit 1
    }
}

# --- Confirma que a mudanca REALMENTE entrou em vigor - ver comentario
#     equivalente em instalar_nginx.ps1.
Start-Sleep -Milliseconds 500
$IdsAntes        = @($ProcessosAntes | ForEach-Object { $_.Id })
$ProcessosDepois = Get-Process nginx -ErrorAction SilentlyContinue
$Aplicou = $false
foreach ($p in $ProcessosDepois) {
    if ($IdsAntes -notcontains $p.Id) { $Aplicou = $true }
}

if (-not $Aplicou) {
    Write-Host ""
    Write-Host " [ERRO] Nenhum processo nginx novo apareceu depois do reload/restart."
    Write-Host " O vhost foi removido do DISCO, mas pode continuar respondendo na MEMORIA"
    Write-Host " do nginx - NAO considere isto desinstalado."
    Write-Host " O que fazer: rode 'Get-Process nginx' e '$NginxExe -s reload' a mao para"
    Write-Host "              investigar antes de dar isto por encerrado."
    Exit 1
}

Write-Host ""
Write-Host " Vhost removido e nginx recarregado com sucesso - confirmado: processo(s)"
Write-Host " novo(s) no ar."
Write-Host " Confira que gestaosac.cdp.lub e dre.cdp.lub continuam respondendo."
Write-Host ""
