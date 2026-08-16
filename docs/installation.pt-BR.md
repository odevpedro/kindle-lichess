# Instalação, atualização, rollback e remoção

[English](installation.md)

## Estado da versão

O Kindle Lichess ainda é uma prévia de desenvolvimento não publicada. Estas instruções
documentam o formato pretendido do pacote e o procedimento já usado no KT4 testado. Elas
não transformam o build atual em uma versão pública suportada.

A autenticação de conta real ainda não está pronta para usuários em geral, pois exige um
token efêmero instalado por SSH. O modo simulado não exige token.

## Requisitos

- Kindle com KOReader já instalado e funcionando.

- Espaço livre para o plugin e o bridge ARM estático de aproximadamente 6 MiB.

- Pacote completo do Kindle Lichess produzido pelo script do repositório.

- Computador capaz de extrair tar.gz e copiar arquivos por USB.

A única configuração completamente validada é Kindle Basic 10ª geração
KT4/KindleHF com KOReader 2026.03. O bridge incluído tem como alvo ARMv7 hard-float.

Jailbreak do Kindle e instalação do KOReader estão fora do escopo deste projeto. Use a
documentação específica para o modelo e firmware exatos; não aplique instruções feitas
para outro aparelho.

## Verificar o pacote

Em uma futura GitHub Release, baixe o pacote e o arquivo SHA256SUMS da mesma versão.
Compare o checksum antes de extrair.

Para um build local:

    ./scripts/build-armv7.sh
    ./scripts/verify-binary.sh
    ./scripts/package.sh

O pacote gerado será:

    dist/kindlelichess-koplugin-armv7.tar.gz

Depois da extração, o diretório superior deve se chamar exatamente:

    kindlelichess.koplugin

Ele deve conter MANIFEST.sha256, main.lua, controller.lua, i18n.lua,
bin/kindle-lichess-bridge e os diretórios bridge, chess, icons, storage e ui.

## Instalação limpa por USB

1. Feche o Kindle Lichess se estiver aberto.
2. Conecte o Kindle ao computador por USB.
3. Extraia o pacote no computador.
4. Abra o diretório koreader/plugins no armazenamento do Kindle.
5. Copie o diretório kindlelichess.koplugin completo para koreader/plugins.
6. Confirme que o resultado é koreader/plugins/kindlelichess.koplugin/main.lua, sem
   duplicação de diretórios.
7. Ejete o Kindle com segurança.
8. Reinicie o KOReader.
9. Abra Ferramentas → Kindle Lichess.

Não coloque o arquivo compactado diretamente em koreader/plugins. Não misture arquivos de
versões diferentes.

O KOReader informa que plugins externos são instalados e atualizados manualmente e não
são revisados pelos desenvolvedores do KOReader:
[guia do usuário do KOReader](https://koreader.rocks/user_guide/).

## Primeiro uso

Comece pelo modo simulado:

1. Abra Ferramentas → Kindle Lichess.
2. Selecione Modo simulado.
3. Abra o Kindle Lichess.
4. Aceite o desafio simulado.
5. Confirme tabuleiro, relógios, ações, chat e tela de resultado.

Escolha o idioma em Ferramentas → Kindle Lichess → Idioma. O modo automático acompanha
o KOReader em português brasileiro e usa inglês como fallback nos demais idiomas.

## Modo de desenvolvimento com conta real

O modo real não possui onboarding público suportado. Atualmente ele espera um token
pessoal do Lichess somente com board:play em:

    /tmp/kindle-lichess-token

O arquivo precisa ser regular, pertencer ao usuário do processo e ter modo 0600. Ele é
temporário e pode desaparecer depois de uma reinicialização.

Nunca salve o token em texto puro sob /mnt/us. Nunca o coloque no diretório do plugin, em
PGN, diagnóstico, histórico do shell, issue ou repositório Git.

A orientação oficial do Lichess reserva tokens pessoais ao uso próprio ou por poucas
pessoas experientes, não a um aplicativo público. A distribuição continua bloqueada até
a implementação de OAuth PKCE:
[orientação de autenticação do Lichess](https://github.com/lichess-org/api/blob/master/example/README.md).

## Atualização

1. Leia as notas da versão e a compatibilidade declarada.
2. Feche o Kindle Lichess.
3. Conecte o Kindle por USB.
4. Renomeie o diretório instalado para um nome de backup que não termine em .koplugin,
   como kindlelichess.koplugin.rollback.
5. Copie o novo diretório kindlelichess.koplugin completo para koreader/plugins.
6. Ejete o Kindle com segurança.
7. Reinicie o KOReader.
8. Teste o modo simulado antes de usar a conta real.
9. Mantenha o rollback até a nova versão completar um smoke test.

Não substitua arquivos Lua isolados enquanto o Kindle Lichess estiver aberto. O KOReader
mantém módulos em memória, e a mistura de memória antiga com arquivos novos pode produzir
falhas enganosas.

## Dados preservados

Substituir somente o diretório do plugin não remove:

- PGNs em /mnt/us/documents/KindleLichess;

- diagnóstico sanitizado no mesmo diretório;

- configurações do KOReader armazenadas fora do plugin;

- token temporário em /tmp enquanto a sessão atual do sistema preservar o arquivo.

O token pode desaparecer após reiniciar o aparelho. Isso é esperado na prévia atual.

## Rollback

1. Feche o Kindle Lichess.
2. Conecte o Kindle por USB.
3. Mova o kindlelichess.koplugin com problema para fora de koreader/plugins.
4. Renomeie o backup novamente para kindlelichess.koplugin.
5. Ejete o Kindle com segurança.
6. Reinicie o KOReader.
7. Teste o modo simulado.

Sem backup, instale um pacote anterior preservado e verificado por checksum. Não combine
arquivos de duas versões.

## Remoção

1. Feche o Kindle Lichess.
2. Reinicie o KOReader se o bridge não tiver encerrado corretamente.
3. Conecte o Kindle por USB.
4. Mova ou apague somente koreader/plugins/kindlelichess.koplugin.
5. Reinicie o KOReader.

Dados opcionais podem ser removidos separadamente:

- /mnt/us/documents/KindleLichess contém PGNs e diagnóstico sanitizado;

- preferências do Kindle Lichess permanecem nas configurações do KOReader.

Revise os PGNs antes de apagá-los. Eles são documentos do usuário e não podem ser
reconstruídos pelo plugin depois da remoção.

## Smoke test

Depois de uma instalação ou atualização, confirme:

- Kindle Lichess aparece em Ferramentas;

- seleção de idioma funciona;

- modo simulado abre e fecha sem deixar janelas;

- diálogos de desafio, tempo, FEN e chat aparecem dentro do plugin;

- partida simulada chega ao resultado;

- navegação pelo histórico funciona;

- exportação PGN cria arquivo legível;

- diagnóstico sanitizado não contém conta, partida, chat, posição ou token;

- fechar o plugin encerra bridge e socket local.

## Recuperação

Se o plugin não aparecer, confira o aninhamento do diretório e reinicie o KOReader.

Se aparecer um erro do bridge, consulte
[troubleshooting.pt-BR.md](troubleshooting.pt-BR.md). Não reinstale repetidamente antes de
anotar o código exato e a versão instalada.
