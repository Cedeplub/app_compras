# `infra/` — subir e derrubar a produção do Dashboard de Compras

Tudo aqui é script versionado. Nenhum passo de subida é comando digitado numa
janela: comando digitado não sobrevive à pessoa que digitou.

## Os arquivos

| Arquivo | Papel |
|---|---|
| `instalar_servico.ps1` | cria o serviço NSSM `app_compras` (uvicorn, sem `--reload`) |
| `desinstalar_servico.ps1` | para e remove o serviço `app_compras` |
| `nginx/compras.conf` | o vhost do dashboard, versionado — a cópia real fica em `C:\nginx\conf\compras.conf` |
| `instalar_nginx.ps1` | copia o vhost, acrescenta o `include` em `nginx.conf`, testa e recarrega |
| `desinstalar_nginx.ps1` | remove o `include` e o arquivo, testa e recarrega |
| `agendar_atualizacao.ps1` | cria a Tarefa Agendada diária do dbt (`dbt seed`+`run`+`test`) |
| `publicar.ps1` | `npm ci` + `npm run build` + reinício do serviço — o caminho único para colocar um front novo no ar |

## A constante `<BIND>`

O endereço em que o uvicorn escuta aparece em **dois lugares**: o topo de
`instalar_servico.ps1` e o comentário equivalente em `nginx/compras.conf`
(usado no `proxy_pass`). Hoje os dois valem `192.168.0.50`, por causa do
socket órfão em `0.0.0.0:8020` (PID 2240, morto desde 25/08/2026 — ver
`CONTEXTO.md`). Depois do primeiro reinício autorizado desta máquina, os dois
viram `127.0.0.1` — é uma linha para trocar em cada arquivo, não uma caçada.

## Ordem de instalação

1. Confirme que a porta 8020 está livre no endereço `<BIND>` atual
   (`Get-NetTCPConnection -LocalPort 8020`). Se houver processo vivo do
   `teste.bat` antigo, derrube-o antes.
2. `powershell -ExecutionPolicy Bypass -File infra\instalar_servico.ps1`
3. Confirme `Get-Service app_compras` → `Running` / `Automatic`.
4. `powershell -ExecutionPolicy Bypass -File infra\instalar_nginx.ps1`
5. Confirme `http://192.168.0.50/` abre a tela, e que
   `gestaosac.cdp.lub` e `dre.cdp.lub` continuam respondendo.
6. `powershell -ExecutionPolicy Bypass -File infra\agendar_atualizacao.ps1`
   (depois de rodar `Unregister-ScheduledTask` na tarefa antiga, que aponta
   para a pasta velha).
7. Quando houver front novo para publicar:
   `powershell -ExecutionPolicy Bypass -File infra\publicar.ps1`

## Ordem de desinstalação (a ordem inversa, de propósito)

O momento de precisar desta lista é o pior momento para deduzi-la.

1. `powershell -ExecutionPolicy Bypass -File infra\desinstalar_nginx.ps1`
   — restaura o backup do `nginx.conf`, roda `nginx -t`, recarrega. Confirme
   que `gestaosac.cdp.lub` e `dre.cdp.lub` seguem no ar.
2. `powershell -ExecutionPolicy Bypass -File infra\desinstalar_servico.ps1`
   — `nssm stop app_compras` + `nssm remove app_compras confirm`.
3. `Unregister-ScheduledTask -TaskName "CEDEP - app_compras - atualizar dados"`
4. Suba pelo modo de desenvolvimento: `teste.bat` (API, porta 8020) e
   `teste_front.bat` (front, porta 5173) — **não dependem de nada instalado**
   e são sempre o caminho de volta.

## O `nginx -s reload` falha nesta máquina (comportamento conhecido)

O serviço `Nginx` roda como `LocalSystem` (padrão NSSM/serviço Windows). O
`nginx -s reload` sinaliza o master via um evento nomeado
`Global\ngx_reload_<pid>`; uma sessão de Administrador comum **não consegue**
sinalizar um evento criado por `LocalSystem` — o comando termina com:

```
nginx: [error] OpenEvent("Global\ngx_reload_<pid>") failed (5: Access is denied)
```

e código de saída ≠ 0. **Isso é o normal nesta máquina, não uma exceção.**
`instalar_nginx.ps1` e `desinstalar_nginx.ps1` tratam esse caso: quando o
`-s reload` falha com exatamente esse erro, o script recorre a
`Restart-Service Nginx -Force` — seguro porque o `nginx -t` já validou o
config em disco antes disso. Qualquer *outro* erro do reload não aciona esse
fallback: o script para e avisa, em vez de reiniciar às cegas.

Reload é gracioso (conexões em curso terminam sozinhas); restart derruba tudo
por um instante. Como há dois vhosts de outras áreas (`gestaosac.cdp.lub`,
`dre.cdp.lub`) no mesmo `nginx.conf`, o reload continua sendo o caminho
padrão tentado primeiro — o restart é só o fallback automático para este erro
específico, não a troca do padrão.

Os dois scripts também conferem, depois do reload/restart, se apareceu
processo `nginx` com PID novo — é a prova de que a config saiu do disco e
entrou em memória, não só que o comando não retornou erro.

## O que NÃO fazer

- Não recarregar o nginx sem o `nginx -t` ter passado antes —
  `gestaosac.cdp.lub` e `dre.cdp.lub` são produção de outras áreas no mesmo
  `nginx.conf`.
- Não subir o serviço com `--reload`.
- Não reiniciar a máquina por conta própria — derruba outros uvicorns em
  produção nesta máquina (portas 8010, 8000, 8001, 8077, 8100). É decisão do
  usuário, não do executor.
