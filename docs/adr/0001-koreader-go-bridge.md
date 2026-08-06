# ADR-0001 — Plugin KOReader Lua e bridge Go

Status: aceito com gate de compatibilidade.

## Decisão

UI em `kindlelichess.koplugin`; rede em `kindle-lichess-bridge`. Build: `CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7`.

KOReader já fornece UI e refresh e-ink; Go fornece HTTP/TLS/context/stream sem Python, Node, JVM, browser ou cgo.

## Gate

“Sem cgo” não prova kernel, ABI, DNS, CA roots ou RAM. Antes da adoção definitiva: binário mínimo, versão Go fixada, `file`, `readelf -h/-A`, dependências, hash, RSS e execução isolada autorizada. Falha reabre o ADR; não autoriza outra stack automaticamente.
