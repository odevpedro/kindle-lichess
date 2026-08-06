# API oficial do Lichess

Base: [`lichess-org/api`](https://github.com/lichess-org/api), commit `b2085f7df37481cdac98f385711843f94d2d67b6`. Produção fixa em `https://lichess.org`.

| Método/caminho | Uso |
|---|---|
| `GET /api/account` | validar token/conta |
| `GET /api/stream/event` | desafios e início/fim; NDJSON; keep-alive vazio ~7s; um stream/token |
| `GET /api/board/game/stream/{gameId}` | estado; primeira linha `gameFull`; fecha ao terminar |
| `POST /api/challenge/{challengeId}/accept` | aceitar; aguardar `gameStart` |
| `POST /api/challenge/{challengeId}/decline` | recusar, reason opcional |
| `POST /api/board/game/{gameId}/move/{move}` | UCI; 400 rejeita; 200 reconcilia pelo stream |
| `POST /api/board/game/{gameId}/draw/{accept}` | literais `yes`/`no` |
| `POST /api/board/game/{gameId}/resign` | desistir após confirmação UI |
| `POST /api/board/game/{gameId}/abort` | somente se estado permitir |

Sem Bot API, scraping, endpoints internos, chat, seek/matchmaking, torneios, análise, explorer ou tablebase.

## NDJSON/estado

Buffer até newline; vazia é keep-alive. EOF com `started` reconecta; após terminal é normal. A abertura do event stream reenvia desafios/partidas correntes, logo consumo é idempotente.

`gameState.moves` é lista UCI completa; relógios em ms. A especificação alerta para notação king-to-rook compatível com Chess960 no roque. O MVP rejeita variante não standard, mas testa/normaliza o roque sem pressuposição silenciosa.

## HTTP/rate limit

Mutations serializadas. Streams long-lived usam conexões próprias. Em 429, `Retry-After` prevalece; ausente, espera conservadora de pelo menos a orientação oficial e frequência reduzida. Tratar separadamente 401, 403, 404, 429, timeout, cancelamento e EOF.

## Auth/política MVP

Mocks sem token. Fase 3: PAT manual somente `board:play`, arquivo 0600, conta separada. Publicação: Authorization Code + PKCE S256; clientes públicos são aceitos, não há refresh token.

Somente conta humana, desafio direto casual primeiro, standard, Rapid/Classical/Correspondence. Blitz fica fora do MVP embora possa ser permitido em desafio direto.
