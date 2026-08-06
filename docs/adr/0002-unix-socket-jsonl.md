# ADR-0002 — Unix domain socket e JSON Lines

Status: aceito.

IPC em `/tmp/kindle-lichess.sock`, `SOCK_STREAM`, modo 0600, um cliente, UTF-8 JSON Lines v1. Sem TCP/HTTP. Framing terá buffer incremental/limite; Lua usa I/O não bloqueante testado no desktop antes do dispositivo.
