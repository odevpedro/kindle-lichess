# Riscos técnicos

| Risco | Prob. | Impacto | Mitigação/gate |
|---|---:|---:|---|
| chess.lua sem licença | Alta | Crítico | não copiar; licenciar/substituir |
| Go incompatível com kernel KT4 | Média | Crítico | binário mínimo + execução autorizada |
| CA roots/DNS/TLS | Média | Alto | teste isolado; nunca desabilitar TLS |
| RSS Go excessivo | Média | Alto | medir idle/streams/pico e definir orçamento |
| FFI Unix socket variável | Média | Alto | adaptador pequeno, testes desktop/32-bit |
| filho zumbi/sobrevivente | Média | Alto | PID, SIGTERM, cancel, waitpid e testes |
| fragmentos NDJSON/JSONL perdidos | Média | Crítico | buffer incremental/todas fragmentações |
| POST repetido após timeout | Média | Alto | fila/requestId/reconciliação sem retry cego |
| divergência após reconexão | Média | Crítico | descartar transitório e reconstruir |
| roque UCI especial | Média | Alto | vetores; standard apenas |
| relógio/ghosting | Alta | Médio | monotônico, correção server, refresh adaptativo |
| tempestade/rate limit | Média | Alto | um event stream, Retry-After, backoff+jitter |
| token vaza | Baixa | Crítico | 0600, allowlist, canário, secret scan |
| aceitar desafio incompatível | Média | Alto | validar variant/speed antes de habilitar |
| mudança API KOReader | Média | Médio | pin/abstração/teste por versão |
| licença SVG incompleta | Média | Alto | inventário/NOTICE antes do fork distribuído |

## Critérios de parada

Licença incerta; ELF/ABI inesperado; cgo/dependência inesperada; TLS só sem validação; token em saída; processo/socket residual; divergência do Lichess; escrita fora dos caminhos; comportamento inesperado no Kindle.
