# Security

hyperspace edits your keyboard configuration, sets system preferences and
installs login items. That is a lot of trust to ask for a window manager
setup, so this describes exactly what it does, and how to check rather than
believe.

## Read it before you run it

```sh
./install.sh --dry-run
```

Prints every package, file, symlink, preference, login agent and service it
would touch, and changes nothing. Every mutation in `install.sh` sits behind
that flag, and `tests/properties.sh` fails the build if one is added without
it, so the listing cannot quietly drift from what the script does.

Already installed? `hyperspace-doctor --audit` prints what has been changed on
this machine, where each displaced file was backed up to, and what
`uninstall.sh` will put back. It reads the same manifest uninstall restores
from, so it is a description of the actual restore, not a summary of intent.

## What it will never do

These are enforced by `tests/properties.sh` in CI, not just promised here:

| Property | Why it matters |
|---|---|
| No `sudo`, no `doas` | Nothing here needs root. A setup script asking for your password gives you no way to know what for. |
| No network access at runtime | Nothing is downloaded, nothing is reported. Homebrew reaches the network during `install.sh`, acting on a `Brewfile` you can read. |
| No `eval`, nothing piped into a shell | The `curl \| bash` pattern turns any compromised host into arbitrary code. There is no download here to compromise. |
| Never writes to your shell config | `~/.zshrc` and friends are yours. This is not a dotfiles manager. |
| Never removes a Homebrew package on teardown | `uninstall.sh` prints the commands and lets you decide. |
| No `KeepAlive` in any LaunchAgent | Agents launch apps at login. Nothing stays resident, so there is no daemon of ours running. |

Each has a negative test: the suite was checked by introducing each violation
and confirming it fails.

## What it does do, that you should know about

- **Edits `~/.config/karabiner/karabiner.json`.** Karabiner sees every
  keystroke you type, so this is the most sensitive thing here. hyperspace
  backs the file up beside itself, inserts one rule named `Caps Lock -> Super`
  at the front of the active profile, and leaves every other rule alone.
  `bin/karabiner-rule` is the only code that touches it, and it is about a
  hundred lines of readable Python.
- **Sets two preferences:** `_HIHideMenuBar` and SwiftBar's plugin directory.
  Both record their previous value first, so uninstall restores what you had
  rather than guessing at a default.
- **Installs one LaunchAgent** that opens SwiftBar at login. `RunAtLoad` only.
- **Compiles two small Swift panels** on first use and caches the binaries in
  `~/.local/state/hyperspace`. Local compilation of source in the repo you
  cloned; nothing is fetched.
- **Runs plugin hooks.** See below.

## Plugins run code

A plugin is a directory under `plugins/`. Enabling one runs its `install.sh`
**as you**, with your permissions. This is not incidental: the `dictation`
plugin uses it to merge Karabiner rules, which is a reasonable thing for a
plugin to need and an unreasonable thing to do silently.

So `hyperspace-plugin enable <name>` names the hook, shows its size, and offers
to print it before running:

```
enabling dictation
  dictation/install.sh will run as you (612 bytes)
  [r]un, [s]how it first, or [q]uit?
```

The menu bar and the panel pass `--yes`, because a GUI toggle has no stdin to
answer a prompt with. They can only enable plugins already present in the repo
you cloned. **A plugin from somewhere else is code from somewhere else.** Read
it first; nothing sandboxes it.

## Verifying what you cloned

```sh
git log --show-signature      # commit signatures, if the author signs
./tests/properties.sh         # the guarantees above, checked against the source
./tests/dryrun.sh             # proves --dry-run changes nothing, from outside
```

`tests/reversible.sh` goes further: it installs, uninstalls, and diffs the
machine to prove the teardown is complete. It really installs, so it refuses to
run without `HYPERSPACE_TEST_I_MEAN_IT=1` and wants a machine you can throw
away.

## Reporting something

Open an issue. If it is sensitive, say so in the issue without the details and
ask for a private channel first.

This is a personal setup repo maintained in spare time. There is no SLA, and
you should read the code before running it, which is why so much work has gone
into making that easy.
