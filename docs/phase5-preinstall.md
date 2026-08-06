# Fase 5 — auditoria pré-instalação

Status: concluída; Gates 1–3 executados e registrados na Fase 6.
Data: 2026-08-06.
Branch: `phase/5-preinstall-audit`.

## Pacote

| Item | Valor |
|---|---|
| arquivo local | `dist/kindlelichess-koplugin-armv7.tar.gz` |
| tamanho | 2.603.805 bytes |
| SHA-256 | `2f2670fc4ac58f9c7b1a8187f4bf06daf43fedcfef4a1584e9879c476113cd53` |
| diretório raiz | `kindlelichess.koplugin/` |
| executável ARM | `bin/kindle-lichess-bridge` |
| SHA-256 do ARM | `77c1ef20f10385190000a8b1938ef882298690110ef754256075fc69c6289d40` |

Duas execuções consecutivas de `scripts/package.sh` produziram o mesmo hash. Todos os
arquivos regulares, exceto o próprio `MANIFEST.sha256`, estão listados em
`docs/package-manifest-armv7.sha256`; `sha256sum -c` aprovou todas as entradas.

O pacote não contém testes, token real, logs, banco de dados, engine, Stockfish, serviço,
autostart, Upstart, cron ou código do submódulo upstream.

## Validações executadas

- `bash -n scripts/*.sh`: aprovado;
- testes Lua puros: 64/64 aprovados;
- testes no runtime oficial do KOReader: 7/7 aprovados;
- `gofmt`, `go vet` e `go test -race`: 8/8 pacotes aprovados;
- duas construções consecutivas do pacote: SHA-256 idêntico;
- `sha256sum -c MANIFEST.sha256`: todos os 33 arquivos aprovados;
- manifesto documentado comparado byte a byte com o manifesto empacotado: idêntico;
- varreduras de token, engine, banco, serviço e caminhos inseguros: nenhuma ocorrência.

## Arquivos modificados na Fase 5

- `README.md`;
- `docs/package-manifest-armv7.sha256`;
- `docs/phase5-preinstall.md`;
- `scripts/package.sh`.

O tarball e seu staging ficam em `dist/`, que permanece ignorado pelo Git.

## Riscos remanescentes antes da instalação

- o kernel e a configuração efetivos do KT4 ainda não foram lidos;
- o executável ARM ainda não foi iniciado nativamente no Kindle;
- consumo de RAM nativo ainda não foi medido; a medição anterior inclui overhead do QEMU;
- existência do CA bundle e dos utilitários esperados ainda depende do preflight;
- toque, orientação e política de refresh e-ink ainda não foram observados no hardware;
- como a USB está danificada, instalação e reversão dependem do SSH por Wi-Fi funcional.

Esses itens são justamente os gates de hardware abaixo. Nenhum deles será marcado como
aprovado por inferência.

## Scripts completos para revisão

- `scripts/build-armv7.sh` — cross-build fixado;
- `scripts/verify-binary.sh` — inspeção ELF;
- `scripts/test-armv7-qemu.sh` — execução isolada;
- `scripts/package.sh` — conteúdo e tarball reproduzível.

| Script | SHA-256 |
|---|---|
| `scripts/build-armv7.sh` | `2f81b4ff0a78b2e0671f924650d1be85451df66b2f0816badf26bcc457d87ed1` |
| `scripts/verify-binary.sh` | `83731e2faccc69d2e2eb737d935583bc422e8ec5882b07f05d2fe7859a517aa3` |
| `scripts/test-armv7-qemu.sh` | `e0babf0901bc307713e4f7f9717af18d8baeb5a5c730cb0f514864a14726bf74` |
| `scripts/package.sh` | `fee69ab4f260d81709bb9bef8ac23a40f84f02bca9b1ad6a84cbb92893ecb77d` |

Nenhum script de instalação oculto será usado. As operações remotas planejadas estão
integralmente descritas abaixo e serão executadas uma a uma, com validação entre gates.

## Destinos e escritas

Antes do modo real:

- upload temporário: `/tmp/kindlelichess-koplugin-armv7.tar.gz`;
- staging temporário: `/tmp/kindle-lichess-install/`;
- plugin novo: `/mnt/us/koreader/plugins/kindlelichess.koplugin/`;
- socket/processos temporários: `/tmp/kindle-lichess*.sock`;
- token descartável do teste sem rede: `/tmp/kindle-lichess-placeholder-token`.

Somente depois de MockBridge e ciclo ARM aprovados:

- token efêmero: `/tmp/kindle-lichess-token`, modo real `0600` no tmpfs.

O CA bundle será somente lido de `/mnt/us/koreader/data/ca-bundle.crt`. Nenhuma operação
escreve em `/etc`, `/usr`, `/var/local`, `/opt`, `/root`, `/mnt/us/kmc`, `chess.koplugin`,
hotfix, KPM, KOReader original, appreg, firewall, SSH ou serviços Amazon.

## Gate 1 — preflight somente leitura

O host será substituído por um IP literal confirmado pelo usuário:

```sh
ssh -p 2222 root@<KINDLE_IP> '
set -eu
uname -a
sed -n "1,80p" /proc/cpuinfo
df -k /mnt/us /tmp
test -d /mnt/us/koreader/plugins
test -f /mnt/us/koreader/data/ca-bundle.crt
test ! -e /mnt/us/koreader/plugins/kindlelichess.koplugin
for command in tar gzip sha256sum ps pidof sed df cp chmod sync rm mkdir; do
    command -v "$command"
done
'
```

Qualquer resultado inesperado interrompe a instalação.

## Gate 2 — upload e verificação em `/tmp`

```sh
scp -P 2222 dist/kindlelichess-koplugin-armv7.tar.gz \
    root@<KINDLE_IP>:/tmp/kindlelichess-koplugin-armv7.tar.gz

ssh -p 2222 root@<KINDLE_IP> '
set -eu
echo "2f2670fc4ac58f9c7b1a8187f4bf06daf43fedcfef4a1584e9879c476113cd53  /tmp/kindlelichess-koplugin-armv7.tar.gz" \
    | sha256sum -c -
mkdir -p /tmp/kindle-lichess-install
tar -xzf /tmp/kindlelichess-koplugin-armv7.tar.gz -C /tmp/kindle-lichess-install
cd /tmp/kindle-lichess-install/kindlelichess.koplugin
sha256sum -c MANIFEST.sha256
'
```

## Gate 3 — cópia do plugin novo

O destino deve continuar inexistente. Como o SSH é fornecido pelo KOReader, ele permanece
aberto durante a cópia e é reiniciado manualmente somente depois de `sync`.

```sh
ssh -p 2222 root@<KINDLE_IP> '
set -eu
target=/mnt/us/koreader/plugins/kindlelichess.koplugin
test ! -e "$target"
cp -R /tmp/kindle-lichess-install/kindlelichess.koplugin "$target"
chmod 0755 "$target/bin/kindle-lichess-bridge"
cd "$target"
sha256sum -c MANIFEST.sha256
sync
'
```

Depois, o usuário abre KOReader e valida o MockBridge. O modo padrão permanece `mock` e
não inicia o executável ARM.

## Gate 4 — ARM nativo sem HTTPS

Usa credencial descartável somente em `/tmp`; nenhum cliente conecta ao socket.

```sh
ssh -p 2222 root@<KINDLE_IP> '
set -eu
umask 077
printf "%s\n" arm-lifecycle-placeholder > /tmp/kindle-lichess-placeholder-token
bridge=/mnt/us/koreader/plugins/kindlelichess.koplugin/bin/kindle-lichess-bridge
socket=/tmp/kindle-lichess-native-test.sock
"$bridge" -socket "$socket" \
    -token-file /tmp/kindle-lichess-placeholder-token \
    -ca-file /mnt/us/koreader/data/ca-bundle.crt &
pid=$!
for attempt in 1 2 3 4 5; do test -S "$socket" && break; sleep 1; done
test -S "$socket"
ps -o pid,rss,vsz,comm -p "$pid"
kill -TERM "$pid"
wait "$pid"
test ! -e "$socket"
rm -f /tmp/kindle-lichess-placeholder-token
'
```

## Gate 5 — token real e modo online

Somente após nova confirmação, o token será transferido para tmpfs sem aparecer em
argumento ou stdout:

```sh
scp -P 2222 /home/hoper/.local/share/kindle-lichess/token \
    root@<KINDLE_IP>:/tmp/kindle-lichess-token
ssh -p 2222 root@<KINDLE_IP> \
    'chmod 0600 /tmp/kindle-lichess-token; test "$(stat -c %a /tmp/kindle-lichess-token)" = 600'
```

O usuário selecionará o modo real na interface. Logs serão aceitos somente após
sanitização por allowlist. O token será removido de `/tmp` ao terminar o teste.

## Reversão

Antes do token real, a reversão remove somente arquivos novos:

Primeiro, o usuário fecha a tela do Kindle Lichess. A reversão se recusa a apagar o
plugin enquanto o bridge ainda estiver em execução:

```sh
ssh -p 2222 root@<KINDLE_IP> '
set -eu
if pidof kindle-lichess-bridge >/dev/null 2>&1; then
    echo "erro: bridge ainda em execução; feche o Kindle Lichess" >&2
    exit 1
fi
rm -f /tmp/kindle-lichess.sock /tmp/kindle-lichess-native-test.sock
rm -f /tmp/kindle-lichess-token /tmp/kindle-lichess-placeholder-token
rm -rf /mnt/us/koreader/plugins/kindlelichess.koplugin
rm -rf /tmp/kindle-lichess-install
rm -f /tmp/kindlelichess-koplugin-armv7.tar.gz
sync
'
```

A remoção do plugin é definitiva, mas todo código pode ser recuperado do tarball/Git.
Nenhum arquivo original do KOReader exige rollback.

## Autorização

Os Gates 1–3 foram autorizados separadamente e executados. Resultados, desvios observados
e correções estão em `docs/phase6-kindle.md`.
