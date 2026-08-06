# ADR-0003 — Lichess como fonte de verdade

Status: aceito.

Estado confirmado é sempre `gameFull.initialFen + gameState.moves`. Jogadas locais são intenções. Reconexão é determinística, duplicatas são inofensivas e rejeições não exigem rollback heurístico.
