#!/bin/sh
# Boots the flutterware MCP server for THIS checkout, healing the worktree
# first. User projects never run this — `fw init` registers the AOT `fw mcp`
# there, which opens its session per tool call and so survives an unresolved
# worktree on its own. This checkout runs the server from source instead
# (a stale global `fw` cannot represent the branch being worked on), and a
# source run cannot even resolve itself until the one-time setup has run:
# `.fvm/` is gitignored and the workspace starts unresolved. An MCP client
# that fails to connect at session start never retries, so without this the
# whole session runs toolless over a setup race. Pay the setup on first
# connect instead: slow once, connected always.
#
# stdio discipline: stdout belongs to the MCP protocol, so every word said
# here goes to stderr — and stdin *is* the protocol stream, so no bootstrap
# command may inherit it. fvm can prompt (the pre-commit hook says the same),
# and a prompt here would eat protocol bytes: everything runs </dev/null,
# where a would-be prompt fails fast instead.
set -e
cd "$(dirname "$0")/.."

say() { echo "[mcp bootstrap] $*" >&2; }

if ! command -v fvm >/dev/null 2>&1; then
  say 'fvm is not on PATH — install it (https://fvm.app) and reconnect.'
  exit 1
fi

# The version pinned in .fvmrc, empty when unreadable — the hook's own sed.
pin="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc 2>/dev/null | head -n1)"

# The symlink satisfies only if it still points at the pin: it may predate a
# pin bump on this branch, and serving under the old SDK fails the workspace
# constraint with an error that says nothing about why.
sdk_current() {
  [ -d .fvm/flutter_sdk ] || return 1
  [ -n "$pin" ] || return 0
  [ "$(basename "$(readlink .fvm/flutter_sdk || true)")" = "$pin" ]
}

if ! sdk_current || [ ! -f .dart_tool/package_config.json ]; then
  # Parallel sessions on one worktree each spawn this script; two concurrent
  # `fvm use`/`pub get` runs on one workspace race each other. One bootstraps
  # and writes its pid into the lock; the rest wait while that pid is alive.
  # Liveness, not age: a cold `fvm install` can legitimately outlast any
  # timer, and deleting a *live* lock starts the concurrent install the lock
  # exists to prevent. A lock whose owner is gone is taken over, and so is
  # one that never gains an owner — a holder killed between its mkdir and
  # its pid write.
  lock=.dart_tool/mcp_bootstrap.lock
  mkdir -p .dart_tool
  announced=0
  ownerless=0
  until mkdir "$lock" 2>/dev/null; do
    owner="$(cat "$lock/pid" 2>/dev/null || true)"
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
      ownerless=0
      if [ "$announced" -eq 0 ]; then
        say 'another session is bootstrapping — waiting…'
        announced=1
      fi
    elif [ -n "$owner" ]; then
      say 'the session holding the bootstrap lock died — taking over.'
      rm -rf "$lock"
      continue
    else
      ownerless=$((ownerless + 1))
      if [ "$ownerless" -ge 15 ]; then
        say 'a bootstrap lock with no owner for 30s — taking over.'
        rm -rf "$lock"
        continue
      fi
    fi
    sleep 2
  done
  echo "$$" >"$lock/pid"
  # Best effort on a client kill; owner-liveness above is the real guarantee.
  trap 'rm -rf "$lock" 2>/dev/null' EXIT
  trap 'rm -rf "$lock" 2>/dev/null; exit 143' INT TERM

  # Re-check under the lock: whoever held it probably did the work.
  if ! sdk_current; then
    say "installing the pinned Flutter SDK (fast when cached)…"
    fvm install </dev/null >&2
    fvm use --skip-pub-get </dev/null >&2
    # A download killed partway (a client's startup timeout) can leave fvm's
    # cache holding a directory that is not an SDK. Refuse loudly here — the
    # downstream failure says "kernel binary" things that name no cause.
    if [ ! -x .fvm/flutter_sdk/bin/dart ]; then
      say "the SDK cache at $(readlink .fvm/flutter_sdk) has no bin/dart —"
      say "likely a half-finished download. Run: fvm remove $pin && fvm install"
      exit 1
    fi
  fi
  if [ ! -f .dart_tool/package_config.json ]; then
    say 'workspace not resolved — running pub get…'
    fvm flutter pub get </dev/null >&2
  fi

  rm -rf "$lock" 2>/dev/null || true
  trap - EXIT INT TERM
fi

exec fvm dart run flutterware_app:mcp
