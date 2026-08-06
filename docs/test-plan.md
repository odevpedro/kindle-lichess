# Plano de testes

Nenhum resultado futuro é alegado na Fase 0.

## Lua

- seleção/deseleção/troca, toque inválido e fora da vez;
- orientação branca/preta e 64 mapeamentos;
- promoção q/r/b/n/cancelamento/rejeição;
- startpos/FEN custom + UCI; roque/en passant/captura e casas sujas;
- evento idêntico/prefixo/menor/divergente;
- JSON inválido, versão, campo, desconhecido e oversized;
- reconexão visual, relógio monotônico/correção/redraw;
- fechamento cancela timers/socket/filho.

Widgets rodam no harness KOReader desktop. Regras usam perft e diferencial contra referência licenciada apenas em teste offline, nunca engine na build.

## Go — NDJSON

Byte a byte e todos os cortes; várias linhas/read; vazias/CRLF; EOF com/sem fragmento; inválida/oversized; cancelamento bloqueado.

## Go — HTTP local

Account/event/game; reconexão EOF/timeout; 401/403/404/429 com Retry-After segundos/data/ausente; movimento 200/400/resposta perdida; terminal sem retry; POST serializado; bodies/fds/context fechados.

## Go — auth/IPC/lifecycle

Token ausente/vazio/symlink/0644/0600; canário ausente de logs/erros/IPC; socket ocupado/stale/arquivo/symlink/segundo cliente; JSONL fragmentado/múltiplo/inválido/grande; SIGTERM em cada estado; bridge crashado. Rodar `go test -race` no host.

## MockBridge integração

1. desafio recusar; 2. aceitar→gameStart/full; 3. lance local/adversário; 4. promoção; 5. empate; 6. resign/abort; 7. vitória/derrota/empate; 8. desconexão em pontos críticos; 9. reconexão igual/avançada/divergente; 10. fechar em cada etapa.

A UI completa passa aqui antes de token real.

## Build/artefato

Build reproduzível ARMv7 sem cgo; `file`, `readelf -h/-A`, `ldd`/interpreter; SHA-256; manifesto sem engine/UCI/token; shellcheck/scripts integrais; RSS idle/conectado/dois streams; compatibilidade de kernel não inferida só do ELF.

## Dispositivo (Fase 6 autorizada)

Mock primeiro. Verificar menu/toque/orientação/ghosting/suspensão-Wi-Fi/RAM/encerramento/caminhos. Conta real depois. Logs sanitizados; anomalia para o teste.

Cada fase entrega comandos/versões, testes, riscos, arquivos e hashes aplicáveis.
