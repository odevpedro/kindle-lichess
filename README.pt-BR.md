# Kindle Lichess

[English](README.md)

Kindle Lichess é um plugin independente e de código aberto para jogar partidas de xadrez
contra pessoas no Lichess por meio do KOReader e de uma tela e-ink.

> **Prévia de desenvolvimento ainda não publicada.** O repositório ainda não está pronto
> para lançamento ao público geral. A autenticação da conta real exige token temporário
> instalado manualmente e acesso SSH. O login público suportado ainda está sendo projetado.

O Kindle Lichess não é afiliado nem endossado pelo Lichess, KOReader ou Amazon.

## Compatibilidade atual

A validação completa no aparelho foi realizada em:

- Kindle Basic de 10ª geração, também chamado KT4/KindleHF;

- KOReader 2026.03;

- bridge ARMv7 hard-float incluído no pacote.

Outros modelos de Kindle e versões do KOReader ainda não foram testados. Não presuma que
um aparelho é compatível somente porque consegue executar o KOReader.

O KOReader classifica plugins desenvolvidos de forma independente como externos: eles
precisam ser instalados e atualizados manualmente e não são revisados pelos
desenvolvedores do KOReader. Consulte o
[guia oficial do KOReader](https://koreader.rocks/user_guide/).

## Funcionalidades

- Partidas casuais contra pessoas pela Board API oficial do Lichess.

- Desafios recebidos e enviados.

- Busca pública de adversário com controles de tempo compatíveis com a Board API.

- Controles de tempo personalizados.

- Validação de lances, promoção, roque e en passant.

- Relógios, reconexão e estado autoritativo vindo do servidor.

- Peças capturadas e vantagem material.

- Revisão do movimento anterior/seguinte durante e depois da partida.

- Exportação PGN ao terminar.

- Chat privado entre jogadores mantido somente na memória.

- Tabuleiro livre com importação FEN.

- Interface em inglês e português brasileiro.

- Exportação de diagnóstico sanitizado.

O pacote online não contém engine, avaliação, explorador de aberturas, tablebase ou
recomendação de jogadas.

## Fair play

As partidas online usam a Board API oficial com a permissão mínima board:play. O Lichess
determina que tabuleiros de terceiros usem essa API e proíbe engine ou outra assistência
externa durante partidas em tempo real:

- [Orientação do Lichess para eBoards](https://lichess.org/page/eboards)

- [Regras de fair play do Lichess](https://lichess.org/page/fair-play)

O escopo da primeira versão é de partidas casuais. Não use o Kindle Lichess junto com
engine, livro de aberturas, tablebase ou outra fonte de sugestão de jogadas.

## Instalação

Ainda não existe artefato público suportado. Para builds locais de desenvolvimento:

1. Compile e empacote o projeto conforme a seção [Desenvolvimento](#desenvolvimento).
2. Extraia dist/kindlelichess-koplugin-armv7.tar.gz no computador.
3. Conecte o Kindle por USB.
4. Copie o diretório kindlelichess.koplugin completo para koreader/plugins no Kindle.
5. Ejete o Kindle com segurança e reinicie o KOReader.
6. Abra Ferramentas → Kindle Lichess.

Não copie somente arquivos individuais. O diretório inclui manifesto, interface Lua,
ativos e o bridge ARM correspondente.

As instruções detalhadas de instalação, atualização, rollback e remoção estão em
[docs/installation.pt-BR.md](docs/installation.pt-BR.md).

## Estado da autenticação

O modo simulado funciona sem conta do Lichess.

O modo de conta real está restrito a testes de desenvolvimento. Ele exige um token
pessoal somente com a permissão board:play, armazenado temporariamente em
/tmp/kindle-lichess-token com modo 0600. O arquivo não é persistido em /mnt/us porque
esse sistema de arquivos não aplica permissões privadas Unix.

Esse fluxo manual não é adequado para uma aplicação pública. O Lichess recomenda tokens
pessoais apenas para uso próprio ou por poucas pessoas com experiência técnica e
recomenda OAuth Authorization Code com PKCE para clientes públicos:

- [Orientação oficial de autenticação do Lichess](https://github.com/lichess-org/api/blob/master/example/README.md)

- [Especificação oficial da API](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml)

Nunca publique um token em issue, log, screenshot, fórum ou chat. Revogue imediatamente
um token comprometido em [Tokens da API do Lichess](https://lichess.org/account/oauth/token).

## Idioma

Abra Ferramentas → Kindle Lichess → Idioma e escolha:

- Automático (KOReader);

- Inglês;

- Português (Brasil).

O modo automático acompanha o KOReader quando português brasileiro estiver selecionado
e usa inglês como fallback para idiomas ainda não suportados.

Reinicie o KOReader depois de atualizar o plugin para recarregar todos os módulos.

## Arquivos PGN

Partidas encerradas podem ser salvas na tela de resultado. Por padrão, os arquivos ficam
em:

    /mnt/us/documents/KindleLichess/

O PGN pode conter nomes dos jogadores, ratings, horário, lances e URL da partida no
Lichess. Ele é um documento do usuário e não é enviado pelo Kindle Lichess.

## Privacidade e diagnóstico

O Kindle Lichess não possui telemetria ou análise controlada pelo projeto. No modo real,
a rede acessa https://lichess.org. A interface Lua conversa com o bridge local por um
socket Unix privado.

O diagnóstico exportado contém somente uma allowlist fixa: versão do formato, versão
pré-release do plugin, idioma, modo do bridge e último código interno de erro. Ele não
contém conta, ID de partida, chat, posição, PGN nem token.

Use Ferramentas → Kindle Lichess → Exportar diagnóstico sanitizado. O arquivo será salvo
em:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

Leia o [aviso completo de privacidade](docs/privacy.pt-BR.md) antes de compartilhar
informações do aparelho.

## Solução de problemas

Falhas como token_missing, auth_forbidden, network_error, rate_limited e
socket_unavailable possuem mensagens diferentes e acionáveis.

Consulte [docs/troubleshooting.pt-BR.md](docs/troubleshooting.pt-BR.md). Nunca anexe o
arquivo do token ou um crash.log do KOReader sem revisão a uma issue pública.

## Atualização e rollback

Antes de atualizar, feche o Kindle Lichess e guarde uma cópia do diretório
kindlelichess.koplugin instalado. Substitua o diretório inteiro pelo diretório da nova
versão e reinicie o KOReader.

Os PGNs ficam fora do diretório do plugin. As configurações do KOReader também ficam
separadas. Para rollback, feche o plugin, restaure o diretório salvo e reinicie o
KOReader.

## Limitações conhecidas

- Login OAuth público ainda não implementado.

- O modo real exige SSH e token pessoal efêmero.

- Somente KT4/KindleHF com KOReader 2026.03 completou a validação no aparelho.

- A suíte de integração do KOReader no host depende de uma árvore já compilada e pode ser
  ignorada quando KOREADER_SOURCE não estiver configurado.

- O histórico do chat começa quando o stream da partida é aberto; mensagens anteriores
  não são buscadas.

- Somente xadrez padrão é suportado.

- O escopo da primeira versão é de partidas casuais.

- Não existe atualização automática.

## Desenvolvimento

Execute os testes Lua:

    ./scripts/test.sh

Execute também a integração com uma árvore compilada do KOReader:

    KOREADER_SOURCE=/caminho/absoluto/para/koreader ./scripts/test.sh

Execute formatação, vet, testes e race checks do Go:

    ./scripts/test-go.sh

Compile e verifique o bridge ARM:

    ./scripts/build-armv7.sh
    ./scripts/verify-binary.sh

Crie o arquivo de distribuição:

    ./scripts/package.sh

O pacote não inclui token real, logs locais, partidas salvas ou documentos privados de
planejamento.

## Segurança

Leia [SECURITY.md](SECURITY.md) antes de relatar uma vulnerabilidade. Não abra uma issue
pública contendo token, chat privado, identificador de conta, identificador de partida
ou log bruto do aparelho.

## Documentação do projeto

- [Arquitetura](docs/architecture.md)

- [Contrato da API do Lichess](docs/lichess-api.md)

- [Projeto de segurança](docs/security.md)

- [Plano de testes](docs/test-plan.md)

- [Licenciamento e proveniência](docs/licensing.md)

- [Backlog de desenvolvimento](docs/mvp-backlog.md)

## Licença

O código próprio é licenciado sob GPL-3.0-or-later. Consulte [LICENSE](LICENSE),
[NOTICE](NOTICE) e [docs/licensing.md](docs/licensing.md).

Mantenedor: [odevpedro](https://github.com/odevpedro).
