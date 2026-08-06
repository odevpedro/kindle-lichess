# Kindle Lichess

Cliente open source para jogar partidas humanas no Lichess em um Kindle Basic 10ª geração (KT4/KindleHF), usando o KOReader.

## Manutenção

Projeto mantido por [odevpedro](https://github.com/odevpedro) (`pedrosschmidt2@gmail.com`). O histórico Git deste repositório preserva a autoria original de dependências e de código que venha a ser incorporado por fork; isso não implica coautoria no código próprio do Kindle Lichess.

## Estado

**Fase 3 — integração real no computador concluída com ressalva em 2026-08-06.** O plugin
possui interface KOReader funcional com MockBridge; bridge Go, Board API, Unix socket e
adaptador Lua foram implementados e testados. Uma conta de teste completou desafios
casuais, lances bilaterais, reconexão, empate e desistência pela API oficial. O harness
gráfico desktop não foi adotado como gate porque seu `fork/exec` travou sob Docker/X11;
esse risco permanece explícito para o teste controlado no dispositivo.

Nenhuma conexão foi feita com o Kindle e nenhum arquivo foi transferido ao dispositivo.
O token privado permanece fora do repositório em arquivo local `0600`.

## Decisões

- UI: plugin Lua `kindlelichess.koplugin` com componentes KOReader.
- Rede: processo Go `kindle-lichess-bridge`, sem cgo, limitado à sessão da tela.
- IPC: Unix socket `/tmp/kindle-lichess.sock`, JSON Lines v1, sem TCP.
- Autoridade: posição reconstruída de `initialFen + moves` confirmado pelo Lichess.
- Fair play: a build online não contém nem inicia engine/UCI/análise.
- Go/ARM: adoção final condicionada ao gate de binário mínimo e execução isolada.

## Entrega da Fase 0

- [Auditoria do Kochess](docs/audit-kochess.md)
- [Comparação com Exact Chess](docs/comparison-exact-chess.md)
- [Arquitetura](docs/architecture.md) e [ADRs](docs/adr/)
- [Protocolo Lua–Go](docs/protocol.md)
- [Board API](docs/lichess-api.md)
- [Licenciamento](docs/licensing.md) e [segurança](docs/security.md)
- [Backlog](docs/mvp-backlog.md), [riscos](docs/risks.md) e [testes](docs/test-plan.md)
- [Implantação futura](docs/deployment.md)
- [Seleção técnica da interface na Fase 1](docs/phase1-ui.md)
- [Relatório de aceitação da Fase 1](docs/phase1-report.md)
- [Relatório de aceitação da Fase 2](docs/phase2-report.md)
- [Andamento da integração desktop — Fase 3](docs/phase3-desktop.md)

## Fontes congeladas

| Fonte | Commit auditado |
|---|---|
| [bateast/kochess](https://github.com/bateast/kochess) | `b9e05a8202083b58e290dc719890584919d81245` |
| [arizati/chess.lua](https://github.com/arizati/chess.lua) | `445225db99ee7c0442a316a2406a139ca3475076` |
| [jckhng/exact-chess](https://github.com/jckhng/exact-chess) | `bfbfc29a63ab429c660f2d303827102e23547ed7` |
| [koreader/koreader](https://github.com/koreader/koreader) | `aae92cebb0151acaf671189fce9875dbce7a2cfe` |
| [lichess-org/api](https://github.com/lichess-org/api) | `b2085f7df37481cdac98f385711843f94d2d67b6` |
| [jhlywa/chess.js](https://github.com/jhlywa/chess.js) | `ca935bf44076e3d1c6e06922c7a9a2f28d959d2a` |

A Fase 1 foi iniciada somente após a revisão e o versionamento desta entrega.

## Testes locais

Execute `./scripts/test.sh` para os testes unitários. Para incluir o carregamento no
runtime desktop real do KOReader, aponte `KOREADER_SOURCE` para uma árvore KOReader
já compilada; detalhes e o digest da imagem estão em
[docs/phase1-ui.md](docs/phase1-ui.md).

Execute `./scripts/test-go.sh` para `gofmt`, `go vet` e `go test -race` na
toolchain Go oficial fixada por digest. Nenhuma ferramenta é instalada no host.

`./scripts/build-desktop.sh` gera o bridge x86-64 sem cgo em `dist/desktop`;
`./scripts/test-desktop-lifecycle.sh` testa socket e `SIGTERM` sem abrir HTTPS.

## Licença

O código próprio é distribuído sob `GPL-3.0-or-later`; consulte [LICENSE](LICENSE). Fontes reutilizadas mantêm seus próprios avisos e autoria conforme [NOTICE](NOTICE) e [documentação de licenciamento](docs/licensing.md).
