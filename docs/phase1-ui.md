# Fase 1 — seleção técnica da interface

## Baseline reproduzível

- Kochess: `bateast/kochess@b9e05a8202083b58e290dc719890584919d81245`, registrado em `upstream/kochess`.
- KOReader: `koreader/koreader@aae92cebb0151acaf671189fce9875dbce7a2cfe`, usado como referência do harness desktop.
- O diretório `upstream/` é material de proveniência e nunca entra em `dist/` nem no diretório instalado no Kindle.

## Reuso aprovado

| Elemento Kochess | Decisão | Motivo |
|---|---|---|
| grade 8×8 e conversão casa/coordenada | adaptar em `ui/board.lua` | desenho simples, útil e GPL-3.0-or-later |
| seleção origem→destino por toque | adaptar como emissão de intenção | mantém boa UX sem alterar estado confirmado |
| 12 SVGs de peças | reutilizar com créditos | derivados de Colin M.L. Burnett, GPL-2.0-or-later |
| diálogo de promoção | reimplementar com widgets KOReader atuais | o fluxo é útil; o acoplamento original não é |
| `_meta.lua` e registro no menu | reimplementar conforme API KOReader atual | código trivial e melhor compatibilidade |

Cada arquivo adaptado terá cabeçalho de origem, commit e licença. Os SVGs serão mantidos sem remover metadados. `NOTICE` preserva autores e licenças.

## Reuso rejeitado

- `chess.lua` e `chess/src/`: sem licença explícita no upstream original de `arizati/chess.lua`;
- `uci.lua`, engine, Elo e caminhos Stockfish: proibidos pelo requisito de fair play;
- `timer.lua`: usa `os.time`, polling e atualização periódica incompatíveis com relógio econômico e monotônico;
- `button.lua` e `buttontable.lua`: sobrescrevem widgets internos inteiros do KOReader e aumentam o risco de incompatibilidade;
- `main.lua`: acopla tabuleiro, engine, PGN, relógio local e estado confirmado;
- PGNs e fluxo de arquivos: fora do MVP.

## Modelo limpo de posição

Será uma implementação própria, sem consulta ao código não licenciado. Responsabilidades limitadas:

1. decodificar `initialFen` standard;
2. aplicar a lista UCI completa recebida do servidor;
3. tratar promoção, roque standard e en passant para reconstrução;
4. calcular casas alteradas entre snapshots;
5. reconhecer apenas movimentos pseudo-legais evidentes para UX.

O modelo não calcula cheque, mate, avaliação ou melhor jogada. Uma intenção local nunca altera a posição confirmada; somente `gameFull`/`gameState` do bridge o fazem.

## APIs KOReader selecionadas

- `WidgetContainer` para ciclo de vida do plugin;
- `Dispatcher` e `registerToMainMenu` para entrada em Ferramentas;
- `UIManager` para abrir/fechar widgets, timers econômicos e refresh regional;
- containers, `Button`, `ButtonDialog`, `ConfirmBox`, `TextWidget` e `IconWidget` nativos;
- `Device.screen` e `Geometry` para dimensionamento, sem Cairo/GTK direto.

## Estado do ambiente desktop

A árvore KOReader congelada contém testes Busted e o runner `./kodev test`, mas seus submódulos de build não estão inicializados. O host não possui `lua`, `luajit` ou `busted` no PATH. Nenhuma dependência foi instalada. Módulos puros serão testáveis também por um runner mínimo; o teste visual completo exigirá preparar o ambiente KOReader desktop em um gate separado.
