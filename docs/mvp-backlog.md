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
- P2 coordenadas no tabuleiro (números `1–8` e letras `a–h`) com fonte pequena, sem
  obstruir peças, seguidas do projeto atual e da densidade de pixels do KT4.
- P1 ✔ Criar desafio no app (não só aceitar os recebidos): direto por usuário
  (`/api/challenge/{username}`, protocolo `create_challenge`/`cancel_challenge`,
  InputDialog no lobby e estado "aguardando aceite"; instantâneo no mock). Resta:
  seek aberto por URL (`/api/challenge/open`), para jogar contra qualquer conta
  além da própria.
- P1 ✔ Seeker automático "Jogar com alguém (10+5 casual)" — `POST /api/board/seek`
  acha oponente aleatório de elo próximo (obrigatório: bridge, protocolo seek/cancel_seek,
  botão no lobby e estado de busca; instantâneo no mock). Faltam: cancelar via socket e ajuste de tempos.
  Obs.: cancelar via socket (`cancel_seek`) já foi entregue.
- P2 "login" no aparelho via token: tela amigável para colar o token `board:play`
  (teclado virtual do KOReader ou leitura de um arquivo em `/mnt/us`), sem depender
  de SSH/CLI para configurar o plugin.
- P0 ✔ Corrigir crash ao renderizar o resultado no KT4: substituída a face inexistente
  `front` por `cfont`; teste de integração pinta de verdade as telas de vitória,
  derrota, empate e aborto para impedir regressão em `frontend/ui/font.lua`.
- P2 ◐ exibir peças capturadas/material abaixo dos jogadores, no estilo Lichess/Chess.com
  (implementado localmente; aguarda validação visual no runtime KOReader e no KT4).
  Derivar exclusivamente de `initialFen + moves` confirmados pelo stream (sem avaliação
  ou engine), mostrar as peças perdidas por cada lado e, opcionalmente, a diferença
  material convencional. A reconstrução deve tratar capturas normais, en passant,
  promoções, posição inicial customizada, histórico divergente e reconexão, sem
  aplicar intenção local pendente.

## Fora do MVP

Matchmaking, torneios, chat, histórico completo, análise, puzzles, computador, Blitz, OAuth público e home Amazon. OAuth2 PKCE é obrigatório antes de publicação geral.

O Lichess não aceita usuário/senha direto na API — toda autenticação é OAuth2. Para um público mais amplo: fluxo OAuth2 authorization code/PKCE via link de login externo, ou (recomendado no Kindle, que não tem navegador/redirect) manter o token pessoal com UX de colar token no próprio device.
