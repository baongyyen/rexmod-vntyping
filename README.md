# rexmod-vntyping

An unofficial, standalone workaround for Vietnamese typing in [Rex](https://rex.superlogical.com).

Some input methods attach Unicode text to a synthetic key event whose keycode means a different character. Rex can use the keycode and garble phrases such as `vui lòng giúp tôi`. This mod forwards the attached text to Rex's text-input responder when the two differ. Physical key events, Cmd/Ctrl shortcuts, function keys, native text views, and marked-text composition stay on Rex's normal path.

## Requirements

- Apple silicon Mac, native `arm64` shell, macOS 15 or later (no Intel or Rosetta)
- Rex at `/Applications/Rex Beta.app`, or an absolute path in `REX_APP`
- Xcode Command Line Tools and `/usr/bin/python3`
- A Vietnamese input method you have already configured

The issue was reproduced on Rex `0.1.0` (build `1696`), and an earlier build of the handler passed a manual check of the phrase above. The standalone distribution has not yet had its own real-keyboard pass. Other Rex versions and input methods are unverified.

## Before you install

- The patch modifies Rex's executable, ad-hoc signs the app, and enables `com.apple.security.cs.disable-library-validation`. The app is no longer vendor-signed, and uninstalling does not restore that signature.
- Vendor updaters may reject the modified app. This project does not download Rex updates or change updater preferences.
- The library path is absolute and tied to the installing user, so use one user per patched app.
- Load only one copy of this handler. Remove any older copy and stop its watcher first.
- Do not run other patchers or updaters on the same bundle at the same time, and do not use `sudo` to get around ownership problems.
- Keep a second terminal open for recovery.

Read [install.sh](install.sh), [patch.sh](patch.sh), and [scripts/dylib-load-command.py](scripts/dylib-load-command.py) before running them.

## Install

Save your work, quit Rex with Cmd+Q, then run one of these from the repository root:

```sh
/bin/sh ./install.sh             # with automatic re-patching
/bin/sh ./install.sh --no-agent  # patch once, and remove any existing agent
```

For a custom location, first run `export REX_APP="/absolute/path/to/Rex Beta.app"`, and keep that value for every later command.

The installer builds and signs the library, copies the runtime files to `~/Library/Application Support/rexmod-vntyping` (`$PREFIX` below), and patches a staged copy of the app before swapping it in.

The default mode also registers the LaunchAgent `dev.rexmod-vntyping.repatch`. It runs at login, when the app's `Info.plist` changes, and every 600 seconds, and it only reapplies the patch. If it fails, check `$PREFIX/agent.log`.

## Verify

```sh
PREFIX="$HOME/Library/Application Support/rexmod-vntyping"
APP="${REX_APP:-/Applications/Rex Beta.app}"
/bin/sh "$PREFIX/patch.sh" --check                # prints "present", exits 0
codesign --verify --strict "$APP"
codesign -d --entitlements - --xml "$APP"         # includes disable-library-validation
launchctl print "gui/$(id -u)/dev.rexmod-vntyping.repatch"  # agent mode only
```

These checks do not prove that typing works. Reopen Rex and, in a disposable pane, type with the input method rather than pasting:

- `vui lòng giúp tôi` in a shell and in an interactive coding prompt
- ASCII text, Backspace/Delete, arrows, Enter, Escape, Cmd/Ctrl shortcuts, and Option characters
- A native text field such as session rename, then cancel

## Uninstall

Save your work and quit Rex, then use the same `REX_APP` as the install:

```sh
PREFIX="$HOME/Library/Application Support/rexmod-vntyping"
/bin/sh "$PREFIX/install.sh" --remove
/bin/sh "$PREFIX/patch.sh" --check   # prints "absent", exits 3 (expected)
```

This stops the agent and removes only this mod's load command. `patch.sh --remove` alone leaves the agent registered, and the agent will patch the app again.

To get a vendor-signed app back, install a fresh official copy of Rex.

After confirming the unpatched app works and no old Rex process still needs these files, you can optionally delete the source, library, logs, and backups:

```sh
rm -rf "$HOME/Library/Application Support/rexmod-vntyping"
```

Do not delete this directory before running `install.sh --remove`.

## Updates and recovery

- **Update Rex:** uninstall, install the official app, verify its signature, reinstall this mod, and repeat the checks above.
- **Update this mod:** run the new checkout's `install.sh` in your chosen mode, then restart Rex.
- **Re-patch after a Rex replacement in `--no-agent` mode:** run `/bin/sh "$HOME/Library/Application Support/rexmod-vntyping/patch.sh"`.
- **Patch exits with `75`:** another patch holds `$PREFIX/.patch.lock`. Wait and retry, and delete the lock only if you are sure no patcher is running.
- **App won't open:** run the uninstall from your second terminal. If that fails, keep the library and backups, and stop the agent before installing a clean Rex so it doesn't patch the new copy.

The patcher keeps backups that are never deleted automatically, so they use disk space:

- `$PREFIX/backup/Rex Beta.app` is a one-time snapshot from before the first patch. It may be outdated or already modified, so don't treat it as a clean vendor copy.
- `$PREFIX/replaced/swap.*/Rex Beta.app` holds the bundle displaced by each successful patch.

## Diagnostics

Logging is off by default. **The log can contain typed text**, so don't type credentials while it is on, and redact it before sharing.

```sh
touch "$HOME/Library/Application Support/rexmod-vntyping/debug"      # enable
rm -f "$HOME/Library/Application Support/rexmod-vntyping/debug"      # disable
```

Restart Rex after either command, because the flag is read when the library loads. Output goes to `$PREFIX/debug.log`.

## Development

- [src/RexVietnameseInput.m](src/RexVietnameseInput.m): AppKit event handling and diagnostics
- [install.sh](install.sh): build, file staging, and LaunchAgent lifecycle
- [patch.sh](patch.sh): locking, staged app replacement, signing, and backups
- [scripts/dylib-load-command.py](scripts/dylib-load-command.py): arm64 Mach-O load-command editing
- [tests/test-standalone-install.py](tests/test-standalone-install.py): isolated integration tests

```sh
/bin/sh -n install.sh && /bin/sh -n patch.sh
/usr/bin/python3 -I tests/test-standalone-install.py -v
```

The tests use real Mach-O fixtures with an isolated home and app path. They do not register a live LaunchAgent, patch your installed Rex, or check real keyboard behavior.

Publish source only: no app bundles, compiled libraries, diagnostics, agent plists, or snapshots.

## License

[MIT](LICENSE)
