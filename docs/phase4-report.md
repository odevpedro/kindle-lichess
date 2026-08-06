# Relatório da Fase 4 — build ARMv7

Status: concluída em ambiente isolado, com validação nativa pendente.
Data: 2026-08-06.
Branch: `phase/4-arm-build`.

## Artefato

| Propriedade | Resultado |
|---|---|
| caminho local | `dist/armv7/kindle-lichess-bridge` |
| tamanho | 6.226.046 bytes |
| SHA-256 | `77c1ef20f10385190000a8b1938ef882298690110ef754256075fc69c6289d40` |
| formato | ELF32 little-endian, ARM, EABI5, executável |
| ligação | estática, sem `PT_INTERP` e sem seção dinâmica |
| símbolos | stripped |
| build | `CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7` |

A toolchain foi `go1.26.5` na imagem fixada
`golang:1.26.5-bookworm@sha256:6c5605ab3a9a9fb3c4eafe5b3d63cdbf3881caf113262b67862547b54a9db599`.
O build usa `-trimpath -buildvcs=false -ldflags="-s -w -buildid="`. Duas compilações
consecutivas produziram o mesmo SHA-256.

`GOARM=7` usa hard-float por padrão na toolchain fixada. O cabeçalho retornou flags
`0x5000002, Version5 EABI, <unknown>`; a conclusão sobre hard-float vem da configuração
embutida do Go e de `go help environment`, não de um rótulo inventado do `readelf`.

## Execução isolada

Foi baixado `qemu-user-static 1:8.2.2+ds-0ubuntu1.17` como `.deb`, extraído somente em
`/tmp` e removido após o teste; nenhum pacote foi instalado.

O binário ARM real, com o CA bundle do build KOReader, apresentou:

```text
execution=ok
socket_create=ok
sigterm_exit=0
socket_cleanup=ok
qemu_max_rss_kib=20568
```

Nenhum cliente abriu o socket, portanto o teste não iniciou HTTPS nem usou o token na
rede. O RSS de 20.568 KiB inclui QEMU e é apenas um limite conservador; não representa
uma medição nativa no KT4.

## Confiança TLS

O bridge ganhou `-ca-file` opcional. No Kindle, o plugin resolve o caminho absoluto do
`data/ca-bundle.crt` que já pertence ao KOReader. O bridge aceita somente arquivo regular,
PEM válido e limitado a 2 MiB. Verificação de certificado e hostname permanecem ativas;
nenhum arquivo é gravado no diretório do KOReader nem em `/etc`.

Sem `-ca-file`, os probes desktop continuam usando o trust store normal do sistema.
Com o bundle explícito do build KOReader, `GET /api/account` real foi aprovado e retornou
somente a conta sanitizada `testkindle`.

## Testes

- 64/64 verificações Lua;
- 7/7 testes no runtime KOReader;
- 8/8 pacotes Go com `gofmt`, `go vet` e `go test -race`;
- handshake TLS local aprovado com CA explícito;
- handshake real com `lichess.org` aprovado usando o CA bundle do KOReader;
- CA inválido rejeitado sem vazar caminho;
- sintaxe dos três scripts ARM aprovada;
- inspeção ELF e duas compilações reproduzíveis aprovadas;
- execução, socket, SIGTERM e limpeza sob QEMU aprovados.

## Riscos pendentes

Go 1.26 requer Linux 3.2 ou superior; sistemas mínimos também precisam de `CONFIG_FUTEX`
e `CONFIG_EPOLL`. A versão e configuração reais do kernel do KT4 não foram consultadas.
Também não foram medidos RSS nativo, DNS, TLS ou `fork/exec` no Kindle.

Esses itens exigem a Fase 5 e autorização explícita antes de qualquer transferência. O
primeiro teste no dispositivo deve usar MockBridge; depois, iniciar o ARM sem cliente de
rede e verificar socket/processo; somente então habilitar a conta real.

## Arquivos da fase

- `scripts/build-armv7.sh`;
- `scripts/verify-binary.sh`;
- `scripts/test-armv7-qemu.sh`;
- `bridge/cmd/kindle-lichess-bridge/{main.go,main_test.go}`;
- `plugin/kindlelichess.koplugin/{main.lua,bridge/live_bridge.lua,bridge/process.lua}`;
- `plugin/kindlelichess.koplugin/tests/koreader_spec.lua`;
- `docs/{phase4-report.md,security.md,deployment.md}`;
- `README.md`.

O artefato em `dist/` é ignorado pelo Git. Nenhum arquivo foi enviado ao Kindle.
