# Security policy

## Supported versions

Kindle Lichess is currently an unreleased developer preview. Until versioned releases
exist, only the current main branch is eligible for security fixes. Installed snapshots
and older development packages may contain already-fixed logging or credential-handling
defects.

This policy will be updated with a supported-version table before the first public release.

## Reporting a vulnerability

Do not open a public issue for a vulnerability involving credentials, account data,
private chat, game identifiers, arbitrary code execution, unsafe file access, or network
security.

Preferred reporting order:

1. Use GitHub private vulnerability reporting for this repository if the Security tab
   offers that option.
2. Otherwise email the maintainer at pedrosschmidt2@gmail.com with the subject
   “Kindle Lichess security report”.

Include only the minimum information required to reproduce the issue. If a token may have
been exposed, revoke it first and do not attach it to the report.

The project is maintained independently and does not promise a formal response SLA. A
report should be acknowledged, reproduced, risk-assessed, fixed, and disclosed only after
a safe upgrade path exists.

## Sensitive data

Never send:

- a Lichess token or Authorization header;

- the token file;

- a raw memory dump;

- a private key;

- an unreviewed KOReader crash.log;

- private chat unrelated to the defect;

- full account/game data when synthetic values reproduce the issue.

The preferred attachment is the sanitized diagnostic file generated from
Tools → Kindle Lichess → Export sanitized diagnostics. Review it before sending.

## If a token was exposed

1. Stop using the affected token.
2. Revoke it at [Lichess API tokens](https://lichess.org/account/oauth/token).
3. Remove the temporary copy from the Kindle.
4. Search screenshots, logs, shell history, issue drafts, and shared files for copies.
5. Create a replacement only after identifying the exposure path.
6. Grant only board:play for the current developer preview.

Lichess documents that tokens must remain secret and that compromised tokens should be
revoked:
[official API specification](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml).

## Security boundaries

Production behavior is intended to be limited to:

- the installed kindlelichess.koplugin directory;

- exported PGN and sanitized diagnostics under /mnt/us/documents/KindleLichess;

- non-secret KOReader settings;

- temporary token and Unix socket under /tmp;

- HTTPS communication with https://lichess.org.

The plugin must not modify the Kindle root filesystem, firmware, boot process, Amazon
services, KOReader core files, firewall, SSH configuration, or unrelated user documents.

## Credential model

The current personal-token flow is development-only. It is not acceptable onboarding for
a general public release. The planned public flow is OAuth Authorization Code with PKCE
and minimum board:play access.

The current bridge:

- reads the token directly from a regular 0600 file;

- does not send token contents to Lua;

- forbids token/authorization fields in IPC;

- avoids token content and path in errors;

- sends authorization only to the allowed Lichess origin;

- refuses to weaken TLS validation.

## Logging and diagnostics

Production logs use allowlisted codes. Rejected stream events log only a known event type
and known reason code. Raw payloads, error text, account names, game IDs, positions, and
chat are excluded.

The sanitized diagnostic exporter accepts only recognized language, bridge mode, and
error-code values. Unknown input becomes unknown.

Older development builds may have logged up to part of a rejected Lichess payload. Treat
old crash logs as potentially private.

## Fair play

The online package contains no engine, UCI integration, evaluation, explorer, tablebase,
or move suggestions. Security reports should flag any accidental inclusion or execution
of such functionality.

Online play must use the official Board API:

- [Lichess eBoard guidance](https://lichess.org/page/eboards)

- [Lichess fair-play rules](https://lichess.org/page/fair-play)

## Coordinated disclosure

Please allow time to reproduce and prepare a fixed package before public disclosure.
Credit will be offered unless the reporter prefers anonymity. The final advisory should
describe affected versions, impact, remediation, token-revocation need, and whether old
logs or artifacts require cleanup.
