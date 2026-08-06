# Backlog do MVP

P0 bloqueia MVP; P1 robustez necessária; P2 pós-MVP.

## Fase 1 — Mock UI

- P0 fork rastreável `kindlelichess.koplugin`, sem sobrescrever Kochess.
- P0 resolver/substituir regras antes de incluí-las.
- P0 remover UCI/engine/Elo/análise e binários/assets relacionados.
- P0 menu, conexão, desafio aceitar/recusar via MockBridge.
- P0 tabuleiro orientado, origem–destino, promoção grande.
- P0 reconstrução FEN+moves, duplicata/divergência.
- P0 relógios econômicos, resultado, empate, desistência confirmada e abort permitido.
- P0 fechar sem tarefas/processos pendentes.
- P1 último lance, refresh regional/full anti-ghosting e cenários desktop completos.

## Fase 2 — Bridge simulado

- P0 JSONL v1, validação e Unix socket 0600.
- P0 processo por sessão/SIGTERM e parser NDJSON incremental.
- P0 Board API contra servidor HTTP local: streams, comandos, reconexão.
- P0 auth por arquivo 0600 sem token real; 401/403/404/429/Retry-After/timeouts.
- P1 logs sanitizados, fila single-flight e dedupe requestId.

## Fase 3 — Integração real no computador

- Gate: solicitar token `board:play` só aqui.
- P0 conta separada, desafio direto casual standard Rapid e fluxo/reconexão completos.

## Fase 4 — ARM

- P0 binário mínimo sem cgo antes do bridge completo.
- P0 `file`/`readelf`/dependências/kernel/RSS/checksums e build reproduzível.

## Fase 5 — Pré-instalação

- P0 árvore, scripts integrais, hashes, ausência de engine/token/autostart, caminhos e reversão.
- Gate: autorização explícita para transferência.

## Fase 6 — Kindle

- P0 transferir só após gate; MockBridge primeiro; validar processo/socket/RAM/refresh/rede/limpeza.
- P0 conta real só depois; parar ante comportamento inesperado.

## Fora do MVP

Matchmaking, torneios, chat, histórico completo, análise, puzzles, computador, Blitz, OAuth público e home Amazon. OAuth2 PKCE é obrigatório antes de publicação geral.
