# Relatório de aceitação — Fase 1

Data: 2026-08-06  
Branch: `phase/1-mock-ui`  
Baseline: `main@9be5d2b`  
Último commit funcional auditado: `17dc819`

## Resultado

A interface mock do Kindle Lichess está implementada e executa no runtime desktop do
KOReader. Ela ainda não acessa o Lichess, não usa token e não está pronta para instalação
no Kindle. A Fase 1 atende seu objetivo: validar o fluxo completo da interface antes da
implementação de rede.

## Mudanças entregues

- plugin `kindlelichess.koplugin` separado, registrado no menu Ferramentas;
- tabuleiro 8×8 em widgets KOReader, orientado pela cor do jogador;
- seleção origem/destino, destaque da seleção e da última jogada e promoção em diálogo;
- relógios monotônicos com correção de meia latência e refresh econômico de 60, 15 ou
  5 segundos conforme o tempo restante;
- telas de conexão, desafio, partida e resultado, com confirmação para abortar/desistir;
- `MockBridge` para desafio, resposta adversária, promoção, empate, vitória, derrota,
  desconexão e reconexão;
- protocolo v1 validado em ambas as direções, com bloqueio explícito de campos secretos;
- reconstrução da posição por `initialFen + moves`, sem atualização otimista;
- runner reproduzível para testes puros e para o runtime desktop oficial do KOReader.

## Autoridade e fair play

A seleção local produz somente uma intenção UCI. O tabuleiro confirmado muda apenas ao
processar `game_full` ou `game_state`. Estados duplicados não alteram a posição; históricos
divergentes e snapshots após reconexão forçam reconstrução a partir do estado recebido.

Não há Stockfish, engine, processo UCI, avaliação, opening explorer, tablebase, análise,
Python, Node.js, servidor HTTP ou cliente de rede no diretório do plugin. A validação local
é deliberadamente pseudo-legal e serve apenas para a interação. O Kochess completo existe
somente como submódulo de proveniência em `upstream/kochess` e será excluído de `dist/`.

## Proveniência e licenças

- Kochess fixado em `b9e05a8202083b58e290dc719890584919d81245`;
- grade/toque adaptados com atribuição no cabeçalho de `ui/board.lua`;
- peças SVG preservadas e creditadas a Colin M.L. Burnett;
- código sem licença explícita de `arizati/chess.lua` não foi reutilizado;
- código próprio sob GPL-3.0-or-later, com `LICENSE`, `NOTICE` e histórico Git preservados.

## Evidências de teste

Comando reproduzível:

```sh
KOREADER_SOURCE=/tmp/kindle-lichess-phase0-koreader ./scripts/test.sh
```

Resultados obtidos:

| Camada | Resultado | Cobertura principal |
|---|---:|---|
| runner Lua | 64/64 verificações | FEN, UCI, roque, en passant, promoção, relógios, protocolo e todos os cenários mock |
| Busted no KOReader | 3/3 testes | metadados/menu, widgets de tabuleiro e sessão completa com jogada, reconexão e empate |
| smoke desktop | carregado | perfil Kindle 600×800/167 dpi; `Plugin loaded kindlelichess`; encerramento controlado após 5 s |
| higiene do diff | aprovado | `git diff --check` e `bash -n scripts/test.sh` sem erros |

O ambiente usou `koreader/koreader@aae92cebb0151acaf671189fce9875dbce7a2cfe`
e `koreader/koappimage` fixado em
`sha256:4416f7b137b1eda49eb486bbe00dd00a347f0f126a649bf75bf1edc8d4877828`.
Nenhuma dependência foi instalada no host.

## Arquivos da Fase 1

- raiz: `.gitmodules`, `LICENSE`, `NOTICE`, `README.md`;
- documentação: `docs/licensing.md`, `docs/phase1-ui.md`, este relatório;
- plugin: `_meta.lua`, `main.lua`, `controller.lua`;
- xadrez: `chess/{position,selection,clock,game_state}.lua`;
- bridge mock: `bridge/{protocol,mock_bridge}.lua`;
- interface: `ui/{board,board_geometry,session}.lua`;
- arte: `icons/empty.svg` e doze SVGs de peças;
- testes: `tests/{run_unit,koreader_spec}.lua`, `scripts/test.sh`;
- proveniência: submódulo `upstream/kochess`.

## Riscos residuais

| Risco | Situação ao encerrar a fase | Próximo controle |
|---|---|---|
| inspeção visual | o smoke SDL não produz uma janela para revisão humana | abrir no KOReader desktop com display e revisar contraste, dimensões e textos antes do Kindle |
| versão instalada do KOReader | a versão exata do dispositivo não foi consultada, pois o Kindle está fora de escopo | verificar somente após autorização, na Fase 6 |
| rede e reconexão reais | apenas o mock foi exercitado | servidor HTTP falso e bridge Go na Fase 2; Lichess real somente na Fase 3 |
| precisão dos relógios | algoritmo testado com relógio injetado, sem latência real | testes de stream/latência na Fase 2 e correção pelo servidor na Fase 3 |
| validação de xadrez | pseudo-legal por decisão de fair play | manter o Lichess como validador definitivo |
| consumo em e-ink | política de refresh definida, mas não medida em hardware | medir somente após build ARM e autorização de instalação |

## Gate para a Fase 2

A Fase 2 pode começar sem token e sem Kindle. Ela deve implementar o processo Go contra
um servidor Lichess falso, o Unix socket e o framing JSON Lines. A interface continuará
usando o MockBridge até os testes de protocolo e ciclo de vida do processo passarem.

Não houve acesso, transferência nem alteração no Kindle nesta fase.
