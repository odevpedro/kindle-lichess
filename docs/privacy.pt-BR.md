# Aviso de privacidade

[English](privacy.md)

Última atualização: 15 de agosto de 2026.

Este aviso descreve a prévia de desenvolvimento ainda não publicada. Ele deve ser revisto
antes do lançamento porque o OAuth planejado pode alterar o tratamento de credenciais.

## Resumo

O Kindle Lichess não possui telemetria, análise, publicidade ou servidor de logs operado
pelo projeto.

No modo real, o bridge conversa com https://lichess.org para autenticar a conta, receber
desafios e partidas, enviar ações do usuário e trocar mensagens do chat da partida. Dentro
do Kindle, o plugin Lua conversa com o bridge por um socket Unix privado.

## Dados processados na memória

O plugin pode manter temporariamente:

- ID e nome da conta Lichess;

- nome e rating do adversário;

- identificadores de desafio e partida;

- posição, histórico de lances, relógios e resultado;

- chat privado da sala de jogadores recebido durante o stream;

- último código interno de erro.

Esses dados são necessários para mostrar e controlar a sessão. Conta, partida, posição e
chat não entram no diagnóstico sanitizado.

## Credenciais

O fluxo atual de desenvolvimento lê um token pessoal do Lichess em:

    /tmp/kindle-lichess-token

O bridge Go, não a interface Lua, lê o token. O arquivo deve ter modo 0600. O token não
passa pelo protocolo JSON, não é impresso em erros, não entra no pacote nem é escrito em
PGN ou diagnóstico.

Ele é enviado somente como autorização HTTPS para https://lichess.org. A autorização não
é encaminhada a outro host após redirecionamento.

O token não é persistido sob /mnt/us porque esse sistema de arquivos não aplica as
permissões Unix privadas necessárias. Uma reinicialização pode removê-lo.

A versão pública exige outro desenho com OAuth PKCE. O mecanismo atual não deve ser
apresentado como onboarding público.

## Destinos de rede

O modo real de produção permite:

- requisições e streams HTTPS para https://lichess.org;

- socket Unix local em /tmp/kindle-lichess.sock.

O projeto não opera servidor de análise, relay, publicidade ou crash report. Builds de
teste podem usar um servidor falso local explicitamente configurado; essa configuração
não faz parte do pacote de produção.

## Chat

Somente a sala privada dos jogadores é exposta. Chat de espectadores é descartado.

Até 40 mensagens recentes ficam na memória durante a partida. Elas não entram em PGN,
configuração, diagnóstico ou log do projeto. O histórico anterior à abertura do stream
não é buscado. Chat malformado é descartado sem registrar o conteúdo.

O Lichess recebe e processa o chat segundo as políticas próprias.

## Arquivos PGN

Ao selecionar Salvar PGN, o Kindle Lichess escreve um documento em:

    /mnt/us/documents/KindleLichess/

O PGN pode conter nomes, ratings, data, histórico completo de lances, resultado, FEN
inicial quando personalizado e URL pública da partida no Lichess. Ele permanece no
Kindle até o usuário mover ou apagar.

O Kindle Lichess não envia o PGN exportado.

## Configurações

As configurações do KOReader podem persistir:

- modo do bridge;

- idioma;

- controle de tempo;

- caminhos não secretos configurados;

- último código interno de erro pertencente à allowlist.

As configurações não devem conter token, conta, ID de partida, chat ou posição.

## Diagnóstico sanitizado

O usuário pode criar:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

O arquivo usa uma allowlist rígida e contém:

- versão do formato;

- rótulo da versão do plugin;

- idioma;

- modo do bridge;

- último código interno reconhecido;

- declarações explícitas de ausência de conta, partida, chat, posição e token.

Valores desconhecidos viram unknown em vez de serem copiados. A exportação nunca lê token,
PGN, transcript do chat, posição atual ou crash.log do KOReader.

Mesmo assim, revise o arquivo antes de compartilhar.

## Logs

O bridge escreve no stderr somente códigos operacionais limitados e pertencentes a uma
allowlist. Um evento rejeitado é representado por tipo conhecido e código conhecido. JSON
bruto, usuários, IDs de partida, posições, chat e texto bruto do erro não são registrados.

Builds antigos de desenvolvimento registraram parte de um evento rejeitado. Um crash.log
criado por uma versão antiga pode conter informações de conta ou partida. Não publique um
crash.log antigo ou sem revisão. Prefira o diagnóstico sanitizado.

## Retenção e exclusão

- Sessão e chat em memória desaparecem quando a sessão/processo termina.

- Token temporário pode desaparecer ao reiniciar e pode ser removido pelo desenvolvedor
  que o instalou.

- PGNs e diagnósticos permanecem até o usuário removê-los.

- Configurações permanecem até serem removidas pelo KOReader ou no armazenamento dele.

- Remover o plugin não remove automaticamente os PGNs.

## Compartilhamento de bugs

Seguro por padrão:

- diagnóstico sanitizado depois de revisão pessoal;

- código exato do erro;

- modelo, firmware, versão do KOReader e versão do plugin.

Não compartilhe:

- token ou arquivo do token;

- cabeçalho Authorization;

- crash.log bruto sem revisar linha por linha;

- chat privado;

- identificadores de conta/partida sem necessidade consciente e redução adequada;

- PGN privado sem consentimento.

Para vulnerabilidades, siga [SECURITY.md](../SECURITY.md).

## Terceiros

Lichess e KOReader são projetos independentes com políticas próprias. Kindle Lichess não
é afiliado ao Lichess, KOReader ou Amazon.

Referências oficiais:

- [Segurança de tokens e OAuth do Lichess](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml)

- [Orientação de autenticação do Lichess](https://github.com/lichess-org/api/blob/master/example/README.md)

- [Orientação sobre plugins externos do KOReader](https://koreader.rocks/user_guide/)
