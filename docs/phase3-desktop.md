# Fase 3 — integração real no computador

Status: em andamento.  
Início: 2026-08-06.  
Branch: `phase/3-desktop-integration`.

## Resultado parcial

O caminho de execução real está preparado, a autenticação inicial foi validada contra o
Lichess e um desafio direto casual chegou ao estado de partida. O modo padrão continua
`mock`.

No menu Ferramentas → Kindle Lichess existem três ações:

- abrir a aplicação;
- selecionar Mock;
- selecionar conta de teste Lichess.

O modo é persistido em `kindlelichess_bridge_mode`. O modo real não recebe o conteúdo
da credencial em Lua; ele transmite ao processo Go somente estes caminhos:

| Item | Padrão |
|---|---|
| executável | `<plugin>/bin/kindle-lichess-bridge` |
| token | `<KOReader data>/kindle-lichess/token` |
| socket | `/tmp/kindle-lichess.sock` |

No desktop, os dois primeiros podem ser substituídos pelas configurações
`kindlelichess_bridge_binary` e `kindlelichess_token_file`. O Go revalida que o token
é arquivo regular `0600`; Lua não abre, imprime ou serializa seu conteúdo.

## Build desktop

```sh
./scripts/build-desktop.sh
./scripts/test-desktop-lifecycle.sh
```

Resultado atual:

- ELF 64-bit x86-64, estaticamente ligado, sem cgo e stripped;
- SHA-256
  `15057b0095cb3cbc2fa6c45759d61a10bad3acb856d6bfcce31803802928fab0`;
- ciclo real do executável: socket criado, `SIGTERM` recebido e socket removido;
- o teste de ciclo não conecta cliente, portanto não inicia HTTPS.

O artefato fica em `dist/desktop/kindle-lichess-bridge` e é ignorado pelo Git.

## Testes atuais

- 64/64 verificações Lua;
- 7/7 testes Busted no runtime oficial do KOReader;
- 8/8 pacotes com `go test -race`;
- scripts validados por `bash -n`;
- busca de higiene sem token no repositório.
- `GET /api/account` real aprovado para a conta de teste `testkindle`;
- probe abre e fecha o bridge por Unix socket e exibe somente `id`, `username` e
  `title` normalizados;
- `GET /api/stream/event` recebeu desafio Standard Rapid 10+0 casual;
- `POST /api/challenge/{challengeId}/accept` retornou confirmação `command_ok`;
- o `game_start` não foi observado na janela curta após a mutação, sem repetição do
  `POST`;
- a reconciliação abriu `GET /api/board/game/stream/{gameId}` e recebeu `gameFull` com
  `initialFen=startpos`, lista de lances vazia, cor preta para `testkindle`, relógios em
  600000 ms e estado `started`.

O último caso valida uma regra importante do protocolo: após uma mutação confirmada ou
ambígua, o cliente consulta a fonte de verdade e não repete automaticamente uma operação
que pode já ter sido aplicada.

## Ferramentas de validação real

Os scripts abaixo recebem somente o caminho absoluto do token. Eles não imprimem nem
copiam a credencial e seus diretórios temporários ficam sob `/tmp`:

| Script | Operação | Saída persistida |
|---|---|---|
| `probe-account.sh` | consulta a conta | campos públicos normalizados |
| `watch-challenge.sh` | observa o stream da conta | desafio normalizado |
| `accept-challenge.sh` | aceita um ID explícito uma única vez | confirmação sanitizada |
| `probe-game.sh` | abre o stream de uma partida | snapshot sanitizado |

## Pendente para concluir a fase

1. jogar e receber ao menos um lance;
2. testar empate/desistência e reconexão;
3. validar o fluxo real completo na interface KOReader desktop;
4. registrar logs sanitizados, revogar a credencial de teste se necessário e emitir o
   relatório de aceitação da Fase 3.

Não há autorização para build ARM, transferência ao Kindle ou alteração do dispositivo.
