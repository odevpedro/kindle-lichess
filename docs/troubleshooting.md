# Troubleshooting

[Português brasileiro](troubleshooting.pt-BR.md)

This guide applies to the unreleased developer preview. Record the exact error code before
restarting or reinstalling.

## Safe first steps

1. Close Kindle Lichess.
2. Confirm Wi-Fi is enabled when using live mode.
3. Reopen the plugin once.
4. If the error persists, restart KOReader.
5. Export sanitized diagnostics from Tools → Kindle Lichess.
6. Test Mock mode to distinguish UI failures from bridge/network failures.

Do not share the token, token file, Authorization header, raw chat, private PGN, or an
unreviewed crash.log.

## Error reference

| Code | Meaning | Recommended action |
|---|---|---|
| token_missing | The temporary live-mode token does not exist | Developer preview: provision the board:play token again or use Mock mode |
| token_permissions | The bridge rejected unsafe token ownership/type/mode | Ensure the token is a regular file owned by the runtime user with exact mode 0600 |
| token_invalid | The token file is empty or malformed | Revoke if necessary, create a new board:play token, and replace the temporary file |
| auth_unauthorized | Lichess rejected the token | Revoke/recreate the token and confirm it belongs to the intended test account |
| auth_forbidden | The token lacks board:play | Create a token with only the required board:play permission |
| not_found | A challenge or game no longer exists | Return to the lobby and create or accept a new challenge |
| lichess_rejected | Lichess rejected an action | Refresh the game state; the challenge may have expired or the move may no longer apply |
| rate_limited | Lichess requested fewer API calls | Stop retrying, wait at least the indicated delay, then try once |
| network_timeout | Lichess did not answer in time | Check Wi-Fi and try again after the connection stabilizes |
| network_error | DNS, routing, TLS, or connection failed | Verify Wi-Fi and date/time; retry after network recovery |
| http_error | Lichess returned a temporary server error | Wait before retrying; check Lichess service status if the issue continues |
| process_start_failed | KOReader could not start the local ARM bridge | Restart KOReader and verify the installed package is complete |
| socket_unavailable | The bridge did not make its local socket available | Restart KOReader; verify token presence and that the matching ARM bridge is installed |
| socket_in_use | Another process already owns the socket | Close all plugin sessions and restart KOReader |
| unsafe_socket_path | The socket path is not safe to replace | Restart KOReader; do not manually replace the path with a file or symlink |
| bridge_closed | The bridge exited or closed the connection | Reopen the plugin; if repeated, export diagnostics |
| socket_read_failed | Local bridge communication failed while reading | Reopen the plugin and restart KOReader if repeated |
| socket_write_failed | Local bridge communication failed while writing | Reopen the plugin and avoid repeating an uncertain game action |
| ca_file_invalid | KOReader's CA bundle is missing, invalid, or too large | Repair/update the KOReader installation; do not disable TLS verification |
| invalid_json | A local or remote message was malformed | Reopen the plugin and report the sanitized code if reproducible |
| invalid_response | Lichess returned a shape this version does not support | Update the plugin or report the reproducible flow |
| message_too_large | A message exceeded the bridge safety limit | Reopen the plugin and report the exact flow |
| internal | An unexpected internal failure occurred | Restart KOReader, export sanitized diagnostics, and report reproduction steps |

The code in parentheses is intentionally retained for support. The human-readable text is
localized, but the code stays stable across languages.

## Old bridge communication failed message

Older builds could show:

    bridge communication failed (socket_unavailable)

even when the real cause was a missing token. The current build checks for token presence
before starting the subprocess and reports token_missing directly. Other startup failures
may still become socket_unavailable when the child process exits before creating the
socket; use the actions in the table and the sanitized diagnostic export.

## Plugin does not appear

- Confirm the path is koreader/plugins/kindlelichess.koplugin/main.lua.

- Confirm there is no extra kindlelichess.koplugin directory nested inside it.

- Confirm the directory name ends exactly in .koplugin.

- Restart KOReader after copying the plugin.

- Confirm the installed KOReader version matches a tested configuration.

## Dialog appears outside the plugin

Restart KOReader to clear cached Lua modules. Then test challenge username, custom time,
FEN, and chat input.

If the dialog only appears after leaving Kindle Lichess, record:

- which dialog was opened;

- selected language;

- Kindle model;

- KOReader version;

- whether the same failure occurs in Mock mode.

Do not include the typed username, FEN, or chat content unless it is a synthetic test
value.

## Network failures

- Confirm the Kindle can reach the internet.

- Confirm device date and time are reasonable for TLS certificate validation.

- Do not disable TLS or replace the HTTPS URL with HTTP.

- Do not rapidly reopen the plugin after rate_limited.

- If Mock mode works and live mode fails, the UI is probably intact; focus on token,
  network, certificate, and Lichess response codes.

## Challenge failures

- not_found usually means the challenge expired or was canceled.

- auth_forbidden means the token scope is wrong.

- lichess_rejected means Lichess refused the requested action.

- Public search supports Board API-compatible controls; faster controls may be limited to
  direct challenges under Lichess eBoard rules.

See [Lichess eBoard guidance](https://lichess.org/page/eboards).

## PGN export

Expected directory:

    /mnt/us/documents/KindleLichess/

If saving fails:

- confirm the parent documents directory exists;

- confirm free storage is available;

- avoid renaming or removing the storage while KOReader is running;

- preserve the exact error code;

- do not overwrite the original game state or delete another PGN as a workaround.

## Sanitized diagnostics

Use Tools → Kindle Lichess → Export sanitized diagnostics. The file is:

    /mnt/us/documents/KindleLichess/kindle-lichess-diagnostics.txt

Open it before sharing. Its expected keys are format, plugin_version, language,
bridge_mode, last_error, and five contains_* declarations.

If any account, game, position, chat, or token value appears, do not share the file.
Treat that as a security defect and follow [SECURITY.md](../SECURITY.md).

## Reporting a bug

Include:

- Kindle model and firmware;

- KOReader version;

- Kindle Lichess release or commit;

- selected language and bridge mode;

- exact stable error code;

- minimal reproduction steps;

- whether Mock mode reproduces the issue;

- sanitized diagnostic file after review.

Do not post security-sensitive bugs publicly.
