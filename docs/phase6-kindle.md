# Fase 6 — validação no Kindle KT4

Status: em andamento.
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

O MockBridge chegou à tela de desafio, mas a janela desapareceu após `Accept`. O código
reconstruía e liberava a árvore de botões sincronamente dentro do callback do próprio
botão. A correção atualiza apenas o texto durante o evento transitório `status`; a troca
estrutural para o tabuleiro continua ocorrendo depois, em `game_start`/`game_full`.

Uma tentativa separada de modo real deixou no log `absolute bridge binary path is
required`: o carregador do KOReader fornece `self.path` relativo. O plugin agora resolve
esse caminho contra `DataStorage:getFullDataDir()` antes de iniciar o processo.

## Correção preparada

- `main.lua`: caminho absoluto do bridge e token padrão efêmero em `/tmp`;
- `ui/session.lua`: atualização de status sem destruir o botão ativo;
- `tests/koreader_spec.lua`: regressões para caminho relativo e callback `Accept`.

Validação local:

- Lua: 64/64 checks;
- runtime oficial KOReader: 9/9 testes;
- Go com `gofmt`, `go vet` e `go test -race`: 8/8 pacotes;
- duas construções consecutivas do pacote: hash idêntico.

Pacote corrigido:

| Item | Valor |
|---|---|
| tamanho | 2.603.967 bytes |
| SHA-256 | `34c867dbe83e74499201f62ff08f68bc0ee37df23d88a0b2bbecc62850aca88d` |
| SHA-256 do bridge ARM inalterado | `77c1ef20f10385190000a8b1938ef882298690110ef754256075fc69c6289d40` |

## Pendências

- atualizar no Kindle somente `main.lua`, `ui/session.lua` e `MANIFEST.sha256`;
- repetir o fluxo MockBridge até o tabuleiro;
- executar ciclo de vida ARM nativo e medir RSS;
- somente então testar HTTPS/conta real com token efêmero.
