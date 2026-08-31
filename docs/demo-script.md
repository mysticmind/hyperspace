# hyperspace on screen

A shooting script for a screen recording of the setup. Runtime 4:30, nine beats,
voice over recorded after the fact. Single display, scaled to 1x.

There is a sixty second recut at the bottom for a README embed.

## Before you hit record

Everything here is keyboard driven, so the recording lives or dies on whether the
viewer can see which keys you pressed.

**The machine**

- One display, scaled to 1x, Retina on. Ring detail is the whole aesthetic.
- Desktop icons hidden, wallpaper plain and dark.
- Notifications in Do Not Disturb. A banner over a tiled window is a reshoot.
- Fresh login, or `hyperspace-restart`, so workspaces start empty.

**The overlay**

- Run a keycaster (KeyCastr, bottom left). Super shows as `⌘⌃⌥`, which is exactly
  the point.
- Terminal at 16pt or larger. 14pt is unreadable after compression.
- Cursor mostly parked. Move it only when the demo is about the menu bar.

**The state**

- All four plugins disabled:
  `hyperspace-plugin disable volume screenshot media dictation`
- Menu bar hidden (the install default), so beat 07 has somewhere to go.
- A second terminal tab ready with the repo checked out, for the shell beats.
- A throwaway colliding plugin staged for beat 06 (see that beat).

## Beat by beat

Timecodes are cumulative and assume a calm pace. Press chords slowly enough that
the keycaster frame lands before the window moves, roughly one chord per second.

### 01 - Cold open, no explanation

`0:00` · 14s

- **On screen** Two windows already tiled edge to edge: a terminal on the left, a
  browser on the right. Nothing else.
- **Press** `Super+→` then `Super+←`, one second apart. The ring crosses the
  screen and back.
- **Hold** Two full seconds on the second window before speaking.

> "This is macOS. No gaps, no title bars, and the only thing telling you where you
> are is a two point ring on the focused window."

Do not open the cheatsheet yet. The open should raise the question that beat 04
answers.

### 02 - Caps Lock is the whole trick

`0:14` · 26s

- **On screen** Cut to the keycaster in close crop, or zoom the corner in post.
  Rest a finger on Caps Lock.
- **Press** `Super+Return` twice. Two more terminals appear and the layout splits
  three ways, then four.

> "Every binding hangs off one key. Karabiner turns Caps Lock into Command,
> Control and Option held together, a chord nothing else on the system claims.
> Caps Lock was doing nothing anyway."

> "Super and Return opens a terminal. Whichever terminal you actually have
> installed: the config bakes in the answer at build time rather than assuming
> mine."

### 03 - Moving, splitting, floating

`0:40` · 40s

- **Press** `Super+↓` `Super+↑` - focus travels, ring follows.
- **Press** `Super+Shift+→` - the focused window swaps places with its neighbour.
- **Press** `Super+E` - the split flips from vertical to horizontal.
- **Press** `Super+A` - accordion. `Super+A` again to come back.
- **Press** `Super+F` - fullscreen inside the tiler, gaps gone. Again to restore.
- **Press** `Super+T` on one window - it floats free. `Super+T` to tile it back.
- **Press** `Super+W` twice to close back down to two windows.

> "Arrows focus. Shift and arrows move. E flips the split, A folds the stack into
> an accordion, F fills the screen, T lets a window out of the layout entirely."

> "Arrows, not H J K L. Super and K is the cheatsheet, and half a vim cluster is
> worse than none."

### 04 - Workspaces and the menu bar pills

`1:20` · 35s

- **Press** `Super+2` - empty workspace. `Super+Return` for a terminal there.
- **Press** `Super+Shift+3` - that window is thrown to workspace 3, which follows.
- **Mouse** Nudge the pointer to the top edge. The menu bar drops in and the
  workspace pills are sitting in it. Hold three seconds.
- **Press** `Super+B` - back and forth to the previous workspace.

> "Nine workspaces on Super and a number. Shift sends the window with you."

> "The indicator is a SwiftBar item, so it lives in the real menu bar next to
> Wi-Fi and the clock rather than replacing the bar with its own. AeroSpace pushes
> it an update the instant a workspace changes; nothing here polls."

### 05 - The cheatsheet reads its own config

`1:55` · 30s

- **Press** `Super+K`. The panel fades in, centred, above everything.
- **On screen** Let it sit. Scroll it if it scrolls. Then `Super+K` to dismiss.

> "Every binding, on one panel. It is not a document I keep in sync, it is
> generated from the live AeroSpace config at the moment you press the key, by
> parsing the file the window manager is running."

> "A trailing comment on a binding becomes its description. So the cheatsheet
> cannot drift from the keys it documents, and anything a plugin adds shows up in
> it for free."

Leave that last clause hanging. Beat 06 pays it off, so shoot the two back to
back.

### 06 - Plugins, and the collision it refuses

`2:25` · 45s

- **Press** `Super+Shift+K` - the plugin panel. `j` `k` to move, `space` on
  *volume*, `Esc` to close.
- **Press** `Super+]` a few times - the volume HUD climbs. A binding that did not
  exist ten seconds ago.
- **Press** `Super+K` - the volume keys are now listed in the cheatsheet.
  `Super+K` to close.
- **Terminal** Enable a deliberately colliding plugin so the refusal prints:

```
$ hyperspace-plugin enable demo-collide
plugin 'demo-collide' binds cmd-ctrl-alt-w, already bound by base config (line 87)
AeroSpace would reject this as 'Ill-formed key'. Change one of them or disable a plugin.
rolled back - plugin state unchanged
```

> "A plugin is a directory with a couple of TOML files. Enabling one splices its
> bindings into the generated config, and nothing is enabled implicitly, so
> pulling this repo can never silently rebind your keyboard."

> "Two plugins wanting the same chord is the easiest way to break a setup like
> this, and AeroSpace reports it only as 'Ill-formed key' pointing at the wrong
> line. So the build refuses first, names both sides, and rolls the enable back."

**Stage this:** copy `plugins/volume` to `plugins/demo-collide` and point one
binding at `cmd-ctrl-alt-w`. Delete it after the shoot.

### 07 - Give the menu bar back

`3:10` · 25s

- **Press** `Super+Shift+B`. The bar appears, AeroSpace restarts, and every window
  resizes down to meet it.
- **Press** `Super+Shift+B` again. The bar goes, the windows reclaim the strip.

> "The menu bar is auto-hidden, which is what lets windows use the full display
> height: hide it and macOS reports the whole screen as usable."

> "Turning it back on is one preference, but the windows would stay tucked
> underneath it. AeroSpace reads the usable height once and a config reload will
> not re-read it. So this binding does both halves, flips the setting and restarts
> the tiler, and the geometry actually follows."

### 08 - It edits your keyboard, so here is the receipt

`3:35` · 40s

- **Terminal** Fullscreen the terminal (`Super+F`). Run three commands, letting
  each finish. Scroll speed matters more than output detail.

```sh
./install.sh --dry-run      # every file, symlink and preference it would touch
hyperspace-doctor --audit   # what it has already done here, and what uninstall restores
./tests/properties.sh       # the guarantees, checked against the source
```

> "This installs a login item, sets system preferences and merges a rule into your
> Karabiner config. That is a lot of trust for a window manager setup, so the
> guarantees are tested rather than promised."

> "No sudo. No network at runtime. Never writes to your shell config. Never
> removes a Homebrew package on teardown. Uninstall restores every file it
> displaced from values recorded at install time, and CI fails if any of that
> stops being true."

### 09 - Close on the thing you opened with

`4:15` · 15s

- **Press** `Super+F` to leave fullscreen, back to the two window layout from
  beat 01.
- **On screen** Two seconds of silence, then cut. Repo URL over the last frame in
  post.

> "Four tools someone else maintains, a handful of config files, and no daemons of
> my own. Clone it, dry run it, and read what it is about to do to your keyboard
> before you let it."

## The sixty second version

Same footage, recut for a README embed or a social post. One narration line per
beat, or no narration at all with the keycaster carrying it.

| In | Beat | Keep |
|---|---|---|
| 0:00 | Cold open | Focus crossing two windows, ring following. No words. |
| 0:06 | Caps Lock | Keycaster close crop, two terminals opening on `Super+Return`. |
| 0:16 | Layout | `Super+E`, `Super+A`, `Super+F` back to back, no pauses. |
| 0:28 | Workspaces | Send a window with `Super+Shift+3`, then the pills on hover. |
| 0:38 | Cheatsheet | `Super+K` open, hold four seconds, close. |
| 0:48 | Plugin | Panel, spacebar on volume, then `Super+]` working immediately. |
| 0:58 | End card | Repo URL on the tiled layout. |

## Notes for the edit

**Pacing**

- Window animations are instant. Hold a beat after each chord or the viewer misses
  the change entirely.
- Beat 07 restarts AeroSpace and there is a visible blink. Keep it, do not cut
  around it; it is what the narration is about.
- Trim dead terminal scrollback rather than speeding it up. Sped up shell output
  reads as filler.

**Legibility**

- Export at native resolution. The ring is a thin line and it is the first thing
  compression eats.
- If the keycaster is small in frame, punch in 1.4x on beats 02 and 06 only.
- Caption the chords as well, for anyone watching muted.

**Reshoot triggers**

- A notification banner, a Dock bounce, or the pointer drifting through a beat
  that is not about the menu bar.
- A chord that does nothing. Karabiner can load a config without applying it: run
  `hyperspace-doctor` and reshoot.
- Any personal file names visible in a terminal or Finder window.

---

Written against the bindings in `config/aerospace/aerospace.base.toml`. Re-check
the chord list before shooting if the base config has moved since.
