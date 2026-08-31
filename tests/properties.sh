#!/usr/bin/env bash
# The security properties, as tests.
#
# Every claim the README makes about what hyperspace will not do is checked
# here, so they stay true instead of merely being true on the day they were
# written. A property nobody tests is a property that quietly stops holding.
#
# Runs anywhere: no macOS, no Homebrew, no install required. That is deliberate,
# so CI on any runner can enforce it.
#
# Usage: tests/properties.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

pass=0 fail=0
ok()  { printf '  \033[1;32mok\033[0m    %s\n' "$*"; pass=$((pass+1)); }
bad() { printf '  \033[1;31mFAIL\033[0m  %s\n' "$*"; fail=$((fail+1)); }

# Tracked files only. An untracked scratch file is not what anyone installs.
files() { git ls-files; }

# Skip this file when scanning: it necessarily contains the patterns it bans.
scan() { git ls-files | grep -v '^tests/properties.sh$'; }

echo "Security properties"

# 1. Never asks for root. A tiling window manager has no business with sudo,
#    and a user who is asked for a password has no way to know what for.
if scan | xargs grep -nE '(^|[^a-zA-Z_-])(sudo|doas)( |$)' 2>/dev/null | grep -v '^\s*#' | grep -q .; then
  bad "found sudo/doas"
  scan | xargs grep -nE '(^|[^a-zA-Z_-])(sudo|doas)( |$)' 2>/dev/null | sed 's/^/        /'
else
  ok "no sudo, no doas, nothing asks for a password"
fi

# 2. The CORE never touches the network at runtime, and a plugin that does has
#    to declare it. Homebrew reaches the network during install.sh, acting on a
#    Brewfile you can read; nothing else in the core may fetch anything.
#
#    A plugin is where that stops being absolute, because `worldradio` is a
#    radio and a radio with no network is a box. So the property is scoped
#    rather than quietly broken: the plugin says `network = true` in its own
#    plugin.toml, bin/plugin prints that before enabling it, and nothing is
#    enabled implicitly. One check covers both halves - a fetcher in the core
#    fails, and so does a fetcher in a plugin that never declared one, because
#    only declared plugins are exempt.
#
#    The pattern covers python and Swift, not just the shell clients. It was
#    curl|wget|nc and friends alone, which urllib.request.urlopen walks
#    straight past - the property would have gone on reading as "ok" while a
#    plugin fetched whatever it liked.
FETCHERS='(^|[;&|(`$ ])(curl|wget|nc|ncat|telnet|scp|sftp|rsync)( |$)'
FETCHERS="$FETCHERS"'|urllib|urlopen|http\.client|requests\.(get|post)'
FETCHERS="$FETCHERS"'|URLSession|socket\.(getaddrinfo|create_connection)|gethostbyaddr'

# Prose, plus every plugin dir whose plugin.toml declares it - matched exactly
# as bin/plugin reads the key, so the test and the loader cannot disagree.
exempt='^(README\.md|Brewfile|SECURITY\.md)$'
for toml in plugins/*/plugin.toml; do
  [[ -f "$toml" ]] || continue
  if grep -qE '^[[:space:]]*network[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$toml"; then
    exempt="$exempt|^$(dirname "$toml")/"
  fi
done

if scan | grep -vE "$exempt" | xargs grep -nE "$FETCHERS" 2>/dev/null | grep -q .; then
  bad "a fetcher in something that never declared network = true"
  scan | grep -vE "$exempt" | xargs grep -nE "$FETCHERS" 2>/dev/null | sed 's/^/        /'
else
  ok "the core fetches nothing; only a plugin declaring network = true may"
fi

# 3. Nothing is piped into a shell, and nothing is eval'd. This is the pattern
#    that turns any compromised download into arbitrary code, and there is no
#    download here to compromise. Keep it that way.
# Prose is excluded, as in check 2: SECURITY.md documents this ban and would
# otherwise trip it. Markdown is not executed, so describing the pattern there
# is not the same as containing it.
code() { scan | grep -vE '\.md$'; }
if code | xargs grep -nE 'curl[^|]*\| *(ba)?sh|\beval\b|python[0-9.]* -c .*exec\(' 2>/dev/null | grep -q .; then
  bad "found eval or a pipe-to-shell"
  code | xargs grep -nE 'curl[^|]*\| *(ba)?sh|\beval\b|python[0-9.]* -c .*exec\(' 2>/dev/null | sed 's/^/        /'
else
  ok "no eval, nothing piped into a shell"
fi

# 4. Design rule 1: never touch shell config. The repo is not a dotfiles
#    manager and must never write to a file that runs on every login shell.
if scan | grep -vE '^(README\.md|install\.sh|SECURITY\.md)$' \
   | xargs grep -nE '(>|>>|tee|sed -i).*\.(zshrc|bashrc|bash_profile|zprofile|profile)' 2>/dev/null | grep -q .; then
  bad "something writes to a shell config"
else
  ok "nothing writes to .zshrc, .bashrc or any shell profile"
fi

# 5. Design rule 2: teardown removes no Homebrew package. uninstall.sh may
#    print the commands, never run them.
# Heredoc bodies are stripped first. uninstall.sh PRINTS the brew commands for
# the user to run themselves, and a check that cannot tell printing from doing
# would fail on the very design rule it is meant to protect.
strip_heredocs() { # file
  awk '
    heredoc != "" { if ($0 == heredoc) heredoc = ""; next }
    match($0, /<<-?['"'"'"]?[A-Za-z_][A-Za-z_0-9]*['"'"'"]?/) {
      d = substr($0, RSTART, RLENGTH)
      sub(/^<<-?/, "", d); gsub(/['"'"'"]/, "", d)
      heredoc = d; next
    }
    { print FILENAME ":" NR ":" $0 }
  ' "$1"
}
if strip_heredocs uninstall.sh | grep -E '^[^#]*brew (uninstall|remove|rm)' | grep -q .; then
  bad "uninstall.sh RUNS a brew uninstall (printing them is fine, running is not)"
  strip_heredocs uninstall.sh | grep -E '^[^#]*brew (uninstall|remove|rm)' | sed 's/^/        /'
else
  ok "uninstall.sh removes no Homebrew package (it only prints the commands)"
fi

# 6. Every mutation in install.sh is behind the dry-run flag. This is what
#    makes --dry-run trustworthy rather than decorative: if a write is added
#    without a guard, the listing silently stops matching what runs.
#
#    Block structure, not a line regex. The mutations live in the `else` arm of
#    `if (( DRY ))`, so a line-level match calls every one of them unguarded.
#    The first version of this check used awk with \s, which BSD awk ignores
#    and GNU awk honours: it found nothing on macOS and six false hits on
#    Linux, passing locally for the wrong reason. python3 is on both runners
#    and needs no such dialect.
if python3 - install.sh <<'GUARD'
import re, sys

src = open(sys.argv[1]).read().splitlines()

MUTATION = re.compile(r'''^\s*(defaults\s+write|ln\s+-sfn|rm\s|mv\s
                          |launchctl\s+(bootstrap|kickstart|bootout)
                          |brew\s+(bundle|services)|killall|open\s+-a)''', re.X)

# `if` and `fi` as whole words. The lookarounds keep `elif` and `config` out,
# and one-line `if ...; then ...; fi` balances because both are counted rather
# than being treated as either/or.
WORD = re.compile(r'(?<![\w-])(if|fi)(?![\w-])')
HEREDOC = re.compile(r'<<-?\s*[\'"]?([A-Za-z_][A-Za-z_0-9]*)[\'"]?')

stack = []          # one entry per open `if`; True when it is a DRY guard
unguarded = []
pending = None      # heredoc terminator we are waiting for

for n, line in enumerate(src, 1):
    if pending is not None:
        if line.strip() == pending:
            pending = None
        continue                     # heredoc body is text, not code
    bare = line.split('#', 1)[0]

    # Guard state applies to THIS line before it opens or closes anything, so a
    # mutation sharing a line with its own `if (( DRY ))` still counts.
    guarded = any(stack) or 'DRY' in bare
    if MUTATION.match(bare) and not guarded:
        unguarded.append((n, line.strip()))

    # Quoted text first: a `would "...remap if one is set"` message counts as
    # an if-opener otherwise, and one stray word silently unbalances the whole
    # parse. That is what the open-block guard below exists to notice.
    code = re.sub(r'"[^"]*"|\'[^\']*\'', '', bare)
    words = WORD.findall(code)
    for _ in range(words.count('if')):
        stack.append('DRY' in code)
    for _ in range(words.count('fi')):
        if stack:
            stack.pop()

    m = HEREDOC.search(bare)
    if m:
        pending = m.group(1)

if stack:
    print(f'        (parser left {len(stack)} if-block(s) open; check is unreliable)')
    sys.exit(1)
for n, text in unguarded:
    print(f'        install.sh:{n} {text}')
sys.exit(1 if unguarded else 0)
GUARD
then
  ok "every mutation in install.sh sits behind the dry-run guard"
else
  bad "install.sh has mutation(s) not behind the dry-run guard"
fi

# 7. LaunchAgents may launch, never persist. KeepAlive would make it a daemon,
#    which is the thing this repo promises not to install.
# The plist KEY, not the word. bin/login-agent's own comment says "no
# KeepAlive", and matching prose rather than the key would fail on a file that
# is documenting the very property being checked.
if scan | xargs grep -n '<key>KeepAlive</key>' 2>/dev/null | grep -q .; then
  bad "a LaunchAgent sets KeepAlive, which makes it a daemon"
  scan | xargs grep -n '<key>KeepAlive</key>' 2>/dev/null | sed 's/^/        /'
else
  ok "no LaunchAgent sets KeepAlive, so nothing stays resident"
fi

echo
printf 'properties: %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
