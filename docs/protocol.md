# Protocolo Lua–Go

## Transporte/framing

- Unix stream socket `/tmp/kindle-lichess.sock`, modo 0600, um cliente.
- Uma mensagem JSON UTF-8 compacta por linha (`\n`); CRLF é normalizado.
- Limite de 65.536 bytes incluindo newline. Excesso fecha a sessão IPC sem alocação ilimitada.
- Reads podem conter fragmento, linha ou várias linhas; fragmentos aguardam newline.
- Linha vazia no IPC é ignorada. JSON inválido gera erro recuperável por linha.
- Campos desconhecidos são ignorados; obrigatórios/tipos/limites são validados.
- Token é proibido em toda mensagem.

## Envelope v1

Toda mensagem exige `v: 1` e `type` (enum, 1–64 chars). `requestId` é obrigatório para comandos com efeito; formato `[A-Za-z0-9_-]{1,64}`. O bridge guarda 128 resultados da sessão para não repetir um `requestId`.

IDs de jogo/desafio: ASCII 1–32. UCI standard: `^[a-h][1-8][a-h][1-8][qrbn]?$`. `timeControl` é string `"limit+increment"` (em segundos, ex. `"600+5"`). `username` é ASCII 3–32 (`[A-Za-z0-9_-]`). Strings humanas têm limite e escape na UI.

Na borda HTTP, o bridge converte esse formato canônico: seek usa `time` em minutos e
`increment` em segundos; desafio direto usa `clock.limit` e `clock.increment` em
segundos. A UI aceita `minutos+incremento` e persiste somente a forma canônica em segundos.

## Plugin → bridge

| `type` | Campos | Efeito |
|---|---|---|
| `connect` | — | valida conta e abre event stream |
| `disconnect` | — | cancelamento/saída limpa |
| `accept_challenge` | `challengeId` | POST accept |
| `decline_challenge` | `challengeId`, `reason?` | POST decline |
| `open_game` | `gameId` | abre/substitui game stream |
| `close_game` | `gameId` | fecha stream da partida |
| `move` | `gameId`, `move` | envia UCI sem aplicação otimista |
| `offer_draw` | `gameId` | POST draw/yes |
| `accept_draw` | `gameId` | POST draw/yes com oferta remota |
| `decline_draw` | `gameId` | POST draw/no |
| `resign` | `gameId` | POST resign |
| `abort` | `gameId` | POST abort quando permitido |
| `seek` | `rated`, `timeControl` | POST `/api/board/seek` |
| `cancel_seek` | — | POST `/api/board/seek/cancel` |
| `create_challenge` | `username`, `rated?`, `timeControl` | POST `/api/challenge/{username}` |
| `cancel_challenge` | `challengeId` | POST `/api/challenge/{challengeId}/cancel` (desafio outbound) |
| `send_chat` | `gameId`, `room:"player"`, `text` | envia chat privado da partida, sem retry automático |
| `ping` | `nonce` | responde `pong` |

```json
{"v":1,"type":"move","requestId":"s1-17","gameId":"BEOucQJo","move":"e2e4"}
```

## Bridge → plugin

| `type` | Campos principais |
|---|---|
| `connected` | `account:{id,username,title?}` |
| `challenge` | `challenge` normalizado |
| `challenge_canceled` | `challengeId` |
| `challenge_declined` | `challengeId`, `reason?` |
| `game_start` / `game_finish` | `game` normalizado |
| `game_full` / `game_state` | `gameId`, `state` normalizado |
| `chat_line` | `gameId`, `room:"player"`, `username`, `text` |
| `opponent_gone` | `gameId`, `gone`, `claimWinInSeconds?` |
| `command_ok` | `requestId`, `command` |
| `move_rejected` | `requestId`, `gameId`, `move`, `reason` |
| `reconnecting` | `stream`, `retryIn`, `attempt` |
| `disconnected` | `reason`, `retryIn?` |
| `error` | `code`, `message`, `requestId?`, `fatal` |
| `pong` | `nonce` |

`game_full.state`: id, variant, speed, rated, createdAt, jogadores reduzidos, `initialFen`, clock opcional, daysPerTurn opcional e `gameState`.

`game_state.state`: `moves`, `wtime`, `btime`, `winc`, `binc`, `status`; opcionais `winner`, `wdraw`, `bdraw`, `expiration`. Tempos são inteiros em milissegundos com limite defensivo.

Challenge normalizado: id, direction, status, rated, speed, variant, timeControl, color e usuários reduzidos. Campos brutos não atravessam por padrão.

Chat é restrito à sala privada `player`. Saída aceita de 1 a 280 bytes sem controles;
entrada aceita até 1.024 bytes. O plugin mantém no máximo 40 mensagens somente em
memória. A sala `spectator` é descartada, mensagens não entram em logs/PGN e o POST não
é repetido automaticamente após timeout para evitar duplicação.


## Confirmação/idempotência

`command_ok` significa somente HTTP 2xx; a posição muda apenas quando `game_state.moves` inclui o lance. Em timeout/EOF após POST, não repetir mutation cegamente: reabrir/aguardar stream e reconciliar.

Duplicata de `requestId` devolve cache. Evento com moves idênticos não redesenha. Histórico menor/divergente força reconstrução completa.

## Erros mínimos

`unsupported_version`, `unknown_type`, `invalid_json`, `message_too_large`, `invalid_field`, `not_connected`, `token_missing`, `token_permissions`, `auth_unauthorized`, `auth_forbidden`, `not_found`, `rate_limited`, `network_timeout`, `stream_eof`, `socket_unavailable`, `lichess_rejected`, `internal`.

Nunca incluir Authorization, token, body bruto sensível ou conteúdo/caminho de token. Mensagens externas são truncadas e sanitizadas.

Adicionar campo opcional é compatível. Remover/renomear campo, unidade ou semântica exige nova versão.
