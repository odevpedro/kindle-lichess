# Arquitetura

## Visão

```text
KOReader
  kindlelichess.koplugin (Lua)
    UI e-ink, reconstrução FEN+UCI, relógio monotônico
             │ Unix socket / JSON Lines v1
             ▼
  kindle-lichess-bridge (Go, filho por sessão)
    token, HTTPS, NDJSON, reconexão e comandos
             │ TLS, somente lichess.org
             ▼
  Lichess Board API (fonte de verdade)
```

## Plugin Lua

Registra menu; inicia/encerra bridge; usa socket sem bloquear UI; valida protocolo; mostra desafio/partida/conexão; reconstrói somente `initialFen + moves`; valida localmente apenas UX; mantém relógio visual econômico; faz refresh regional e full refresh ocasional.

## Bridge Go

Lê token de arquivo 0600; valida conta; mantém um event stream global e um game stream; parseia NDJSON incremental; serializa mutations; trata 401/403/404/429/Retry-After; não repete POST ambíguo sem reconciliar; usa contexto/backoff/jitter; sanitiza logs; trata SIGTERM.

## Estado da partida

1. `gameFull` define metadados, `initialFen` e snapshot.
2. Cada `gameState` traz a lista UCI completa e relógios.
3. Snapshot igual é duplicata; prefixo acrescenta lances; histórico menor/divergente ou reconexão invalida transitório.
4. A posição é sempre reconstruída; a diferença entre posição anterior/nova define casas sujas.
5. Toque local é intenção pending; somente stream altera estado confirmado.

MVP aceita apenas variante `standard` e Rapid/Classical/Correspondence. Blitz não é suportado inicialmente.

## Relógio

Snapshot `{serverWtime, serverBtime, receivedAtMonotonic, activeColor, estimatedLatency}`. O lado ativo é calculado sob demanda e todo `gameState` corrige deriva. Redraw após snapshot/lance/diálogo/reconexão, em intervalos econômicos e mais curto apenas com pouco tempo.

## Concorrência/reconexão

Um event stream por token; um game stream; uma fila de POST. `Retry-After` prevalece em 429. EOF terminal é normal; EOF com `started` reconecta. Resposta perdida de movimento é reconciliada pelo stream antes de novo envio.

## Ciclo de vida

Tela abre → plugin inicia filho → bridge cria socket 0600 → plugin conecta/envia `connect`. Ao fechar: `disconnect`, fechamento IPC, SIGTERM, cancelamento de streams, remoção do socket próprio e wait do filho. Sem daemon, autostart, Upstart, cron, HTTP ou TCP.

## ADRs

- [ADR-0001 — KOReader Lua + Go](adr/0001-koreader-go-bridge.md)
- [ADR-0002 — Unix socket + JSONL](adr/0002-unix-socket-jsonl.md)
- [ADR-0003 — servidor autoritativo](adr/0003-server-authoritative-state.md)
- [ADR-0004 — sem engine](adr/0004-no-engine-online.md)
- [ADR-0005 — ciclo por sessão](adr/0005-session-lifecycle.md)
- [ADR-0006 — Lichess falso permanente de contrato](adr/0006-contract-fake-lichess.md)
