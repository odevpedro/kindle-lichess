# Fase 6 — validação no Kindle KT4

Status: Gate ARM nativo aprovado; integração online preparada, aguardando validação pela interface.
Data: 2026-08-06.
Branch: `phase/6-kindle-validation`.

## Gates executados

### Gate 1 — preflight somente leitura

- kernel Linux 4.1.15-lab126, `armv7l`;
- Freescale i.MX6 SoloLite, ARMv7 com VFPv3/NEON/hard-float;
- rootfs `ext3` montada `ro`;
- 504.412 KiB de RAM total e 236.416 KiB disponíveis no instante da leitura;
- 4,8 GiB disponíveis em `/mnt/us` e 50,1 MiB no tmpfs usado por `/tmp`;
- KOReader, diretório de plugins e CA bundle encontrados;
- destino do plugin inexistente;
- todos os comandos planejados encontrados.

Nenhuma escrita ocorreu nesse gate.

### Gate 2 — pacote em `/tmp`

- pacote de 2.603.805 bytes recebido somente em `/tmp`;
- SHA-256 `2f2670fc4ac58f9c7b1a8187f4bf06daf43fedcfef4a1584e9879c476113cd53` aprovado;
- 33/33 arquivos aprovados pelo manifesto após extração em `/tmp`.

### Gate 3 — plugin novo

- criado somente `/mnt/us/koreader/plugins/kindlelichess.koplugin`;
- 33/33 arquivos aprovados no destino;
- nenhuma credencial transferida e nenhum bridge iniciado;
- plugin descoberto pelo gerenciador de plugins do KOReader.

## Descobertas de hardware

O FSP de `/mnt/us` apresenta arquivos como modo 0777 mesmo após `chmod`. Isso é adequado
para o executável do plugin, mas não satisfaz a exigência de token 0600. A estratégia foi
corrigida: o token do protótipo ficará somente em `/tmp/kindle-lichess-token`, tmpfs com
permissões Unix reais, durante uma sessão autorizada.

## Defeito encontrado na primeira abertura

O MockBridge chegou à tela de desafio, mas o KOReader reiniciou após `Accept`. A primeira
correção eliminou a reconstrução da árvore de botões dentro do callback, mas o segundo
teste no KT4 ainda falhou. O log então identificou a causa principal em
`framecontainer.lua:143`: `_padding_left` era `nil` durante `paintTo()`.

`Board` herdava de `FrameContainer`, mas sobrescrevia `getSize()`. Assim, o `paintTo()`
herdado não executava a inicialização de padding feita por `FrameContainer:getSize()`.
O método redundante foi removido: o tamanho agora é obtido normalmente da grade 8×8.
O teste do tabuleiro passou a pintar de fato em um blitbuffer 600×600, cobrindo a linha
que falhou no dispositivo.

Uma tentativa separada de modo real deixou no log `absolute bridge binary path is
required`: o carregador do KOReader fornece `self.path` relativo. O plugin agora resolve
esse caminho contra `DataStorage:getFullDataDir()` antes de iniciar o processo.

## Correção preparada

- `main.lua`: caminho absoluto do bridge e token padrão efêmero em `/tmp`;
- `ui/session.lua`: atualização de status sem destruir o botão ativo;
- `tests/koreader_spec.lua`: regressões para caminho relativo e callback `Accept`.

Validação local:

- Lua: 66/66 checks;
- runtime oficial KOReader: 9/9 testes;
- Go com `gofmt`, `go vet` e `go test -race`: 8/8 pacotes;
- duas construções consecutivas do pacote: hash idêntico.

Pacote corrigido:

| Item | Valor |
|---|---|
| tamanho | 2.604.691 bytes |
| SHA-256 | `cff5e47d2e7bdc1d09c04adfbf98f72e8b457fe2c969389e8efb8874fde6f2fd` |
| SHA-256 do bridge ARM inalterado | `77c1ef20f10385190000a8b1938ef882298690110ef754256075fc69c6289d40` |

### Atualização mínima instalada

O pacote corrigido foi transferido para `/tmp/kindlelichess-update-171acca.tar.gz` e
validado antes da extração. Os arquivos anteriores foram preservados em
`/tmp/kindle-lichess-backup-171acca/`. Somente estes arquivos do plugin foram
substituídos:

- `main.lua`;
- `ui/session.lua`;
- `MANIFEST.sha256`.

Após `sync`, 33/33 hashes do plugin instalado foram aprovados e o bridge permaneceu
byte a byte igual. O rollback automático não foi acionado. A nova versão será carregada
somente após reinício manual do KOReader.

### Correção de pintura instalada

A revisão `2013e34` foi transferida separadamente para `/tmp` e validada pelo SHA-256
`1b48fd78f7f38d66cf9bac88fd64e4f56f2f1f1ebd2b262f6675fe79098a6e3a`. Somente
`ui/board.lua` e `MANIFEST.sha256` foram substituídos, com backup em
`/tmp/kindle-lichess-backup-2013e34/`. Depois de `sync`, 33/33 hashes foram novamente
aprovados e o rollback não foi acionado.

## Refinamentos visuais preparados

- marcador circular cinza em cada destino vazio aceito pela validação local;
- anel cinza ao redor de peças que podem ser capturadas;
- marcadores removidos ao desmarcar, enviar jogada ou trocar a posição do servidor;
- relógios encapsulados em regiões fixas para refresh parcial independente de toque;
- atualização a cada 15 s acima de 5 min, 5 s entre 1–5 min e 2 s abaixo de 1 min;
- nenhum refresh por segundo e nenhuma engine/análise introduzida.

Testes da revisão: 66/66 checks Lua, 9/9 testes no runtime KOReader, pintura dos
marcadores em blitbuffer 600×600 e avanço visual do relógio sem evento de toque.

### Refinamentos instalados

A revisão `a8723aa` foi transferida para `/tmp`, validada pelo SHA-256
`cff5e47d2e7bdc1d09c04adfbf98f72e8b457fe2c969389e8efb8874fde6f2fd` e instalada
com backup em `/tmp/kindle-lichess-backup-a8723aa/`. Somente `chess/position.lua`,
`chess/selection.lua`, `ui/board.lua`, `ui/session.lua` e `MANIFEST.sha256` foram
substituídos. Depois de `sync`, 33/33 hashes foram aprovados e não houve rollback.

## Legalidade completa e MockBridge contínuo

A validação local deixou de aceitar apenas movimentos pseudo-legais. O redutor agora
mapeia casas atacadas, simula o lance antes de confirmá-lo e rejeita captura do rei,
rei em xeque, peça cravada, roque saindo/passando/terminando em xeque e en passant que
expõe o próprio rei. FEN exige exatamente um rei de cada cor. Os marcadores mostram
somente destinos legais.

O MockBridge preserva as cinco respostas iniciais quando forem legais e depois escolhe
deterministicamente o primeiro lance legal, sem avaliação, pontuação ou busca. Assim o
cenário não abandona depois da abertura e não executa resposta fixa ilegal após xeque.
Isso permanece restrito ao mock; a build online continua sem engine.

Validação local da revisão:

- 88/88 verificações Lua;
- 9/9 testes no runtime KOReader;
- 8/8 pacotes Go com `go test -race`;
- scripts e diff sem erros;
- duas construções idênticas do pacote.

Pacote instalado:

| Item | Valor |
|---|---|
| tamanho | 2.605.957 bytes |
| SHA-256 | `0bc4608e86614617a9ecab7fbfc9729129768fc27e2720718feba72d1baa187b` |
| bridge ARM | `77c1ef20f10385190000a8b1938ef882298690110ef754256075fc69c6289d40` |
| backup | `/tmp/kindle-lichess-backup-legal-0bc4608e/` |

Somente `bridge/mock_bridge.lua`, `chess/position.lua`, `chess/selection.lua` e
`MANIFEST.sha256` foram substituídos no dispositivo. O staging e o destino passaram
33/33 hashes; nenhum rollback foi necessário.

## Gate 4 — execução ARM nativa

O bridge instalado executou diretamente no KT4 usando socket e credencial fictícios
exclusivos em `/tmp`, sem cliente conectado e portanto sem HTTPS. Resultado observado:

- processo em estado sleeping, 6 threads;
- `VmRSS`: 3.396 KiB;
- `VmSize`/`VmPeak`: 571.228 KiB de espaço virtual reservado;
- `SIGTERM` encerrou com sucesso;
- socket e credencial fictícia foram removidos.

O valor virtual não representa RAM residente; o RSS observado é o indicador de pressão
real de memória. Ainda será medido novamente com os streams da conta e da partida.

## Preparação do modo real

O token autorizado foi transferido sem impressão para `/tmp/kindle-lichess-token`,
validado como arquivo regular não simbólico, proprietário `root`, modo 0600 e tamanho
limitado. Ele não integra o pacote, Git ou armazenamento persistente e será removido ao
final da sessão. Nenhuma requisição HTTPS foi iniciada durante essa preparação.

## Correção do primeiro carregamento online

Na primeira abertura do modo real, a interface retornou imediatamente à tela inicial.
O diagnóstico filtrado mostrou duas causas independentes:

- `/tmp/kindle-lichess-token` havia sido removido durante o reinício do KOReader, e o
  bridge encerrou corretamente com `token_missing`;
- o KOReader antigo do KT4 não declara `AF_UNIX` em `ffi/posix_h`, causando
  `missing declaration for symbol 'AF_UNIX'` antes da conexão Lua com o socket.

O transporte agora declara e usa `KINDLE_LICHESS_AF_UNIX = 1`, constante POSIX para
Linux, assim como já fazia para `SOCK_STREAM`. O teste de socket também usa somente a
constante privada e deixa de depender da declaração presente no runtime desktop moderno.

A revisão passou 88/88 verificações Lua, 9/9 testes KOReader e 8/8 pacotes Go. Duas
construções produziram o pacote idêntico de 2.605.964 bytes com SHA-256
`815456f011c349ad51b0749e0c2b5a423361987a8dc40a4e29cf4512f89cc4e1`.
Somente `bridge/unix_transport.lua` e `MANIFEST.sha256` foram instalados, com 33/33
hashes aprovados e backup em `/tmp/kindle-lichess-backup-ffi-815456f0/`.

Uma segunda abertura confirmou que `AF_UNIX` fora resolvido, mas revelou que o mesmo
runtime também não declara `sockaddr_un`, `connect`, `F_GETFL`, `F_SETFL`, `F_SETFD` e
`FD_CLOEXEC`. O módulo passou a declarar estrutura, função ausente e constantes privadas
Linux sem depender da versão de `ffi/posix_h`. `SocketBridge:_connect()` também captura
exceções da fábrica/transporte e as converte em erro visível, sem derrubar a janela.

A revisão completa passou 88/88 verificações Lua, 10/10 testes KOReader e 8/8 pacotes
Go. Duas construções geraram o pacote idêntico de 2.606.141 bytes com SHA-256
`3ac47b49659dc75301d89330fa9a6fa195ad2a7ae8536756fe3769ed00e2e8ac`.
Somente `bridge/{unix_transport,socket_bridge}.lua` e `MANIFEST.sha256` foram instalados,
com 33/33 hashes aprovados e backup em
`/tmp/kindle-lichess-backup-socket-3ac47b49/`.

Antes do reinício, um probe isolado iniciou o bridge sem enviar JSON e carregou o novo
transporte com o LuaJIT antigo do próprio KT4. A conexão Unix terminou com
`OLD_KOREADER_UNIX_CONNECT_OK`; `SIGTERM` e limpeza do socket também passaram. Nenhuma
requisição HTTPS ocorreu nesse probe.

O token será retransmitido depois do reinício manual caso `/tmp` seja limpo novamente.

## Correção de bloqueio em `fcntl`

Com o modo real em `Conectando…`, `/proc` mostrou o bridge vivo, socket Unix aceito e
nenhum descritor de rede. Um probe do `SocketBridge` ficou bloqueado em
`unix_stream_recvmsg`; seu `fdinfo` tinha apenas `flags: 02`, sem `O_NONBLOCK`.

A causa foi a chamada variádica `fcntl`: no LuaJIT ARM, números Lua em `...` são passados
como `double`, enquanto `F_SETFL` e `F_SETFD` exigem `int`. O transporte agora omite o
terceiro argumento em `F_GETFL` e usa `ffi.cast("int", ...)` nos dois setters. O teste
KOReader lê os flags do descritor e exige explicitamente `O_NONBLOCK`.

A revisão passou 88/88 verificações Lua, 10/10 testes KOReader e 8/8 pacotes Go. Duas
construções geraram o pacote idêntico de 2.606.176 bytes com SHA-256
`0cdd27eb8176cef918510e811fe3cc35bb991c4bd9234599f7819245a623cddc`.
Somente `bridge/unix_transport.lua` e `MANIFEST.sha256` foram instalados, com backup em
`/tmp/kindle-lichess-backup-nonblock-0cdd27eb/`.

O probe final no KT4 produziu `KINDLE_FD_NONBLOCK_OK`,
`SOCKET_BRIDGE_CONNECTED_OK` e `NONBLOCK_PROBE_CLEANUP_OK`: flags, fila JSON, HTTPS,
autenticação, evento `connected`, SIGTERM e limpeza passaram no runtime real.

## Correção do handoff de reconexão

Diagnóstico do relato "UI mostra conexão, mas o tabuleiro não abre e depois aparece erro
de conexão": o bridge emite `disconnected` antes de cada `reconnecting` em qualquer
oscilação de stream (`app/session.go` `notifyReconnect`), e o plugin tratava `disconnected`
como queda definitiva — zerava a conexão, mostrava "Sem conexão" e a UI descartava o
tabuleiro durante o handoff `opening_game → game_full`. Em rede instável isso ocorria antes
do `game_full`, deixando a tela "conectada" sem tabuleiro e depois com erro de conexão.

Mudança em `plugin/kindlelichess.koplugin/controller.lua`: `disconnected` agora é tratado
como sinal transitório de reconexão (mesmo estado de `reconnecting`), preservando
`game_state`/`selection`/view. A falha definitiva continua a chegar por `error` com
`fatal=true`, único caminho que baixa a conexão para `offline`. Novos checks em
`tests/run_unit.lua` cobrem a sequência live
`connected → game_start → disconnected → reconnecting → game_full` e garantem que o
tabuleiro só abre após `game_full`.

Validação local:

- Lua: 96/96 verificações;
- Go com `gofmt`, `go vet` e `go test -race`: 8/8 pacotes;
- duas construções do pacote com hash idêntico.

Pacote da revisão:

| Item | Valor |
|---|---|
| tamanho | 2.607.731 bytes |
| SHA-256 | `f5aeaadabb93dae0fe00229855e764598b9cedac777b2ff030919a95fd7bd2d3` |

O bridge ARM não foi recompilado nesta revisão (mudança é só Lua). Antes do próximo reinício
do KOReader, o pacote atualizado deve ser transferido para `/tmp` e validado pelo SHA-256
acima antes da extração. O token efêmero em `/tmp/kindle-lichess-token` pode precisar ser
retransmitido se `/tmp` for limpo no reinício.

## Causa raiz do `invalid response` no primeiro jogo real

No primeiro teste live no KT4, após aceitar o desafio a UI ficava em
"Reconectando em 1,2,3 s" e depois caía com "Bridge request failed
(invalid response)", sem abrir o tabuleiro. Diagnóstico direto contra a API real
mostrou que o cubo `gameStart`/`gameFinish` traz `status` como **objeto**
(`{"id":20,"name":"started"}`) e `winner` também pode ser objeto, mas
`normalizeGameReference` fazia `json.Unmarshal` de `status` numa `string`, o que
falha e devolve `invalid_response`. O `game_start` nunca chegava ao plugin, então o
tabuleiro não abria e o stream encerrava. O fake/desktop mandava `status` como
string, por isso só o live real estourava.

Mudança em `bridge/internal/app/normalize.go`: `normalizeGameReference` aceita a
forma viva — `id` ou `gameId`, `status` como string ou `{id,name}`, e `winner`
como string ou `{color,id,name}` — com testes de regressão em
`normalize_test.go`. Não há mudança de protocolo Lua.

Validação local:

- Go `gofmt`, `go vet` e `go test -race`: 8/8 pacotes;
- duas construções idênticas do pacote.

Pacote/Bridge da revisão:

| Item | Valor |
|---|---|
| SHA-256 do pacote | `7e8a7a4835d46d507eabdae5153159438266860ffbd7697835d340ec9f6948d2` |
| SHA-256 do bridge ARM | `7a50826e8b3e3bfad21b1a27f661eb4fd8539a28738740255fd2878249d9ba59` |

No KT4 foi instalado somente `bin/kindle-lichess-bridge` e `MANIFEST.sha256`
(substituindo o bridge antigo), com `sha256sum -c` = 33/33 OK e backup em
`/tmp/kindle-lichess-backup-bridge-7a50/`.

## Causa raiz do "Bridge request failed (internal)" após um lance

Relato ao vivo: "faço o lance no Kindle, ele aparece no navegador, mas a resposta do
adversário não volta ao Kindle e aparece 'Bridge request failed'". O código reportado
no device foi `internal` (não `not_found`). O diagnóstico no bridge: `do()` converte
erros na abertura da conexão em `network_error` (reconectável), mas os erros de leitura
do corpo do stream (`reader.Next()`) eram devolvidos brutos em `stream()`. Numa queda do
Wi-Fi do KT4 no meio de uma linha NDJSON, o corpo volta `io.ErrUnexpectedEOF` ou
`connection reset` — que o `retryDecision` não reconhecia (só `io.EOF`,
`stream.ErrTruncatedLine`, timeout e `network_error`/`http_error`/`rate_limited`), então
o stream encerrava como fatal e o plugin descia para `offline`, congelando o tabuleiro
até reiniciar o KOReader.

Mudança em `bridge/internal/lichess/client.go`: no loop de leitura, `io.EOF`,
`stream.ErrTruncatedLine` e `stream.ErrMessageTooLarge` seguem como estão; qualquer
outro erro de leitura é convertido por `transportError` em `network_error`
(reconectável). Assim uma queda no meio de um NDJSON vira uma reconexão normal
("Reconectando…") e o bridge reabre a partida (`game_full`), em vez de travar. NOVO
`TestStreamReadInterruptionIsRetryable` corta a conexão no meio de uma linha e exige que
o erro seja um `APIError` `network_error`. Não há mudança de protocolo Lua.

Validação local:

- Go `gofmt`, `go vet` e `go test -race`: 8/8 pacotes;
- probe live no host: `connect → game_start → challenge → game_full` sem erro.

Pacote/Bridge da revisão:

| Item | Valor |
|---|---|
| SHA-256 do pacote | `66957a3b889885c562731db33ec2cee2b00e6519f8aa908ba6cb0dd6a38c02693` |
| SHA-256 do bridge ARM | `e0b6f989c1f227dbb54cb95dba1237c81865b73289f6fc5447c9711ac124a2ac` |

No KT4, se instalar, basta `bin/kindle-lichess-bridge`, `MANIFEST.sha256` e backup com
`sha256sum -c` = 33/33, fechando e reabrindo o KOReader depois. Como só o binário mudou,
a instalação pode esperar o fim da partida atual.

## Pendências

- fechar e reabrir o Kindle Lichess para o plugin subir o novo bridge;
- repetir: autenticar `GET /api/account`, aceitar desafio casual Rapid
  (standard), confirmar **tabuleiro abre** sem `invalid_response`;
- validar lances bilaterais, relógios, resultado e reconexão no KT4;
- medir RSS com os dois streams e remover o token efêmero ao final.
- autenticar `GET /api/account` pela interface;
- receber e aceitar desafio direto casual Rapid;
- validar movimentos bilaterais, relógios, resultado e reconexão no KT4;
- medir RSS com os dois streams e remover o token efêmero ao final.

## Ajustes visuais (instalados 2026-08-07)

Instalado `dist/kindlelichess-koplugin-armv7.tar.gz`, SHA-256
`e0b6f2d70ad3ffb0a695a796ec6f6416d4fec77c7228132275bb456eefd9fd48`, 33/33
checks aprovados no device (backup `/tmp/kl-backup-lua-141235/`).

- **Coordenadas fora do tabuleiro** (`ui/board.lua`): ranks `1–8` à esquerda e
  fileiras `a–h` na base, via `HorizontalSpan` + células `CenterContainer`;
  `Board:init` desconta `label_size` do `board_size` e recalcula o quadrado.
- **Promoção inline** (`controller.lua`, `ui/session.lua`): removido o
  `ButtonDialog` modal (colidia com o refresh em tela cheia no runtime do KT4 e
  só aparecia ao fechar). `Controller:tap_square` grava `controller.promotion`
  `{from,to}`; `Session:_promotion` adia um `_rebuild` via `UIManager:nextTick`;
  `_build_game` renderiza um `ButtonTable` Q/R/B/N no lugar da linha de ações.
  `promotion` é limpo ao promover com sucesso, ao fechar e em cada
  `game_full`/`game_state`.
- **Rei em xeque** (`ui/board.lua`): `Square.checked` + `_background()` com
  `COLOR_GRAY`; `Board:init`/`update` usam `Position:is_in_check(turn)` +
  `king_square(turn)`.
- Registro: `ui/board.lua` `34e6aa17…`, `ui/session.lua` `4f56eb38…`,
  `controller.lua` `755bea09…`, `ui/board_geometry.lua` `004296f5…`,
  `MANIFEST.sha256` `5be6da5c…`.
- Testes unitários `tests/run_unit.lua`: 96/96 ok; `luajit -bl` limpo.

## Jogar com alguém (seeker automático, 2026-08-07)

Fluxo do Lichess "jogar com alguém de elo próximo": `POST /api/board/seek`
(rapid 10+5, casual) seguido de `gameStart` no stream de eventos quando acha oponente.

- Bridge: `Client.CreateSeek`/`CancelSeek` + `SeekOptions`; protocol `seek`/
  `cancel_seek` (valida `timeControl`); `session.go` despacha para `/api/board/seek`
  e `/api/board/seek/cancel`.
- Plugin: `protocol.lua` registra `seek`/`cancel_seek`; `mock_bridge` responde
  `command_ok` e dispara `game_start`; `controller.seek_game`/`cancel_seek` +
  estado `seeking`; `session.lua` botão "Jogar com alguém (10+5)" e "Cancelar busca"
  no lobby (rebuild via `nextTick`).
- Cores de velocidade aceitas em `_apply_full` ampliadas para
  `unlimited/ultraBullet/bullet/blitz/rapid/classical/correspondence/relay`
  (antes só rapid/classical/correspondence → bloqueava desafios do browser).
- Testes: Go `TestSeekRoundTrip` + `TestValidateCommandAcceptsEveryType`/fields;
  Lua 123/123.
- SHA-256 bridge armv7 `d6f0f931…`; desktop `7de2a68a…`; plugin
  `ec04f573…` (MANIFEST 33/33). Instalado no device 2026-08-07 (33/33, backup
  `/tmp/kl-backup-lua-151336`).

## Desafio direto por usuário (2026-08-09)

Backlog P1 "criar desafio no app (não só aceitar os recebidos) — direto por
usuário": o plugin agora envia `POST /api/challenge/{username}` para desafiar
qualquer conta pelo nome, sem depender do browser.

- Bridge: `Client.CreateChallenge` (`ChallengeOptions`) e `Client.CancelChallenge`
  (cancelar desafio outbound via `/api/challenge/{id}/cancel`); protocol
  `create_challenge` (valida `username` ASCII 3–32 e `timeControl`) e
  `cancel_challenge` (valida `challengeId`); `session.go` despacha os dois e
  amplia a interface `API`.
- Plugin: `protocol.lua` registra `create_challenge`/`cancel_challenge`;
  `mock_bridge` responde `command_ok` + `game_start` (aceite imediato, igual seek)
  e `challenge_canceled` para cancelamento; `controller.create_challenge`/
  `cancel_challenge` + estado `challenging`; `controller:handle` distingue
  `challenge.direction == "out"` (estado "aguardando aceite", sem aceitar/recusar
  o próprio desafio) de desafios recebidos; `session.lua` ganhou o botão
  "Desafiar jogador…" no lobby, um `InputDialog` para o username e a view
  "Cancelar desafio". Erros não fatais de criação voltam ao lobby.
- Testes: Go `TestDirectChallengeRoundTrip`, `TestValidateCommandAcceptsEveryType`
  (com `cancel_challenge`), validação de campos (`invalid_username`,
  `invalid_time_control`), endpoint `/api/challenge/{username}` no
  `TestEveryBoardMutationUsesDocumentedEndpoint`; Lua 133/133 cobre criação de
  desafio, campos enviados e o tratamento de desafio outbound/inbound.
- SHA-256 bridge armv7 `ba96fc61…`; desktop `9981f185…`; plugin
  `7dcf1e1b…` (pacote completo `dist/kindlelichess-koplugin-armv7.tar.gz`,
  reproduzível em duas construções). Não instalado no device — aguardar fim da
  validação atual no KT4; só Lua+MANIFEST mudaram além do binário.

## Seek sem bloquear o command pump + fix en passant (2026-08-09)

- Bridge: `Client.StartSeek` agora retorna o `io.ReadCloser` do corpo do stream
  (`/api/board/seek` mantém o seek ativo enquanto a conexão estiver aberta).
  `session.go` lê o corpo numa goroutine (`openSeek`/`closeSeek`) e não segura o
  pump de comandos; `cancel_seek` (ou `gameStart`) fecha o corpo. Teste Go
  `TestSeekStreamDoesNotBlockCommandPump` cobre: `command_ok` imediato ao seek,
  `ping` respondendo durante o stream aberto e fechamento do corpo no cancel.
- Plugin: bug pré-existente em `chess/position.lua` — `coords_square(from_file,
  (from_rank + to_rank) / 2)` produzia `"d6.0"` (float) em runtimes que
  mantêm o sufixo decimal no `tostring` (Lua 5.3+; LuaJIT do KOReader truncava,
  por isso passava). O en passant (`e5d6` etc.) era rejeitado como
  `evidently_illegal`. Fix: `coords_square` normaliza com `math.floor`, válido
  tanto em LuaJIT 5.1 quanto em Lua 5.4. Reproduzido: falhava na linha 43 do
  `tests/run_unit.lua` em lua5.4 e passa em lua5.4 e luajit (`ok - 133 checks`).
- Bridge verificado com `gofmt`, `go vet` e `go test -race -count=1 ./...` (8/8
  pacotes). SHA-256 dos binários ainda não rebuildados (dist ignorado pelo Git);
  rebuildar antes de instalar no KT4.

## Crash no primeiro toque de uma partida sem lances (2026-08-12)

O fluxo de seek encontrava um adversário e abria a partida, mas a janela do plugin
fechava no primeiro toque quando ainda não existia lance anterior. Uma inspeção
somente leitura de `/mnt/us/koreader/crash.log` no KT4 encontrou três ocorrências de
`ui/board.lua:216: table index is nil`, todas no caminho
`Square:onTapSquare → Controller:tap_square → Session:_controller_changed → Board:update`.

A causa era local à UI, não ao seeker: `Board:init` convertia a ausência de último
lance (`nil`) em `{}`. No primeiro `Board:update`, a tabela vazia era considerada
verdadeira pelo Lua e o código executava `refresh[self.last_move.from] = true`; como
`from` era `nil`, o LuaJIT encerrava o callback com `table index is nil`, propagando a
exceção até a janela do KOReader. Desafios em que já havia um lance no snapshot não
acionavam o defeito, o que fazia o problema parecer específico do pareamento aleatório.

Correção em `ui/board.lua`: preservar `last_move=nil` e marcar separadamente apenas
casas `from`/`to` realmente presentes. A regressão em `tests/koreader_spec.lua` exige
que um tabuleiro recém-criado mantenha `last_move=nil` antes da atualização causada
pelo primeiro toque.

Validação local:

- Lua: 133/133 verificações;
- parsing de `ui/board.lua` e `tests/koreader_spec.lua` pelo Lua embutido no Neovim;
- Go: `gofmt`, `go vet` e `go test -race` sem falhas;
- `git diff --check` sem erros.
- duas construções idênticas do pacote ARMv7, SHA-256
  `cd0e1896b6a2db0c4074db8588a0b57609b647268bb4962c5a81bc53068c4767`.

O teste de integração no runtime KOReader desktop não foi executado porque a árvore
compilada indicada por `KOREADER_SOURCE` não está presente neste host.

Após autorização explícita, o pacote de 2.617.046 bytes foi transferido via SSH para
`/tmp/kindlelichess-update-cd0e1896.tar.gz`; tamanho e SHA-256 foram confirmados no
aparelho. O staging `/tmp/kindle-lichess-stage-cd0e1896/` passou 33/33 hashes antes da
instalação. O plugin anterior foi preservado em
`/tmp/kindle-lichess-backup-cd0e1896/`; a cópia instalada passou novamente 33/33 hashes
e `ui/board.lua` coincidiu com o staging (`f852edeb00d1437629da260763b1dcdd2f2ee3d2a4f925e8071783f482c7eb41`).
O rollback automático não foi acionado. O bridge e o socket permaneceram ausentes.
O KOReader não foi reiniciado remotamente; é necessário reiniciá-lo manualmente para
descartar os módulos Lua já carregados antes de repetir o seek.

## Crash ao pintar o resultado da partida (2026-08-12)

Uma partida live de seek pôde ser jogada quase até o final, mas a janela fechou quando
o resultado chegou. O `crash.log` do KT4 registrou às 20:09:25 duas falhas ao carregar
`./fonts/front`, seguidas por `frontend/ui/font.lua:386: attempt to index local 'face'`
durante `UIManager:_repaint`; o KOReader reiniciou às 20:10:47. Não houve erro de rede,
stream ou bridge nesse encerramento.

A tela de resultado era o único ponto do plugin que solicitava
`Font:getFace("front", 32)`. Essa face não existe no KOReader 2026.03/KindleBasic3;
o fluxo chegava corretamente a `game_finish`, construía o widget com face nula e só
falhava no repaint. A face foi trocada por `cfont`, já usada e validada no restante da
interface do KT4.

O teste KOReader agora instancia e pinta em framebuffer real as quatro classes de
resultado: vitória branca por mate, vitória preta por desistência, empate e aborto.
Isso cobre a etapa de pintura que o teste anterior não executava depois de chegar a
`controller.view == "result"`.

Também foi registrado no backlog P2 o placar visual de peças capturadas/material,
sempre derivado de `initialFen + moves` confirmados, incluindo en passant, promoção,
reconexão e histórico divergente, sem engine ou avaliação posicional.

## Histórico, PGN, tempo, tabuleiro livre e chat instalados (2026-08-14)

Foram implementados e empacotados em conjunto: navegação de lances com `<`/`>`,
exportação PGN atômica em `/mnt/us/documents/KindleLichess/`, controles de tempo
personalizados, tabuleiro livre offline e chat privado `player` durante partidas
ativas. O spike do chat resultou em `GO`; o texto fica somente em memória, mensagens
de espectadores são ignoradas e POSTs incertos não são repetidos automaticamente.

Validação local:

- Lua: 167/167 verificações;
- Go: 8/8 pacotes com `go test -race`;
- `git diff --check` e scripts shell sem erros;
- bridge ARMv7 estático: SHA-256
  `8bbd63177d6b53a7db4a242f06048f405c58782b445d0f884a34c1033fa0ee80`;
- pacote reproduzido duas vezes com 2.627.034 bytes e SHA-256
  `11eccd9654775b7f3ab40d3a65880eab0a146535c0bd4302865e20b3de7bc5ce`.

Após autorização explícita, o pacote foi enviado ao KT4 e extraído em staging dentro
da área de plugins, pois o tmpfs tinha apenas cerca de 9 MiB livres. Staging e destino
passaram 37/37 hashes. O plugin anterior permanece recuperável em
`/mnt/us/koreader/plugins/.kindlelichess-backup-pre-11eccd96`; nenhum rollback foi
necessário. O token real em `/tmp/kindle-lichess-token` foi preservado sem leitura,
com modo 0600 e o mesmo tamanho observado. O novo bridge iniciou nativamente no ARMv7,
criou o socket de teste e encerrou de forma limpa com credencial fictícia, sem HTTPS.
O KOReader não foi reiniciado remotamente; um reinício manual ainda é necessário para
descartar módulos Lua da versão anterior já carregados.
