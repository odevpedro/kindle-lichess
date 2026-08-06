# ADR-0006 — Lichess falso como teste de contrato permanente

Status: aceito.

## Contexto

Streams NDJSON, reconexão e respostas HTTP de erro são difíceis de reproduzir de forma
segura contra produção. Usar o Lichess real nesses testes exigiria rede, credencial,
contas e rate limit, além de produzir resultados não determinísticos.

## Decisão

A Fase 2 usa `net/http/httptest` da biblioteca padrão do Go. Cada teste implementa apenas
o endpoint e a sequência de bytes necessários ao comportamento sob teste. Não haverá um
clone geral do Lichess, executável separado ou servidor incluído no pacote final.

As fixtures e handlers permanecem na suíte após a integração real. Eles validam o contrato
do cliente para:

- chunks NDJSON fragmentados, agrupados, vazios ou interrompidos;
- códigos 401, 403, 404 e 429, incluindo `Retry-After`;
- confirmação e rejeição de mutations;
- cancelamento, fechamento de bodies e reconexão determinística;
- ausência do token em logs, erros e mensagens IPC.

## Limites

O falso servidor não tenta simular matchmaking, regras de xadrez, interface web, Bot API
ou detalhes internos do Lichess. Formatos vêm somente da Board API documentada. Testes
reais no computador continuam obrigatórios na Fase 3 porque um falso servidor não prova
TLS público, política de produção ou mudanças incompatíveis da API.

## Toolchain

O módulo declara Go 1.26 e é testado com a imagem oficial
`golang:1.26.5-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599`.
Não são instalados pacotes Go no host e a implementação prioriza a biblioteca padrão.
