# NScroll

Reverse mouse scrolling direction on macOS.

NScroll inverts scroll events from discrete scroll wheels only. Trackpads and the Magic Mouse report continuous deltas and are left untouched, so they keep following the system "Natural scrolling" preference — set that however you like, and NScroll fixes the mouse independently.

Requires macOS 11 or later and the Xcode Command Line Tools.

## Install

```bash
make && sudo make install
```

Installs `nscroll` to `/usr/local/bin`. To avoid `sudo`, use a prefix you own: `make install PREFIX=$HOME/.local`.

## Run it at login

```bash
nscroll enable
```

Writes `~/Library/LaunchAgents/com.nscroll.agent.plist` and loads it. Don't use `sudo` — the agent is per-user, and `enable` will refuse.

macOS won't let the event tap start until you grant Accessibility permission to `/usr/local/bin/nscroll` under System Settings → Privacy & Security → Accessibility. The agent retries every 10 seconds, so it begins working as soon as you tick the box. Check with `nscroll status`.

## Commands

|                   |                                                          |
| ----------------- | -------------------------------------------------------- |
| `nscroll run`     | invert scrolling in the foreground until interrupted     |
| `nscroll enable`  | install and start the launch agent                       |
| `nscroll disable` | stop and remove the launch agent                         |
| `nscroll restart` | restart the launch agent, after reinstalling the binary  |
| `nscroll status`  | report whether the launch agent is installed and running |
| `nscroll help`    | also `-h`, `--help`                                      |
| `nscroll version` | also `-V`, `--version`                                   |

No flags and no configuration file. `nscroll status` exits 0 when the agent is running, 3 when it's installed but not running, and 4 when it isn't installed.

The agent commands have `make` targets too: `make enable`, `make disable`, `make restart`, `make status`.

## Two things that will bite you

**Rebuilding revokes the Accessibility grant.** macOS keys the permission to the binary's code signature, and the default ad-hoc signature changes on every build. To make the grant stick, create a self-signed code-signing certificate in Keychain Access and install with `make install SIGN_ID="NScroll Dev"`.

**Moving the binary breaks the agent.** The plist records an absolute path, so run `nscroll enable` again after installing to a different prefix.

After a rebuild: `sudo make install && make restart`.

## Configuration

None, by design. NScroll inverts the vertical axis for discrete wheels and that's the whole feature. To also invert horizontal scrolling, edit `axes` in [`Sources/ScrollInverter.swift`](Sources/ScrollInverter.swift) and rebuild.

## License

MIT — see [LICENSE](LICENSE).
