# Solução de problemas

[English](troubleshooting.md)

Este guia vale para a prévia de desenvolvimento não publicada. Anote o código exato antes
de reiniciar ou reinstalar.

## Primeiros passos seguros

1. Feche o Kindle Lichess.
2. Confirme o Wi-Fi ao usar modo real.
3. Reabra o plugin uma vez.
4. Se continuar, reinicie o KOReader.
5. Exporte o diagnóstico sanitizado em Ferramentas → Kindle Lichess.
6. Teste o modo simulado para separar falhas de UI de falhas de bridge/rede.

Não compartilhe token, arquivo do token, cabeçalho Authorization, chat, PGN privado ou
crash.log sem revisão.

## Referência de erros

| Código | Significado | Ação recomendada |
|---|---|---|
| token_missing | O token temporário do modo real não existe | Prévia: instale novamente o token board:play ou use o modo simulado |
| token_permissions | O bridge rejeitou tipo, dono ou modo inseguros | Use arquivo regular pertencente ao processo com modo exato 0600 |
| token_invalid | O arquivo está vazio ou malformado | Revogue se necessário, crie outro token board:play e substitua o arquivo |
| auth_unauthorized | O Lichess recusou o token | Revogue/recrie e confirme a conta de teste |
| auth_forbidden | Falta a permissão board:play | Crie token somente com a permissão necessária board:play |
| not_found | Desafio ou partida não existe mais | Volte ao lobby e crie ou aceite outro desafio |
| lichess_rejected | O Lichess recusou a ação | Atualize o estado; o desafio pode ter expirado ou o lance não se aplica mais |
| rate_limited | O Lichess pediu menos requisições | Pare de repetir, aguarde o tempo indicado e tente uma vez |
| network_timeout | O Lichess não respondeu a tempo | Confira o Wi-Fi e aguarde estabilizar |
| network_error | Falha de DNS, rota, TLS ou conexão | Confira Wi-Fi e data/hora; tente após recuperar a rede |
| http_error | Erro temporário do servidor Lichess | Aguarde; verifique o estado do serviço se persistir |
| process_start_failed | KOReader não iniciou o bridge ARM | Reinicie e confira se o pacote instalado está completo |
| socket_unavailable | O bridge não disponibilizou o socket | Reinicie; confira token e bridge ARM correspondente |
| socket_in_use | Outro processo já usa o socket | Feche todas as sessões e reinicie o KOReader |
| unsafe_socket_path | O caminho do socket não é seguro | Reinicie; não substitua o caminho por arquivo ou symlink |
| bridge_closed | O bridge encerrou a conexão | Reabra; se repetir, exporte diagnóstico |
| socket_read_failed | Falha ao ler a comunicação local | Reabra e reinicie o KOReader se repetir |
| socket_write_failed | Falha ao escrever na comunicação local | Reabra e não repita uma ação de partida de resultado incerto |
| ca_file_invalid | CA bundle do KOReader ausente/inválido | Repare/atualize o KOReader; não desative TLS |
| invalid_json | Mensagem local ou remota malformada | Reabra e relate o código se reproduzível |
| invalid_response | Resposta do Lichess incompatível com a versão | Atualize ou relate o fluxo reproduzível |
| message_too_large | Mensagem excedeu o limite de segurança | Reabra e relate o fluxo exato |
| internal | Falha interna inesperada | Reinicie, exporte diagnóstico e relate a reprodução |

O código entre parênteses é mantido para suporte. A descrição é traduzida, mas o código
permanece igual em todos os idiomas.

## Mensagem antiga bridge communication failed

Builds antigos podiam mostrar:

    bridge communication failed (socket_unavailable)

mesmo quando faltava o token. O build atual verifica a presença antes de iniciar o
subprocesso e mostra token_missing diretamente. Outras falhas muito precoces ainda podem
virar socket_unavailable; use a tabela e o diagnóstico sanitizado.

## Plugin não aparece

- Confira koreader/plugins/kindlelichess.koplugin/main.lua.

- Confira se não existe outro kindlelichess.koplugin aninhado.

- O nome deve terminar exatamente em .koplugin.

- Reinicie o KOReader depois da cópia.

- Confira se a versão do KOReader corresponde a uma configuração testada.

## Diálogo aparece fora do plugin

Reinicie o KOReader para limpar módulos Lua em cache. Teste usuário do desafio, tempo
personalizado, FEN e chat.

Se a janela só aparecer depois de sair, registre:

- diálogo aberto;

- idioma;

- modelo;

- versão do KOReader;

- se o modo simulado também falha.

Não inclua usuário, FEN ou chat real; use valores sintéticos.

## Falhas de rede

- Confirme acesso à internet.

- Confira data e hora para validação TLS.

- Não desative TLS nem troque HTTPS por HTTP.

- Não reabra rapidamente depois de rate_limited.

- Se o modo simulado funciona e o real falha, investigue token, rede, certificado e
  resposta do Lichess.

## Falhas de desafio

- not_found normalmente indica desafio expirado/cancelado.

- auth_forbidden indica escopo errado.

- lichess_rejected indica ação recusada.

- A busca pública aceita controles compatíveis com a Board API; controles rápidos podem
  ficar limitados a desafios diretos pelas regras de eBoard.

Consulte a [orientação para eBoards](https://lichess.org/page/eboards).

## Exportação PGN

Diretório esperado:

    /mnt/us/documents/KindleLichess/

Em caso de falha:

- confira o diretório documents;

- confira espaço livre;

- não remova o armazenamento com KOReader em execução;

- preserve o código exato;

- não apague outro PGN como solução improvisada.

## Diagnóstico sanitizado

Use Ferramentas → Kindle Lichess → Exportar diagnóstico sanitizado. O arquivo é:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

Revise antes de compartilhar. As chaves esperadas são format, plugin_version, language,
bridge_mode, last_error e cinco declarações contains_*.

Se aparecer conta, partida, posição, chat ou token, não compartilhe. Trate como falha de
segurança e siga [SECURITY.md](../SECURITY.md).

## Relatar bug

Inclua:

- modelo e firmware;

- versão do KOReader;

- versão/commit do Kindle Lichess;

- idioma e modo do bridge;

- código estável do erro;

- passos mínimos;

- se o modo simulado reproduz;

- diagnóstico sanitizado revisado.

Não publique bugs sensíveis.
