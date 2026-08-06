# Segurança

## Token

Inexistente nas Fases 0–2. Na Fase 3: manual, fora de chat/Git, arquivo configurável modo exato 0600. Bridge recusa ausente, symlink inesperado, owner errado ou permissões abertas. Token não entra em argv, IPC, fixture, erro/log e vai somente a `https://lichess.org`; Authorization não segue redirect a outro host. `token.example` terá só placeholder.

## IPC/processo

`umask 077`; socket 0600; um cliente; `lstat`/tipo/owner antes de limpar stale; nunca remover arquivo comum/symlink; limites de linha/campo; JSON inválido isolado; execução por caminho absoluto sem shell; PID conhecido; SIGTERM/context/wait; descriptors fechados.

## Rede/logs

TLS/hostname normais, nunca desabilitados. CA roots/DNS do firmware são gates. Timeouts por fase, detecção de inatividade, bodies limitados e Retry-After/backoff/jitter. Base alternativa só em testes.

Logs por allowlist. Teste injeta token-canário e falha se aparecer em stdout/stderr/IPC. Diagnóstico pseudonimiza conta/jogo.

## Fair play

Sem engine, UCI, eval, sugestão, explorer, tablebase ou análise. Validação local apenas entrada/reconstrução. Pacote auditado por nomes/assinaturas/processos.
