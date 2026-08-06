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

## Pendências

- reiniciar manualmente somente o KOReader para carregar a correção FFI;
- autenticar `GET /api/account` pela interface;
- receber e aceitar desafio direto casual Rapid;
- validar movimentos bilaterais, relógios, resultado e reconexão no KT4;
- medir RSS com os dois streams e remover o token efêmero ao final.
