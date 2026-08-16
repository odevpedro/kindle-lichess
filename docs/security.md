# Segurança

## Token

Inexistente nas Fases 0–2. Na Fase 3: manual, fora de chat/Git, arquivo configurável modo exato 0600. O preflight do KT4 confirmou que o filesystem FSP de `/mnt/us` sintetiza permissões abertas e não pode hospedar esse arquivo. No protótipo privado, o token é transferido por sessão para `/tmp/kindle-lichess-token`, com `umask 077` e modo verificado como 0600; não persiste no armazenamento do usuário e é removido ao terminar. Bridge recusa ausente, symlink inesperado, owner errado ou permissões abertas. Token não entra em argv, IPC, fixture, erro/log e vai somente a `https://lichess.org`; Authorization não segue redirect a outro host. `token.example` tem só placeholder.

## IPC/processo

`umask 077`; socket 0600; um cliente; `lstat`/tipo/owner antes de limpar stale; nunca remover arquivo comum/symlink; limites de linha/campo; JSON inválido isolado; execução por caminho absoluto sem shell; PID conhecido; SIGTERM/context/wait; descriptors fechados.

## Rede/logs

TLS/hostname normais, nunca desabilitados. O plugin passa ao bridge o caminho absoluto do
`data/ca-bundle.crt` existente no KOReader; o arquivo é somente leitura, regular, PEM
válido e limitado a 2 MiB. Sem caminho explícito, o bridge usa o trust store do sistema.
DNS e kernel do firmware continuam gates. Timeouts por fase, detecção de inatividade,
bodies limitados e Retry-After/backoff/jitter. Base alternativa só em testes.

Logs por allowlist. Eventos rejeitados registram somente tipo de evento e código de erro
reconhecidos; JSON bruto, texto bruto do erro, usuário, ID de partida, posição e chat não
entram no stderr. Testes injetam canários em payload/erro e falham se aparecerem na saída.

O diagnóstico exportável também usa allowlist fechada: versão do formato, rótulo da
versão, idioma, modo do bridge e último código interno reconhecido. Ele não lê nem
pseudonimiza conta/jogo: esses dados simplesmente não entram no arquivo. Consulte
[privacy.md](privacy.md) e [privacy.pt-BR.md](privacy.pt-BR.md).

## Fair play

Sem engine, UCI, eval, sugestão, explorer, tablebase ou análise. Validação local apenas entrada/reconstrução. Pacote auditado por nomes/assinaturas/processos.
