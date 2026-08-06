# Auditoria do Kochess

Data: 2026-08-06. Fonte: [`bateast/kochess`](https://github.com/bateast/kochess), commit `b9e05a8202083b58e290dc719890584919d81245`, com submódulo `arizati/chess.lua` em `445225db99ee7c0442a316a2406a139ca3475076`.

## Conclusão

O Kochess é uma base útil para a casca KOReader: tabuleiro, peças SVG, toque origem–destino, promoção e atualização localizada. `main.lua`, relógio, leitor incremental e UCI devem ser substituídos.

Há um bloqueio jurídico: o Kochess declara GPLv3 ou posterior, mas `arizati/chess.lua` não contém licença. O módulo de regras não será copiado até haver concessão verificável ou substituição licenciada.

## Licença, autoria e histórico

- Principal: texto GPLv3; README declara copyright de Baptiste Fouques e “GPL 3.0 or above”. Tratar como `GPL-3.0-or-later` preservando todos os avisos.
- Autores no histórico: Baptiste Fouques (`bateast`) e contribuição documental de Bruno Turcatti; sete commits entre 2025-06-24 e 2026-04-22.
- Regras: submódulo por Flynn/arizati, 12 commits de 2020–2021; README o descreve como port de `jhlywa/chess.js`.
- Peças: README credita Colin M.L. Burnett e informa GPLv2+.
- O fork posterior `omer-faruq/chess.koplugin` inclui Stockfish ARMv7 e não será origem limpa.
- Na Fase 1, usar fork Git rastreável, nunca cópia avulsa de trechos.

## Estrutura e responsabilidades

| Caminho | Responsabilidade | Decisão |
|---|---|---|
| `_meta.lua` | metadados | adaptar |
| `main.lua` (1.116 linhas) | menu, layout, PGN, engine, partida, promoção e relógio | reescrever orquestração |
| `board.lua` (396) | grade 8×8, toque, seleção e refresh por casa | principal candidato a adaptação |
| `button.lua`, `buttontable.lua` | widgets customizados | reavaliar contra KOReader atual |
| `timer.lua` (91) | relógio local | não reutilizar |
| `uci.lua` (235) | subprocesso/protocolo UCI | excluir integralmente |
| `settingswidget.lua` (406) | humano/engine, Elo e tempo | substituir |
| `utils.lua` (145) | fork/exec, pipes, polling e I/O | reescrever |
| `chess.lua` | wrapper de regras | bloqueado pela licença |
| `chess/src/chess.lua` | FEN/PGN/regras/histórico | útil, mas não liberado |
| `icons/*.svg` | peças | reutilização potencial com créditos/licença |

## Dependências

Runtime KOReader/LuaJIT; `device`, `dispatcher`, `UIManager`, geometry, Blitbuffer, GestureRange, widgets, logger/gettext/lfs; libc via FFI; engine UCI externa no original; regras por `arizati/chess.lua` com bitops/fallback.

## Regras e representação

O módulo usa tabuleiro 0x88 e mantém lado, roque, en passant, halfmove/fullmove, histórico e PGN.

- **FEN:** carrega/gera seis campos. O próprio código admite que valida estrutura, não conteúdo completo (por exemplo, não exige os dois reis).
- **UCI:** `move({from,to,promotion})` e histórico verbose permitem `e2e4`/`e7e8q`; o `main.lua` já converte para engine.
- **Promoção:** q/r/b/n com diálogo.
- **Roque:** ambos os lados; UI atualiza torre.
- **En passant:** regra e refresh da casa capturada.
- **Validação:** lances legais, xeque/mate, stalemate, material insuficiente, repetição e regra de 50 lances.

A suíte Busted do submódulo tem 1.678 linhas e cobre perft, geração, FEN, SAN, PGN, especiais e regressões. Não foi executada: o host não possui Lua/LuaJIT/Busted e nada foi instalado automaticamente. Portanto, não se afirma que passa.

## Tabuleiro/toque

Aproveitável: 64 botões grandes, origem–destino, borda de seleção, atualização de casas especiais e paleta e-ink. Limitações: orientação fixa com brancas embaixo, sem último lance, aplica jogada local antes de confirmação, sem estado pending, código sem testes UI e pequenos defeitos como declaração duplicada de variável de roque.

## Relógio

Não reutilizar: usa `os.time`; não desconta enquanto roda; `time` e `base` compartilham tabela, prejudicando reset; comentário/cadência divergem; não há correção do servidor. O novo usa `ui/time` monotônico e snapshots remotos.

## APIs KOReader confirmadas

No commit auditado: diretório `*.koplugin` com `main.lua`/`_meta.lua`; `registerToMainMenu`/`addToMainMenu`; Dispatcher; `UIManager:show/close/setDirty/scheduleIn/unschedule`; evento `CloseWidget`; InputContainer/GestureRange; `ui/time.now` monotônico; refresh regional `ui`/`partial`/`flashpartial`/`full`; referências `ffiUtil.runInSubProcess`/`terminateSubProcess`.

## Veredito

**Aprovado com restrições para fork da interface.** Não aprovado para cópia integral. UCI sai; relógio/I/O são novos; regras ficam bloqueadas até resolução de licença. Nenhum código foi alterado nesta fase.
