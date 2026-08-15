# Viabilidade do chat do Lichess

Decisão: **GO**, com escopo restrito ao chat privado entre os dois jogadores durante
uma partida ativa.

## Contrato oficial confirmado

- o Board API aceita `POST /api/board/game/{gameId}/chat` com o escopo OAuth
  `board:play` já necessário para jogar;
- o corpo usa formulário com `room=player` e `text=<mensagem>`;
- o stream da partida já utilizado pelo bridge entrega eventos `chatLine` contendo
  `room`, `username` e `text`;
- existe também leitura pontual do histórico pelo endpoint de chat, mas ela não é
  necessária para o primeiro escopo em tempo real.

Referências oficiais:

- <https://github.com/lichess-org/api/blob/master/doc/specs/tags/board/api-board-game-gameId-chat.yaml>
- <https://github.com/lichess-org/api/blob/master/doc/specs/tags/board/api-board-game-stream-gameId.yaml>
- <https://github.com/lichess-org/api/blob/master/doc/specs/schemas/ChatLineEvent.yaml>
- <https://lichess.org/page/chat-etiquette>

## Escopo implementado

- somente sala `player`; mensagens de espectadores são descartadas;
- composição manual pelo teclado do KOReader e transcript das cinco mensagens mais
  recentes na tela, com até 40 retidas na sessão;
- contador de não lidas para mensagens do adversário;
- limite local de 280 bytes, sem campos vazios ou caracteres de controle;
- nenhuma persistência em arquivo, PGN, configurações ou logs;
- texto malformado recebido é descartado sem encerrar/reconectar o stream;
- um POST de chat que falha ou expira não é repetido automaticamente, pois o servidor
  pode já ter publicado a mensagem.

## Limitação deliberada

O primeiro escopo mostra apenas mensagens observadas enquanto o stream da partida está
aberto. A leitura retroativa pelo endpoint `GET` não foi adicionada, então mensagens
anteriores à conexão ou perdidas numa desconexão não são recompostas. O chat fecha ao
terminar a partida, quando o stream oficial também termina. Essa limitação evita nova
requisição, persistência de conteúdo privado e uma interface de histórico mais pesada
no e-ink; pode ser reavaliada separadamente.
