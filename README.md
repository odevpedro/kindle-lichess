# Kindle Lichess

[Português brasileiro](README.pt-BR.md)

Kindle Lichess is an independent, open-source KOReader plugin for playing human chess
games on Lichess from an e-ink screen.

> **Unreleased developer preview.** This repository is not ready for a general public
> release. Live-account authentication still requires a manually provisioned temporary
> token and SSH access. The supported public login flow is being designed.

Kindle Lichess is not affiliated with or endorsed by Lichess, KOReader, or Amazon.

## Current compatibility

The complete device validation has been performed on:

- Kindle Basic 10th generation, also known as KT4/KindleHF;

- KOReader 2026.03;

- ARMv7 hard-float bridge included in the package.

Other Kindle models and KOReader versions are currently untested. Do not assume that a
device is supported only because it can load KOReader.

KOReader classifies independently developed plugins as external plugins: they are
installed and updated manually and are not reviewed by the KOReader developers. See the
[official KOReader user guide](https://koreader.rocks/user_guide/).

## Features

- Casual human games through the official Lichess Board API.

- Incoming and outgoing challenges.

- Public opponent search using Board API-compatible time controls.

- Custom time controls.

- Legal move validation, promotion, castling, and en passant.

- Clocks, reconnect handling, and server-authoritative game state.

- Captured pieces and material advantage.

- Previous/next move review during and after a game.

- PGN export after the game.

- Private player-to-player game chat, kept only in memory.

- Free board editor with FEN import.

- English and Brazilian Portuguese interface.

- Sanitized diagnostic export.

The online build contains no chess engine, evaluation, opening explorer, tablebase, or
move recommendation feature.

## Fair play

Online play uses the official Board API with the minimum board:play permission. Lichess
states that third-party boards must use this API, and its fair-play rules prohibit engine
or other external assistance during real-time games:

- [Lichess eBoard guidance](https://lichess.org/page/eboards)

- [Lichess fair-play rules](https://lichess.org/page/fair-play)

The initial release scope is casual games. Do not use Kindle Lichess together with an
engine, opening book, tablebase, or another source of move advice.

## Installation

There is no supported public release artifact yet. For local development builds:

1. Build and package the project with the commands in [Development](#development).
2. Extract dist/kindlelichess-koplugin-armv7.tar.gz on your computer.
3. Connect the Kindle by USB.
4. Copy the complete kindlelichess.koplugin directory to koreader/plugins on the Kindle.
5. Safely eject the Kindle and restart KOReader.
6. Open Tools → Kindle Lichess.

Do not copy only individual files from the package. The directory includes a manifest,
the Lua interface, assets, and the matching ARM bridge.

Detailed installation, update, rollback, and removal instructions are in
[docs/installation.md](docs/installation.md).

## Authentication status

Mock mode works without a Lichess account.

Live mode is currently restricted to development testing. It requires a personal token
with only the board:play permission, stored temporarily as
/tmp/kindle-lichess-token with mode 0600. This file is intentionally not persisted on
/mnt/us because that filesystem does not enforce private Unix permissions.

This manual token flow is not suitable for a general public application. Lichess
recommends personal tokens only for personal or small, technically experienced use and
recommends OAuth Authorization Code with PKCE for public client applications:

- [Official Lichess authentication guidance](https://github.com/lichess-org/api/blob/master/example/README.md)

- [Official Lichess API specification](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml)

Never post a token in an issue, log, screenshot, forum, or chat. Revoke a compromised
token immediately at [Lichess API tokens](https://lichess.org/account/oauth/token).

## Language

Open Tools → Kindle Lichess → Language and select:

- Automatic (KOReader);

- English;

- Portuguese (Brazil).

Automatic mode follows the KOReader language when Brazilian Portuguese is selected and
falls back to English for unsupported locales.

Restart KOReader after updating the plugin so that all translated modules are reloaded.

## PGN files

Finished games can be saved from the result screen. By default, files are written to:

    /mnt/us/documents/KindleLichess/

PGNs may contain player names, ratings, timestamps, moves, and the Lichess game URL.
They are user documents and are not uploaded by Kindle Lichess.

## Privacy and diagnostics

Kindle Lichess has no project-owned telemetry or analytics. Network traffic in live mode
goes to https://lichess.org. The Lua interface communicates with the local bridge over a
private Unix socket.

The diagnostic export contains only a fixed allowlist: format version, unreleased plugin
version, selected language, bridge mode, and last internal error code. It excludes account
names, game IDs, chat, positions, PGNs, and tokens.

Use Tools → Kindle Lichess → Export sanitized diagnostics. The file is written to:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

Read the complete [privacy notice](docs/privacy.md) before sharing device information.

## Troubleshooting

Common failures such as token_missing, auth_forbidden, network_error,
rate_limited, and socket_unavailable now have separate, actionable messages.

See [docs/troubleshooting.md](docs/troubleshooting.md). Never attach the token file or an
unreviewed KOReader crash.log to a public issue.

## Update and rollback

Before updating, close Kindle Lichess and keep a copy of the installed
kindlelichess.koplugin directory. Replace the entire directory with the directory from the
new release and restart KOReader.

PGNs are outside the plugin directory. KOReader settings are also stored separately.
Rollback consists of closing the plugin, restoring the backed-up plugin directory, and
restarting KOReader.

## Known limitations

- Public OAuth login is not implemented.

- Live mode currently requires SSH and an ephemeral personal token.

- Only the KT4/KindleHF with KOReader 2026.03 has completed device validation.

- The host KOReader integration suite requires a compiled KOReader source tree and may be
  skipped when KOREADER_SOURCE is not configured.

- Chat history begins when the game stream is opened; older messages are not fetched.

- Only standard chess is supported.

- The first release scope is casual games.

- Automatic updates are not implemented.

## Development

Run Lua tests:

    ./scripts/test.sh

Run the KOReader integration suite by providing an already compiled KOReader tree:

    KOREADER_SOURCE=/absolute/path/to/koreader ./scripts/test.sh

Run Go formatting, vet, tests, and race checks in the pinned toolchain:

    ./scripts/test-go.sh

Build and verify the ARM bridge:

    ./scripts/build-armv7.sh
    ./scripts/verify-binary.sh

Create the distributable archive:

    ./scripts/package.sh

The package script includes no real token, local logs, saved games, or private planning
documents.

## Security

Please read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Do not open a
public issue containing a token, private chat, account identifier, game identifier, or
raw device log.

## Project documentation

- [Architecture](docs/architecture.md)

- [Lichess API contract](docs/lichess-api.md)

- [Security design](docs/security.md)

- [Test plan](docs/test-plan.md)

- [Licensing and provenance](docs/licensing.md)

- [Development backlog](docs/mvp-backlog.md)

## License

Project-owned code is licensed under GPL-3.0-or-later. See [LICENSE](LICENSE),
[NOTICE](NOTICE), and [docs/licensing.md](docs/licensing.md).

Maintainer: [odevpedro](https://github.com/odevpedro).
