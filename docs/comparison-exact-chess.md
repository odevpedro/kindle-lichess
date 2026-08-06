# Kochess versus Exact Chess

Exact Chess identificado: [`jckhng/exact-chess`](https://github.com/jckhng/exact-chess), commit `bfbfc29a63ab429c660f2d303827102e23547ed7`.

| Critério | Kochess | Exact Chess | Decisão |
|---|---|---|---|
| UI | Lua + KOReader | C + GTK2/Cairo/librsvg/X11 | Kochess |
| Integração | plugin KOReader | extensão KUAL | KOReader obrigatório |
| Tabuleiro/toque | widgets e origem–destino | drawing area, toque e alvos legais | adaptar Kochess; observar Exact |
| Orientação | fixa | modos white/black | implementar própria |
| Último lance | não | sim | referência comportamental |
| Regras | chess.lua sem licença explícita | C derivado de GNOME Chess | não copiar Exact; resolver regras Lua |
| FEN/UCI | FEN + conversão UCI | backend UCI/GNOME | FEN+UCI remoto |
| Especiais | promoção, roque, en passant | idem | testes próprios |
| Relógio remoto | não | não | implementação nova |
| Engine | inicializa UCI | modos Stockfish | remover totalmente |
| Dependências | KOReader/LuaJIT | runtime GTK/Cairo/X11 ARM | Exact viola a stack |
| Testes | suíte ampla só nas regras | cinco smoke tests de backend | Lua+Go+integração próprios |
| Licença | GPLv3+; lacuna nas regras | GPL-family/GNOME, mapeamento impreciso | preservar Kochess; não importar Exact |

## Referências visuais/comportamentais úteis

Contraste e contornos das peças, seleção/último lance, alvos grandes, orientação pelo jogador e painel de histórico recolhível.

## Itens explicitamente não reutilizáveis

GTK/Cairo/X11, runtime ARM empacotado, launcher KUAL, backend GNOME em C, UCI/Stockfish e PWA/Node/React.

Conclusão: Exact Chess é uma boa referência visual, mas estruturalmente oposto à arquitetura mandatória e não será fonte de código.
