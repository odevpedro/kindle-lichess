# Fase 6 — validação no Kindle KT4

Status: correção instalada, aguardando repetição visual do MockBridge.
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

## Pendências

- validar marcadores de destino e refresh parcial dos relógios no KT4;
- repetir o fluxo MockBridge até o tabuleiro;
- executar ciclo de vida ARM nativo e medir RSS;
- somente então testar HTTPS/conta real com token efêmero.
