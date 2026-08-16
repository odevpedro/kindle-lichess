# Installation, update, rollback, and removal

[Português brasileiro](installation.pt-BR.md)

## Release status

Kindle Lichess is currently an unreleased developer preview. These instructions document
the intended package layout and the procedure already used on the tested KT4. They do not
turn the current build into a supported public release.

Live-account authentication is not ready for general users because it still requires an
ephemeral token provisioned through SSH. Mock mode does not require a token.

## Requirements

- A Kindle on which KOReader is already installed and working.

- Enough free space for the plugin and its approximately 6 MiB static ARM bridge.

- A complete Kindle Lichess package produced by the repository packaging script.

- A computer capable of extracting a tar.gz archive and copying files over USB.

The only fully validated configuration is Kindle Basic 10th generation
KT4/KindleHF with KOReader 2026.03. The included bridge targets ARMv7 hard-float.

Kindle jailbreak and KOReader installation are outside this project's scope. Follow the
documentation appropriate to the exact Kindle model and firmware; do not use instructions
written for a different device.

## Verify the package

For a future GitHub release, download the archive and the published SHA256SUMS file from
the same release. Compare the archive checksum before extracting it.

For a local build, run:

    ./scripts/build-armv7.sh
    ./scripts/verify-binary.sh
    ./scripts/package.sh

The generated archive is:

    dist/kindlelichess-koplugin-armv7.tar.gz

After extraction, the top-level directory must be exactly:

    kindlelichess.koplugin

It must contain MANIFEST.sha256, main.lua, controller.lua, i18n.lua,
bin/kindle-lichess-bridge, and the bridge, chess, icons, storage, and ui directories.

## Clean installation over USB

1. Close Kindle Lichess if it is open.
2. Connect the Kindle to the computer by USB.
3. Extract the package on the computer.
4. Open the koreader/plugins directory on the Kindle storage.
5. Copy the complete kindlelichess.koplugin directory into koreader/plugins.
6. Confirm that the result is koreader/plugins/kindlelichess.koplugin/main.lua, not a
   duplicated nested directory.
7. Safely eject the Kindle.
8. Restart KOReader.
9. Open Tools → Kindle Lichess.

Do not place the archive itself in koreader/plugins. Do not merge files from different
versions.

KOReader documents that external plugins are manually installed, manually updated, and
not reviewed by the KOReader developers:
[KOReader user guide](https://koreader.rocks/user_guide/).

## First run

Start with Mock mode:

1. Open Tools → Kindle Lichess.
2. Select Mock mode.
3. Open Kindle Lichess.
4. Accept the simulated challenge.
5. Confirm that the board, clocks, actions, chat, and result screen render correctly.

Select the desired language under Tools → Kindle Lichess → Language. Automatic follows a
Brazilian Portuguese KOReader locale and otherwise falls back to English.

## Live-account developer mode

Live mode is not a supported public onboarding flow. It currently expects a personal
Lichess token with only board:play access at:

    /tmp/kindle-lichess-token

The file must be a regular file owned by the runtime user with mode 0600. It is temporary
and may disappear after a restart.

Never store the plaintext token under /mnt/us. Never put it in the plugin directory, a
PGN, a diagnostic file, a shell history, an issue, or the Git repository.

The official Lichess authentication guidance says personal tokens are intended for
personal or small technically experienced use, not a general multi-user app. Public
distribution remains blocked until the OAuth PKCE flow is implemented:
[Lichess authentication guidance](https://github.com/lichess-org/api/blob/master/example/README.md).

## Update

1. Read the release notes and compatibility statement.
2. Close Kindle Lichess.
3. Connect the Kindle by USB.
4. Rename the installed directory to a backup name that does not end in .koplugin, for
   example kindlelichess.koplugin.rollback.
5. Copy the complete new kindlelichess.koplugin directory into koreader/plugins.
6. Safely eject the Kindle.
7. Restart KOReader.
8. Test Mock mode before using a live account.
9. Keep the rollback directory until the new version has completed at least one full
   smoke test.

Do not overwrite individual Lua files while Kindle Lichess is open. KOReader caches
loaded modules, so a mixture of old memory and new files can produce misleading failures.

## Data preserved during update

Replacing only the plugin directory does not remove:

- PGNs under /mnt/us/documents/KindleLichess;

- the sanitized diagnostic file in that directory;

- KOReader settings stored outside the plugin;

- a temporary token in /tmp, while the current system session keeps that file.

The temporary token may still disappear after restarting the device. That behavior is
expected in the developer preview.

## Rollback

1. Close Kindle Lichess.
2. Connect the Kindle by USB.
3. Move the failing kindlelichess.koplugin directory out of koreader/plugins.
4. Rename the saved rollback directory back to kindlelichess.koplugin.
5. Safely eject the Kindle.
6. Restart KOReader.
7. Test Mock mode.

If no rollback copy exists, install a previously downloaded, checksum-verified release
package. Do not combine files from two releases.

## Removal

1. Close Kindle Lichess.
2. Restart KOReader if the bridge did not exit cleanly.
3. Connect the Kindle by USB.
4. Move or delete only koreader/plugins/kindlelichess.koplugin.
5. Restart KOReader.

Optional user data can be removed separately:

- /mnt/us/documents/KindleLichess contains exported PGNs and sanitized diagnostics;

- Kindle Lichess preferences remain in KOReader's settings.

Review PGNs before deleting them. They are user documents and cannot be reconstructed by
the plugin after removal.

## Installation smoke test

After every clean installation or update, verify:

- Kindle Lichess appears under Tools;

- the language selector works;

- Mock mode opens and closes without leaving a window behind;

- challenge input, custom time, FEN, and chat dialogs appear inside the plugin;

- a simulated game reaches the result screen;

- move history navigation works;

- PGN export creates a readable file;

- sanitized diagnostic export contains no account, game, chat, position, or token data;

- closing the plugin removes the local bridge process and socket.

## Recovery

If the plugin does not appear, verify the directory nesting and restart KOReader.

If the plugin opens but reports a bridge error, use
[troubleshooting.md](troubleshooting.md). Do not repeatedly reinstall before recording
the exact error code and the installed version.
