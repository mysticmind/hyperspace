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

hyperspace auto-hides the menu bar so AeroSpace can reclaim the 30pt strip - the
bar is off screen most of the time, which leaves an overflow manager very little
to manage. Meanwhile Ice on macOS 26 struggles with exactly the items that end
up hidden here: on this setup all fourteen were Control Centre items (Wi-Fi,
Bluetooth, Sound, Battery), which macOS vends from a single process. Ice cannot
resolve an owning PID for them:

```
MenuBarItemManager  Missing sourcePID for <…:Item-0 (windowID: 148)>
MenuBarItemManager  Clearing cached menu bar item windowIDs
```

So it cannot forward a click to them, and it invalidates its cache twice a
second trying. Clicking a hidden item in the Ice Bar did nothing; letting Ice
expand items into the real menu bar instead ran into its "smart" auto-rehide,
which fires as soon as the auto-hidden bar drops. Two settings pulling against
each other, for a feature worth little once the bar is hidden anyway.

For the record, on the crash that came first: the `jordanbaird-ice` cask is
stable 0.11.12, built October 2024, and it traps ~0.7s into every launch on
macOS 26. Upstream's `0.11.13-dev.2` prerelease fixes that much. If you want Ice
back, install it yourself - hyperspace no longer has an opinion about it.

## Requirements

| Needed | Why | If missing |
|---|---|---|
| macOS | it drives AeroSpace, Karabiner and the macOS menu bar | refuses |
| Homebrew | everything else installs through it | refuses, links to brew.sh |
| `python3` 3.9+ | config generation, cheatsheet, plugin manager | refuses, `xcode-select --install` |
| `swiftc` | the native cheatsheet and plugin panels | warns, falls back |
| a terminal | `Super+Return` | uses whichever you have, else `Terminal` |
| Karabiner-Elements launched once | it writes `karabiner.json` on first launch, and the Caps Lock rule is merged into that file | offers to launch it and wait, else refuses |
| trusted Homebrew taps | Homebrew 6 will not load a cask from an untrusted tap | names them and asks |
| Accessibility permission | AeroSpace and Karabiner cannot manage windows or keys without it | cannot be scripted; macOS asks on first run |

macOS ships python 3.9 and `swiftc` with the Command Line Tools, so
`xcode-select --install` covers both. Everything above except the Accessibility
grant is checked by `install.sh` before your configuration is touched, and each
one names the command that fixes it.

The Karabiner row is the easy one to trip over on a fresh machine: `brew`
installs the app, but the app writes its config on first launch, so a brand new
Mac has no `karabiner.json` for the rule to merge into. install.sh offers to
open it and wait rather than making you work that out.

## Install

```sh
git clone <this repo> ~/.local/share/hyperspace
cd ~/.local/share/hyperspace
./install.sh --dry-run     # read exactly what it will touch
./install.sh
```

On Homebrew 6, the first run stops to ask you to trust two third-party taps
(`nikitabobko/tap` for AeroSpace, `FelixKratz/formulae` for borders). Homebrew
will not load a cask from an untrusted tap, because tapping one means running
code its maintainer publishes. install.sh names them and asks; it will not
trust them for you.

`--dry-run` prints every package, file, symlink, preference, login agent and
service it would change, and changes nothing. This script edits your keyboard
configuration, so you should not have to take that on trust. See
[SECURITY.md](SECURITY.md).

Clone it wherever you like. `install.sh` works out where it is from its own
path, and everything it links points back at that location, so nothing here
assumes a particular directory. `~/.local/share` is only the suggestion that
matches where the rest of it already lives: `~/.local/bin` for the commands,
`~/.local/state/hyperspace` for the manifest and backups, `~/.config` for the
configs it links.

One consequence worth knowing: the paths that point back are absolute, both the
symlinks and the plugin paths `build-config` bakes into the generated
`aerospace.toml`. **Move the repo after installing and both break.** Re-run
`install.sh` from the new location to repoint them, or run `uninstall.sh`
before you move it.

Then grant Accessibility to AeroSpace and Karabiner when macOS asks. That is
the only manual step - everything starts at login on its own.

## Uninstall

```sh
./uninstall.sh
```

It restores every file it displaced and every `defaults` key it changed, using
values recorded at install time. **It does not uninstall Homebrew packages.**
It prints the commands and lets you decide.

## The menu bar, and why tiling has to be told

hyperspace auto-hides the menu bar because that is what lets windows use the
full display height: with it hidden macOS reports `visibleFrame` as the whole
screen, so AeroSpace tiles all of it.

Turning it back on is a one-line `defaults write`, but doing only that leaves
every window where it was, tucked under the bar. AeroSpace reads the usable
height once and caches it, and `reload-config` does not re-read it. Measured:

```
menu bar hidden                 y=6   h=887
menu bar shown, reload only     y=6   h=887     <- under the bar
menu bar shown, after restart   y=36  h=857
```

So `Super+Shift+B` does both halves: flips the setting, then restarts AeroSpace
so the geometry is recomputed. `hyperspace-menubar show|hide|sync` is the same
thing from a shell, and it is in the SwiftBar menu too.

`sync` is for when the menu bar changed somewhere this could not see it -
System Settings, another tool, a display arriving. Nothing watches for that:
hyperspace runs no daemons, so the recomputation has to be asked for.

## The cheatsheet - `Super+K`

A floating window listing every binding. Press `Super+K` again to close it.

It is **generated from `aerospace.toml` at the moment you press the key**, by
parsing the live config - so it cannot drift from the keys it documents, and
any binding a plugin adds appears in it for free. A trailing comment on a
binding becomes its description:

```toml
cmd-ctrl-alt-w = 'close'   # close window
```

It is a native SwiftUI panel, compiled on first run and cached - no build step,
no binary in the repo, no `.app` bundle. It centres itself, sits above other
windows, and follows light and dark mode, all of which it gets for free by
being a real window: it can measure itself.

That is why it stopped being a terminal. A terminal window cannot be asked how
big it will be, so the old version predicted its own size from the glyph metrics
of JetBrains Mono at 14 and did arithmetic to centre it. Constants like that go
wrong the moment the font does, and when they drift far enough the window is
placed off screen and macOS clamps it to an edge - which looks like bad centring
but is not. `NSHostingView.fittingSize` replaces the whole guess.

The Alacritty version survives as `bin/cheatsheet-term`, the fallback for
machines with no `swiftc`. `bin/cheatsheet-toggle` picks between them.

The toggle is just "is the panel running" - nothing resident, no helper process.

## Plugins

A plugin is a directory under `plugins/`:

```
plugins/<name>/
  plugin.toml        name + description                          (required)
  bindings.toml      [mode.main.binding] lines to splice in      (optional)
  window-rules.toml  [[on-window-detected]] blocks               (optional)
  swiftbar/          menu bar plugins, linked into ~/.config/swiftbar
                     (only put plugins here - SwiftBar RUNS every file in
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

`aerospace.toml` is **generated** - edit `aerospace.base.toml` instead. The
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
is the single easiest way to break this setup - and AeroSpace reports it only
as `Ill-formed key` with the line number of the *second* definition, which
tells you nothing about which plugin is at fault. `build-config` refuses first
and names both sides:

```
plugin 'volume' binds cmd-ctrl-alt-w, already bound by base config (line 87)
AeroSpace would reject this as 'Ill-formed key'. Change one of them or disable a plugin.
rolled back - plugin state unchanged
```

The enable is rolled back, so a bad plugin cannot leave you with a config that
fails to build.

### Shipped examples

| Plugin | Bindings |
|---|---|
| `volume` | `Super+[` / `Super+]` volume, `Super+\` mute - uses AeroSpace's native `volume` command, no dependencies |
| `screenshot` | `Super+P` region to clipboard, `Super+Shift+P` region to file |
| `dictation` | [Handy](https://handy.computer): **Right Option held** = push-to-talk, **Super+D** = toggle start/stop |
| `media` | now playing in the menu bar with transport controls for whichever player is running; `Super+Shift+[` / `]` prev/next, `Super+Shift+\\` play-pause |

## Which terminal Super+Return opens

Whichever you have. `bin/terminal` resolves it and `build-config` bakes the
answer into `aerospace.toml`, so the binding names a terminal that is actually
installed rather than one this repo happens to prefer. First match wins:

```
$HYPERSPACE_TERMINAL                  one-off, or for a script
~/.config/hyperspace/terminal         a file with the app name, to make it stick
first installed of: Alacritty, Ghostty, kitty, WezTerm, iTerm
Terminal                              ships with macOS, so there is always an answer
```

`hyperspace-terminal` prints the current answer. Changing it takes a
`build-config` and an `aerospace reload-config`, or just re-run `install.sh`.

Note that hyperspace does not install a terminal. It used to hardcode
Alacritty, which is not in the Brewfile, so on a machine without it
`Super+Return` silently did nothing.

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
are not terminals (Firefox, and so on) give you no such setting - macOS has no
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
| `Super+Shift+B` | show / hide the menu bar, and resize the tiling to match |
| `Super+Shift+K` | plugin panel (toggle) - `j`/`k` move, `space` toggles, `1`-`9` jump, `Esc` closes |
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
| `Super+Shift+;` | service mode (`Esc` reload · `R` reset layout · `F` float · `S` restart stack · `⌫` close others) |

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
`reload-config` is not enough - AeroSpace does not recompute screen geometry
when the visible frame changes, and you get windows sized for the old frame.

**AeroSpace's TOML rejects duplicate keys** with the unhelpful message
`Ill-formed key`. If a binding is defined twice - easy when you have both
two bindings for the same chord - that is what you will see. The line number
it reports is the *second* definition. `bin/build-config` catches this for
plugin bindings before AeroSpace ever sees the file.

**Karabiner can read a new config without applying it.** The tell is in
`~/.local/share/karabiner/log/console_user_server.log`: a `Load ...karabiner.json`
line with no `core_configuration is updated` after it, usually alongside
`core_service_daemon_client connect_failed: Permission denied`. Every remap
silently does nothing - Caps Lock stops being Super and every binding looks
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
delivery - Karabiner or a conflicting global hotkey - not AeroSpace.

**Handy has one global dictation mode, not one per binding.** `push_to_talk`
in its `settings_store.json` makes the transcribe binding *either* hold-to-talk
*or* tap-to-toggle - you cannot have both from Handy alone. The `dictation`
plugin puts Handy in toggle mode and emulates push-to-talk in Karabiner by
sending the chord on key-down **and again on key-up**, so holding brackets the
recording. That is how both behaviours coexist.

**Karabiner uses the first rule that matches a key.** New rules are inserted at
the front of the list, which shadows any pre-existing rule on the same key
rather than deleting it - uninstall removes ours and yours starts working
again. It also means the Caps Lock -> Super rule must stay above anything that
matches a Super chord.

**The key is named `esc`, not `escape`.**

**`'''triple-quoted'''` TOML strings** are not parsed; use single quotes and
avoid command paths containing spaces.

## Security

It edits `karabiner.json`, sets system preferences and installs a login item,
which is a lot of trust for a window manager setup. So the guarantees are
tested rather than promised: no `sudo`, no network at runtime, no `eval` or
pipe-to-shell, never writes to your shell config, never removes a Homebrew
package on teardown, no `KeepAlive` in any LaunchAgent. `tests/properties.sh`
fails CI if any of those stops being true, and each check was verified by
introducing the violation and confirming it is caught.

```sh
./install.sh --dry-run       # what it would do, before it does anything
hyperspace-doctor --audit    # what it has already done here, and what uninstall restores
./tests/properties.sh        # the guarantees, checked against the source
./tests/dryrun.sh            # proves --dry-run is inert, from outside
```

Enabling a plugin runs that plugin's `install.sh` as you. That is deliberate
(the `dictation` plugin merges Karabiner rules with it) and it is now announced
and confirmable rather than silent. A plugin from elsewhere is code from
elsewhere; read it first.

[SECURITY.md](SECURITY.md) has the full account.

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

`bin/` is hand-written commands, not build output: thirteen executable scripts
that `install.sh` symlinks onto your PATH as `hyperspace-*`, plus the two Swift
sources beside the wrappers that compile them. Source sits next to whatever
uses it here, the same way `plugins/media/` keeps `media-ctl` next to the menu
bar plugin that calls it. Nothing compiled is ever committed: the two panels
are built on first use and cached in `~/.local/state/hyperspace/`.

```
Brewfile                          dependencies
install.sh / uninstall.sh         symmetric, manifest-driven
bin/karabiner-rule                surgical add/remove of the Caps→Super rule
bin/login-agent                   launch-at-login for SwiftBar
bin/doctor                        diagnose the three layers when a chord does nothing
bin/restart                       restart Karabiner + AeroSpace when the stack is wedged
bin/menubar                       show/hide the menu bar and make the tiling follow
bin/terminal                      which terminal Super+Return opens
tests/properties.sh               the security guarantees, as tests
tests/dryrun.sh                   proves --dry-run changes nothing
tests/reversible.sh               install, uninstall, diff the machine (destructive)
bin/cheatsheet                    parse aerospace.toml (text, or --json for the panel)
bin/cheatsheet-toggle             Super+K show/hide, builds and caches the panel
bin/cheatsheet-ui.swift           the cheatsheet panel (SwiftUI)
bin/cheatsheet-term               Alacritty cheatsheet, fallback when there is no swiftc
bin/build-config                  aerospace.base.toml + plugins -> aerospace.toml
bin/plugin                        list / enable / disable plugins
bin/plugin-ui                     Super+Shift+K show/hide, builds and caches the panel
bin/plugin-ui.swift               the plugin panel (SwiftUI)
bin/plugin-dialog                 osascript plugin picker, fallback when there is no swiftc
plugins/<name>/                   see Plugins above
config/aerospace/aerospace.base.toml   the window manager (aerospace.toml is generated)
config/swiftbar/aerospace.10s.sh  menu bar plugin: pills, switcher, cheatsheet
config/borders/bordersrc          focused-window ring
config/karabiner/caps-to-super.json   the one rule, as a snippet
```

State lives in `~/.local/state/hyperspace/`.
