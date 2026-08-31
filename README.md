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
| [JankyBorders](https://github.com/FelixKratz/JankyBorders) | ring around the focused window |

No custom daemons. No focus-follows-mouse shim, no gesture capture, no private
APIs. Everything here is a config file for a tool someone else maintains.

### Why there is no menu bar overflow manager

Earlier versions used [Ice](https://github.com/jordanbaird/Ice) to hide menu bar
overflow. It is gone, because it and hyperspace want opposite things.

hyperspace auto-hides the menu bar so AeroSpace can reclaim the 30pt strip — the
bar is off screen most of the time, which leaves an overflow manager very little
to manage. Meanwhile Ice on macOS 26 struggles with exactly the items that end
up hidden here: on this setup all fourteen were Control Centre items (Wi-Fi,
Bluetooth, Sound, Battery), which macOS vends from a single process. Ice cannot
resolve an owning PID for them —

```
MenuBarItemManager  Missing sourcePID for <…:Item-0 (windowID: 148)>
MenuBarItemManager  Clearing cached menu bar item windowIDs
```

— so it cannot forward a click to them, and it invalidates its cache twice a
second trying. Clicking a hidden item in the Ice Bar did nothing; letting Ice
expand items into the real menu bar instead ran into its "smart" auto-rehide,
which fires as soon as the auto-hidden bar drops. Two settings pulling against
each other, for a feature worth little once the bar is hidden anyway.

For the record, on the crash that came first: the `jordanbaird-ice` cask is
stable 0.11.12, built October 2024, and it traps ~0.7s into every launch on
macOS 26. Upstream's `0.11.13-dev.2` prerelease fixes that much. If you want Ice
back, install it yourself — hyperspace no longer has an opinion about it.

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

## The cheatsheet — `Super+K`

A floating window listing every binding. Press `Super+K` again to close it.

It is **generated from `aerospace.toml` at the moment you press the key**, by
parsing the live config — so it cannot drift from the keys it documents, and
any binding a plugin adds appears in it for free. A trailing comment on a
binding becomes its description:

```toml
cmd-ctrl-alt-w = 'close'   # close window
```

The window is an ordinary Alacritty window with a known title. Three things
place it, all of them settings on that window rather than machinery of ours: an
`on-window-detected` rule floats it, Alacritty's own `window.level` pins it
above other windows, and `bin/cheatsheet-toggle` centres it from the sheet's
measured size. The toggle is just "does a window with that title exist" —
nothing resident, no helper process.

Centring is arithmetic, not a query: nothing can ask a window where it will
land before it opens. `bin/cheatsheet-toggle` predicts the size from the glyph
metrics of JetBrains Mono at 14 — `8.0` per column, `18.5` per line, plus
Alacritty's `window.padding` on *each* side — and halves the remaining screen.
Change the font or its size and those constants are wrong; `HYPERSPACE_SCALE`
and `HYPERSPACE_Y_OFFSET` are there to correct it without editing the script.
Get the size wrong by enough and the window is placed off screen, at which
point macOS clamps it against an edge — which looks like bad centring but is
not.

## Plugins

A plugin is a directory under `plugins/`:

```
plugins/<name>/
  plugin.toml        name + description                          (required)
  bindings.toml      [mode.main.binding] lines to splice in      (optional)
  window-rules.toml  [[on-window-detected]] blocks               (optional)
  swiftbar/          menu bar plugins, linked into ~/.config/swiftbar
                     (only put plugins here — SwiftBar RUNS every file in
                     that directory; helper scripts belong in the plugin root)
  install.sh         run on enable                               (optional)
  uninstall.sh       run on disable                              (optional)
```

A plugin can reach past AeroSpace: the `dictation` plugin ships
`karabiner-rules.json` and uses its `install.sh` hook to merge those rules
into your Karabiner config through `bin/karabiner-rule`, which is why the
plugin model needs hooks at all.

```sh
hyperspace-plugin list
hyperspace-plugin enable volume screenshot
hyperspace-plugin disable volume
```

**Nothing is enabled implicitly.** Dropping a directory into `plugins/` does
nothing until you enable it, so a `git pull` can never silently rebind your
keyboard.

### How it works

`aerospace.toml` is **generated** — edit `aerospace.base.toml` instead. The
base carries two markers, and `bin/build-config` splices enabled plugins in:

```
# @plugin-window-rules@   <- [[on-window-detected]] blocks land here
# @plugin-bindings@       <- binding lines land here, inside [mode.main.binding]
```

Inside a plugin's own files, `@PLUGIN_DIR@` is substituted with that plugin's
directory, so a plugin can call its own helper scripts without hardcoding
where the repo was cloned:

```toml
cmd-ctrl-alt-shift-rightSquareBracket = 'exec-and-forget @PLUGIN_DIR@/media-ctl next'
```

The generated file is gitignored, and `install.sh` builds it before linking.

### Collisions are caught before AeroSpace sees them

Two plugins binding the same key, or a plugin colliding with the base config,
is the single easiest way to break this setup — and AeroSpace reports it only
as `Ill-formed key` with the line number of the *second* definition, which
tells you nothing about which plugin is at fault. `build-config` refuses first
and names both sides:

```
plugin 'volume' binds cmd-ctrl-alt-w, already bound by base config (line 87)
AeroSpace would reject this as 'Ill-formed key'. Change one of them or disable a plugin.
rolled back — plugin state unchanged
```

The enable is rolled back, so a bad plugin cannot leave you with a config that
fails to build.

### Shipped examples

| Plugin | Bindings |
|---|---|
| `volume` | `Super+[` / `Super+]` volume, `Super+\` mute — uses AeroSpace's native `volume` command, no dependencies |
| `screenshot` | `Super+P` region to clipboard, `Super+Shift+P` region to file |
| `dictation` | [Handy](https://handy.computer): **Right Option held** = push-to-talk, **Super+D** = toggle start/stop |
| `media` | now playing in the menu bar with transport controls for whichever player is running; `Super+Shift+[` / `]` prev/next, `Super+Shift+\\` play-pause |

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

Arrows do focus and movement. `H`/`J`/`K`/`L` are deliberately *not* aliases
for them: `Super+K` is the cheatsheet (Omarchy's key for it), and half a vim
cluster is worse than none. `hjkl` still works inside resize mode.

### Windows
| Key | Action |
|---|---|
| `Super+Return` | terminal |
| `Super+Shift+Return` | browser |
| `Super+Space` | Raycast |
| `Super+W` | close window |
| `Super+←↓↑→` | focus |
| `Super+Shift+←↓↑→` | move window |
| `Alt+Tab` / `Alt+Shift+Tab` | cycle windows within the workspace |

### Layout
| Key | Action |
|---|---|
| `Super+T` | float ⇄ tile |
| `Super+E` | flip split orientation |
| `Super+A` | accordion ⇄ tiles |
| `Super+F` | fullscreen (no gaps) |
| `Super+K` | keybinding cheatsheet (toggle) |
| `Super+Shift+K` | plugin panel (toggle) — `j`/`k` move, `space` toggles, `1`-`9` jump, `Esc` closes |
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
two bindings for the same chord — that is what you will see. The line number
it reports is the *second* definition. `bin/build-config` catches this for
plugin bindings before AeroSpace ever sees the file.

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

**Handy has one global dictation mode, not one per binding.** `push_to_talk`
in its `settings_store.json` makes the transcribe binding *either* hold-to-talk
*or* tap-to-toggle — you cannot have both from Handy alone. The `dictation`
plugin puts Handy in toggle mode and emulates push-to-talk in Karabiner by
sending the chord on key-down **and again on key-up**, so holding brackets the
recording. That is how both behaviours coexist.

**Karabiner uses the first rule that matches a key.** New rules are inserted at
the front of the list, which shadows any pre-existing rule on the same key
rather than deleting it — uninstall removes ours and yours starts working
again. It also means the Caps Lock -> Super rule must stay above anything that
matches a Super chord.

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
bin/login-agent                   launch-at-login for SwiftBar
bin/doctor                        diagnose the three layers when a chord does nothing
bin/cheatsheet                    render the cheatsheet from aerospace.toml
bin/cheatsheet-toggle             Super+K show/hide
bin/build-config                  aerospace.base.toml + plugins -> aerospace.toml
bin/plugin                        list / enable / disable plugins
plugins/<name>/                   see Plugins above
config/aerospace/aerospace.base.toml   the window manager (aerospace.toml is generated)
config/swiftbar/aerospace.10s.sh  menu bar plugin: pills, switcher, cheatsheet
config/borders/bordersrc          focused-window ring
config/karabiner/caps-to-super.json   the one rule, as a snippet
```

State lives in `~/.local/state/hyperspace/`.
