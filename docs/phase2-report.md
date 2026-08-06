# Relatório de aceitação — Fase 2

Data: 2026-08-06  
Branch: `phase/2-bridge-simulated`  
Baseline: `phase/1-mock-ui@1677ad5`

## Resultado

A camada de rede simulada está implementada sem token e sem acesso ao Lichess real. O
bridge Go fala Board API por HTTPS, processa streams NDJSON incrementalmente, expõe uma
única sessão em Unix socket e encerra junto com a tela. O adaptador Lua usa o loop de
eventos do KOReader e I/O não bloqueante.

O plugin continua selecionando `MockBridge` por padrão. O adaptador real foi construído
e testado, mas só será ativado na Fase 3, quando existir configuração local de token e o
gate explícito para integração real no computador.

## Por que o servidor falso não é retrabalho

O falso Lichess não é um segundo produto nem um clone do site. São handlers locais
`net/http/httptest`, compilados apenas durante testes e mantidos como testes de contrato.
Eles continuam úteis depois da integração real porque reproduzem, de forma determinística:

- chunks NDJSON partidos, agrupados, vazios e truncados;
- EOF inesperado e reconexão;
- HTTP 401, 403, 404 e 429 com `Retry-After`;
- movimento aceito ou recusado e partida terminal;
- cancelamento, timeout e fechamento dos streams;
- detecção de vazamento de credencial.

Nenhum servidor falso, porta TCP ou fixture HTTP entra no pacote do Kindle.

## Mudanças entregues

### Go

- framing JSON Lines limitado a 65.536 bytes;
- validação v1, campos desconhecidos compatíveis e campos secretos proibidos;
- leitura de token somente de arquivo regular `0600`, sem caminho ou conteúdo em erros;
- cliente para todos os endpoints Board API previstos no MVP;
- streams account/game, cancelamento por contexto e reconexão com backoff/`Retry-After`;
- normalização mínima de conta, desafio, partida e estado;
- mutations serializadas e cache dos últimos 128 `requestId`;
- Unix socket absoluto `0600`, um cliente, remoção segura por inode;
- executável por sessão, destino fixo `https://lichess.org`, tratamento de `SIGTERM`;
- fechamento concorrente sincronizado: o processo só retorna após remover o socket.

### Lua/KOReader

- transporte Unix via FFI POSIX, porque o LuaSocket embarcado não oferece
  `socket.unix`;
- socket não bloqueante e `FD_CLOEXEC`;
- fila de saída limitada, escrita parcial e até oito reads curtos por ciclo;
- conexão com retry por dois segundos, sem bloquear a interface;
- framing incremental com keep-alive, CRLF, múltiplas linhas e limite defensivo;
- registro/remoção no loop de eventos do KOReader;
- lançamento por `fork/exec` sem shell e supervisão do grupo de processos;
- encerramento com `SIGTERM` e fallback `SIGKILL` somente após dois segundos.

## Autoridade, segurança e fair play

O bridge envia `command_ok` apenas para confirmar HTTP 2xx. O tabuleiro continua mudando
somente ao receber `game_full` ou `game_state`; uma reconexão reabre o stream e o
snapshot volta a ser a autoridade.

O destino do executável não é configurável: o token só pode ser enviado a
`https://lichess.org`. Erros externos são convertidos em códigos curtos e nunca carregam
body bruto, Authorization, conteúdo ou caminho do token. O IPC rejeita campos chamados
`token`, `authorization` ou `access_token`, inclusive aninhados.

Não há engine, Stockfish, processo UCI, avaliação, explorer, tablebase ou análise. O
servidor HTTP falso existe apenas em arquivos `*_test.go`.

## Evidências de teste

Comandos reproduzíveis:

```sh
./scripts/test-go.sh
KOREADER_SOURCE=/tmp/kindle-lichess-phase0-koreader ./scripts/test.sh
```

Resultados obtidos:

| Camada | Resultado | Cobertura principal |
|---|---:|---|
| Go estático | aprovado | `gofmt` e `go vet ./...` |
| Go concorrente | 8/8 pacotes | `go test -race ./...`, incluindo HTTP falso e socket real |
| runner Lua | 64/64 | posição, toque, relógio, protocolo e MockBridge |
| Busted/KOReader | 6/6 | widgets, sessão mock, JSONL, processo e socket Unix FFI real |
| shell | aprovado | `bash -n scripts/test.sh scripts/test-go.sh` |

Toolchains fixadas:

- `golang:1.26.5-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599`;
- `koreader/koappimage@sha256:4416f7b137b1eda49eb486bbe00dd00a347f0f126a649bf75bf1edc8d4877828`.

Nenhuma dependência foi instalada no host.

## Arquivos da Fase 2

- Go: `bridge/cmd/kindle-lichess-bridge` e
  `bridge/internal/{app,auth,ipc,lichess,protocol,reconnect,stream}`;
- Lua: `bridge/{process,socket_bridge,unix_transport}.lua`;
- testes: arquivos `*_test.go`, `tests/koreader_spec.lua` e
  `scripts/test-go.sh`;
- documentação: ADR-0006, protocolo, arquitetura, plano de testes e este relatório;
- exemplo: `token.example`, sem credencial.

## Riscos residuais

| Risco | Situação ao encerrar a fase | Próximo controle |
|---|---|---|
| contrato público mudou | fixtures refletem a especificação congelada, não produção | validar docs e desafio casual na Fase 3 |
| TLS/certificados/rede real | cliente foi exercitado somente contra HTTP local | HTTPS real no computador na Fase 3 |
| processo Lua + binário juntos | transporte, supervisão e sessão foram testados por camadas | ativar o adaptador e executar o binário nativo na Fase 3 |
| consumo/RSS | ainda não medido | binário mínimo e medições na Fase 4 |
| kernel ARMv7 | não presumido por testes x86_64 | `file`, `readelf` e execução isolada nas Fases 4/6 |
| e-ink/Wi-Fi/suspensão | hardware permanece intocado | somente após auditoria e autorização nas Fases 5/6 |

## Gate para a Fase 3

A próxima fase é integração real exclusivamente no computador. Antes de qualquer chamada,
deve ser criado manualmente um token de conta separada com escopo mínimo `board:play`,
salvo em arquivo local `0600`. O token nunca será pedido no chat.

A Fase 3 começa com `GET /api/account` e um desafio direto casual Standard Rapid. Não
há autorização para Kindle, build ARM ou transferência de arquivos.
