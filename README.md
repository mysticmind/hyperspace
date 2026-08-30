# hyperspace

An Omarchy-style tiling setup for macOS: **AeroSpace** for tiling, **Caps Lock as
Super**, and a workspace indicator that lives *in* the native menu bar instead of
replacing it.

Zero gaps, edge to edge, with a thin ring on the focused window.

```
┌─────────────────────┬─────────────────────┐
│                     │                     │   Super      = Caps Lock (⌘⌃⌥)
│      Alacritty      │       Firefox       │   gaps       = 0
│      720 x 899      │      720 x 899      │   ring       = 2pt, focused only
│                     │                     │   menu bar   = auto-hide
└─────────────────────┴─────────────────────┘
```

## What it is

| Piece | Role |
|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | tiling window manager |
| [Karabiner-Elements](https://karabiner-elements.pqrs.org/) | Caps Lock → Super (⌘⌃⌥) |
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | workspace pills as a native menu bar item |
| [Ice](https://github.com/jordanbaird/Ice) | menu bar overflow management |
| [JankyBorders](https://github.com/FelixKratz/JankyBorders) | ring around the focused window |

No custom daemons. No focus-follows-mouse shim, no gesture capture, no private
APIs. Everything here is a config file for a tool someone else maintains.

## Install

```sh
git clone <this repo> ~/oss_contrib/hyperspace
cd ~/oss_contrib/hyperspace
./install.sh
```

Then grant Accessibility to AeroSpace and Karabiner when macOS asks. That is
the only manual step — everything starts at login on its own.

## Uninstall

```sh
./uninstall.sh
```

It restores every file it displaced and every `defaults` key it changed, using
values recorded at install time. **It does not uninstall Homebrew packages** —
it prints the commands and lets you decide.

## Your terminal's title bar

Under a tiler the traffic lights are dead weight. This repo does not touch your
terminal config (rule 1), so set it yourself:

```toml
# ~/.config/alacritty/alacritty.toml
[window]
decorations = "none"       # no title bar at all
# "buttonless" keeps the bar and only drops the buttons
```

```
# ~/.config/ghostty/config
window-decoration = false
```

Decoration changes apply to **new** windows, not ones already open. Apps that
are not terminals (Firefox, and so on) give you no such setting — macOS has no
global switch for window controls.

## Keybindings

`Super` = Caps Lock = ⌘⌃⌥. `Super+Shift` is the second layer.

### Windows
| Key | Action |
|---|---|
| `Super+Return` | terminal |
| `Super+Shift+Return` | browser |
| `Super+Space` | Raycast |
| `Super+W` | close window |
| `Super+←↓↑→` / `Super+hjkl` | focus |
| `Super+Shift+←↓↑→` / `Super+Shift+hjkl` | move window |
| `Alt+Tab` / `Alt+Shift+Tab` | cycle windows within the workspace |

### Layout
| Key | Action |
|---|---|
| `Super+T` | float ⇄ tile |
| `Super+E` | flip split orientation |
| `Super+A` | accordion ⇄ tiles |
| `Super+F` | fullscreen (no gaps) |
| `Super+N` | macOS native fullscreen |
| `Super+-` / `Super+=` | resize |
| `Super+,` | balance sizes |
| `Super+R` | resize mode (`hjkl`, `Esc` to exit) |

### Workspaces
| Key | Action |
|---|---|
| `Super+1..9` | go to workspace |
| `Super+Shift+1..9` | send window to workspace |
| `Super+Tab` / `Super+Shift+Tab` | next / previous workspace |
| `Super+B` | back and forth |
| `Ctrl+Alt+Tab` | focus next monitor |
| `Super+Shift+O` | throw window to next monitor |
| `Super+Shift+Space` | move whole workspace to next monitor |

### Apps and system
| Key | Action |
|---|---|
| `Super+Shift+F` | Finder (home) |
| `Super+Shift+M` | Spotify |
| `Super+Shift+G` | Slack |
| `Super+Esc` | lock screen |
| `Super+Shift+;` | service mode (`Esc` reload · `R` reset layout · `F` float · `⌫` close others) |

## Gotchas worth knowing

These were all found by measuring, not by reading docs. They cost real time.

**Windows cannot use the menu bar strip while the menu bar is visible.**
macOS clamps them out of it. A negative `outer.top` gap makes AeroSpace *ask*
for the space, and macOS grants it to some windows and not others, producing an
inconsistent layout:

```
Alacritty  y=0   h=891   ← honored
Alacritty  y=30  h=870   ← clamped back, pushed 8pt off-screen
```

Auto-hiding the menu bar is the only mechanism that works: macOS then reports
`visibleFrame` as the full display height. That is why `install.sh` sets
`_HIHideMenuBar`. The cost is that SwiftBar's pills only appear on hover.

**Changing menu bar or Dock visibility needs an AeroSpace *restart*.**
`reload-config` is not enough — AeroSpace does not recompute screen geometry
when the visible frame changes, and you get windows sized for the old frame.

**AeroSpace's TOML rejects duplicate keys** with the unhelpful message
`Ill-formed key`. If a binding is defined twice — easy when you have both
arrow and `hjkl` bindings — that is what you will see. The line number it
reports is the *second* definition.

**Karabiner can read a new config without applying it.** The tell is in
`~/.local/share/karabiner/log/console_user_server.log`: a `Load ...karabiner.json`
line with no `core_configuration is updated` after it, usually alongside
`core_service_daemon_client connect_failed: Permission denied`. Every remap
silently does nothing — Caps Lock stops being Super and every binding looks
broken, while the config file on disk is perfectly correct. Fix:

```sh
launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.Karabiner-Core-Service-rev2"
launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.Karabiner-Console-User-Server"
```

`install.sh` does this after writing the rule, and warns if the log still does
not show the config applied.

**To tell a dead keybinding from a dead command**, run the command directly and
then fire the binding by name:

```sh
aerospace layout horizontal vertical              # is the command broken?
aerospace config --get mode.main.binding --keys   # is the binding registered?
aerospace trigger-binding --mode main cmd-ctrl-alt-e   # does the binding work?
```

If all three succeed but the physical chord does nothing, the problem is key
delivery — Karabiner or a conflicting global hotkey — not AeroSpace.

**The key is named `esc`, not `escape`.**

**`'''triple-quoted'''` TOML strings** are not parsed; use single quotes and
avoid command paths containing spaces.

## Design rules

Written down because the setup this replaced broke every one of them:

1. **Never touch shell config.** This is not a dotfiles manager. `~/.zshrc` is
   yours.
2. **Never uninstall Homebrew packages on teardown**, even ones the installer
   added. Print the commands; let the human decide.
3. **Back up what you displace, and record it**, so uninstall restores exactly
   that rather than guessing at defaults.
4. **Symlink files, not directories**, so other tools sharing a config
   directory keep working.
5. **Merge into the user's Karabiner config, never replace it.** `bin/karabiner-rule`
   adds one rule and removes one, leaving every other rule intact.
6. **A LaunchAgent may launch an app; it may not be a daemon.** The two agents
   here are `RunAtLoad` only, with no `KeepAlive` and nothing resident, and
   they exist solely because `SMAppService` is unreachable from a shell.

## Layout

```
Brewfile                          dependencies
install.sh / uninstall.sh         symmetric, manifest-driven
bin/karabiner-rule                surgical add/remove of the Caps→Super rule
bin/login-agent                   launch-at-login for SwiftBar and Ice
bin/doctor                        diagnose the three layers when a chord does nothing
config/aerospace/aerospace.toml   the window manager
config/swiftbar/aerospace.10s.sh  menu bar plugin: pills, switcher, cheatsheet
config/borders/bordersrc          focused-window ring
config/karabiner/caps-to-super.json   the one rule, as a snippet
```

State lives in `~/.local/state/hyperspace/`.
