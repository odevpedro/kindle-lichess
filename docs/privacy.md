# Privacy notice

[Português brasileiro](privacy.pt-BR.md)

Last updated: 2026-08-15.

This notice describes the current unreleased developer preview. Review it again before a
public release because the planned OAuth login may change credential handling.

## Summary

Kindle Lichess has no project-owned telemetry, analytics service, advertising, or remote
logging endpoint.

In live mode, the bridge communicates with https://lichess.org to authenticate the
account, receive challenges and games, submit user actions, and exchange in-game chat.
Inside the Kindle, the Lua plugin communicates with the bridge through a private Unix
socket.

## Data processed in memory

The plugin may temporarily hold:

- Lichess account ID and username;

- opponent username and rating;

- challenge and game identifiers;

- board position, move history, clocks, and result;

- private player-room chat received while the game stream is open;

- the last internal error code.

This data is required to render and control the active session. Account, game, position,
and chat data are not included in the sanitized diagnostic export.

## Credentials

The current developer-preview flow reads a personal Lichess token from:

    /tmp/kindle-lichess-token

The Go bridge, not the Lua UI, reads the token. The file must have mode 0600. The token is
not sent through the plugin's JSON protocol, printed in errors, included in the package,
or written to PGN/diagnostics.

The token is sent only as HTTPS authorization to https://lichess.org. Authorization is
not forwarded to another host after a redirect.

The token is intentionally not persisted under /mnt/us because that filesystem cannot
enforce the required private Unix permissions. A system restart may remove it.

The public release requires a separate OAuth PKCE design. The current token mechanism
must not be presented as public onboarding.

## Network destinations

Production live mode permits:

- HTTPS requests and streams to https://lichess.org;

- a local Unix socket at /tmp/kindle-lichess.sock.

The project does not operate an analytics, relay, advertising, or crash-report server.
Test builds may use an explicitly configured local fake server; that test configuration
is not part of the production package.

## Chat

Only the private player room is exposed. Spectator chat is discarded.

Up to 40 recent chat messages are held in memory for the current game. They are not added
to PGN, settings, diagnostics, or project logs. Chat history from before the game stream
opened is not fetched. Malformed chat is discarded without logging its contents.

Lichess receives and processes chat under its own policies.

## PGN files

When the user selects Save PGN, Kindle Lichess writes a user document under:

    /mnt/us/documents/KindleLichess/

A PGN can contain player names, ratings, date, complete move history, result, initial FEN
for a custom starting position, and the public Lichess game URL. It remains on the Kindle
until the user moves or deletes it.

Kindle Lichess does not upload an exported PGN.

## Settings

KOReader settings may persist:

- bridge mode;

- language choice;

- selected time control;

- configured non-secret file locations;

- last allowlisted internal error code.

The settings must not contain a token, account name, game ID, chat message, or position.

## Sanitized diagnostics

The user can create:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

The file is generated from a strict allowlist and contains:

- diagnostic format version;

- plugin version label;

- language;

- bridge mode;

- last recognized internal error code;

- explicit statements that account, game ID, chat, position, and token are absent.

Unknown values are replaced with unknown rather than copied into the file. The export
never reads the token, PGNs, chat transcript, current position, or KOReader crash log.

Review the file before sharing it anyway.

## Logs

The bridge writes only bounded, allowlisted operational codes to stderr. A rejected
Lichess event is represented by a known event type and a known error code. Raw JSON,
usernames, game IDs, positions, chat, and raw error text are not logged.

Older development builds logged part of a rejected stream payload. A crash.log created by
an older build may therefore contain account or game information. Do not publish an old
or unreviewed crash.log. The sanitized diagnostic file is the preferred support artifact.

## Retention and deletion

- In-memory session and chat data disappear when the plugin process/session ends.

- The temporary token may disappear on restart and can be explicitly removed by the
  developer who provisioned it.

- PGNs and sanitized diagnostics remain until the user removes them.

- KOReader settings remain until removed through KOReader or its settings storage.

- Removing the plugin directory does not automatically delete PGNs.

## Sharing bug reports

Safe by default:

- the sanitized diagnostic file after personal review;

- exact error code;

- Kindle model, firmware version, KOReader version, and plugin release.

Do not share:

- token or token file;

- Authorization header;

- raw crash.log without line-by-line review;

- private chat;

- account or game identifiers unless consciously required and redacted where possible;

- PGN from a private game without consent.

For vulnerabilities, follow [SECURITY.md](../SECURITY.md).

## Third parties

Lichess and KOReader are independent projects with their own policies. Kindle Lichess is
not affiliated with Lichess, KOReader, or Amazon.

Relevant official references:

- [Lichess API token security and OAuth](https://github.com/lichess-org/api/blob/master/doc/specs/lichess-api.yaml)

- [Lichess authentication guidance](https://github.com/lichess-org/api/blob/master/example/README.md)

- [KOReader external plugin guidance](https://koreader.rocks/user_guide/)
