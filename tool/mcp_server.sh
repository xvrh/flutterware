#!/bin/sh
# Boots the flutterware MCP server for THIS checkout, healing the worktree
# first. User projects never run this — `fw init` registers the AOT `fw mcp`
# there, which opens its session per tool call and so survives an unresolved
# worktree on its own. This checkout runs the server from source instead
# (a stale global `fw` cannot represent the branch being worked on), and a
# source run cannot even resolve itself until the one-time setup has run:
# the SDK cache starts cold and the workspace starts unresolved. An MCP client
# that fails to connect at session start never retries, so without this the
# whole session runs toolless over a setup race. Pay the setup on first
# connect instead: slow once, connected always.
#
# stdio discipline: stdout belongs to the MCP protocol, so every word said
# here goes to stderr — and stdin *is* the protocol stream, so no bootstrap
# command may inherit it. A would-be prompt under </dev/null fails fast
# instead of eating protocol bytes.
set -e
cd "$(dirname "$0")/.."

say() { echo "[mcp bootstrap] $*" >&2; }

# The version pinned in flutter_version, empty when unreadable. The ./fw
# wrapper owns installing it; this only asks whether that already happened —
# a per-version cache dir means a pin bump on this branch reads as "not
# installed" all by itself.
pin="$(tr -d ' \t\r\n' < flutter_version 2>/dev/null || true)"

sdk_current() {
  [ -n "$pin" ] || return 1
  [ -x "${FW_SDK_CACHE:-$HOME/.flutterware/sdks}/$pin/bin/dart" ]
}

# Resolved is not enough: it has to be *current*. `dart run` re-resolves when a
# manifest is newer than the resolution, and that resolve reaches pub.dev —
# inside the client's 30s connect budget, over a network nobody here controls.
# Six sessions died in it on 2026-08-11 alone, each with a pub stack trace
# ("Attempting to send request on closed client") that names no cause and no
# fix. A rebase touching any pubspec is all it takes. So the wrapper resolves
# first, from the cache, and `dart run` finds nothing left to do.
resolution_current() {
  [ -f .dart_tool/package_config.json ] || return 1
  # -maxdepth 3 covers the workspace members and skips build output and the
  # example app's own nested packages; the lockfile moves whenever they do.
  [ -z "$(
    find . -maxdepth 3 \( -name pubspec.yaml -o -name pubspec.lock \) \
      -not -path './.*' -not -path '*/build/*' \
      -newer .dart_tool/package_config.json 2>/dev/null | head -n1
  )" ]
}

if ! sdk_current || ! resolution_current; then
  # Parallel sessions on one worktree each spawn this script; two concurrent
  # SDK-install/`pub get` runs on one workspace race each other. One
  # bootstraps and writes its pid into the lock; the rest wait while that pid
  # is alive. Liveness, not age: a cold SDK download can legitimately outlast any
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
    # The wrapper verifies the checksum and moves the SDK into place
    # atomically, so a download killed partway leaves no broken SDK — and its
    # own lock has owner-liveness, so it leaves no wedge either.
    say 'installing the pinned Flutter SDK (a cold download takes minutes)…'
    ./fw dart --version </dev/null >&2
  fi
  if ! resolution_current; then
    # Offline first, and usually last: a rebase moves a pubspec's mtime far
    # more often than it moves a version, and the cache already holds what the
    # lockfile pins. Only a genuinely new dependency needs the network, and
    # then the failure is about that package rather than about a socket.
    say 'resolution is stale — running pub get (offline first)…'
    ./fw flutter pub get --offline </dev/null >&2 ||
      ./fw flutter pub get </dev/null >&2
  fi

  rm -rf "$lock" 2>/dev/null || true
  trap - EXIT INT TERM
fi

# APP_TOOL_PATH is the "record, do not discover" half of the contract the
# launcher normally fills in. `Session.findAppToolDirectory` can resolve this
# package on its own now, but recording it here is free and keeps the catalog
# daemon working even if that resolution ever stops answering — which is how
# it was found: the server ran for weeks resolving null, and every previews
# screenshot refused with a message about `appPackageRoot` that named the
# symptom rather than the invocation.
exec env APP_TOOL_PATH="$PWD/app" ./fw dart run flutterware_app:mcp
