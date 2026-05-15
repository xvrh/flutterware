/// The bash shim installed as `<mirror>/bin/flutter` and `<mirror>/bin/dart`.
/// `@REAL@`, `@KIND@`, `@WRAP_EXE@` are replaced at install time.
///
/// Fast path is pure bash: marker walk-up, classification, one audit-log
/// line. Only *interesting* runs hand off to the compiled wrap executable.
const _shimTemplate = r'''#!/usr/bin/env bash
# flutterware wrap shim — generated; do not edit.
set -u
REAL="@REAL@"
KIND="@KIND@"
WRAP_EXE="@WRAP_EXE@"

# 1. Walk up for the flutter_version marker.
root=""
d="$PWD"
while :; do
  if [ -f "$d/flutter_version" ]; then root="$d"; break; fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
[ -z "$root" ] && exec "$REAL" "$@"

# 2. First non-flag argument (the subcommand).
sub=""
for a in "$@"; do
  case "$a" in
    -*) ;;
    *) sub="$a"; break ;;
  esac
done

# 3. Classify (probe default — replaced by config.dart in sub-project 3).
cls="noise"
if [ "$KIND" = "flutter" ]; then
  case "$sub" in
    run|test) cls="interesting" ;;
  esac
fi

# 4. Audit log — one line per invocation, every kind.
fwdir="$root/.flutterware"
mkdir -p "$fwdir" 2>/dev/null || true
printf '%s\t%s\t%s\t%s\t%s %s\n' \
  "$(date +%Y-%m-%dT%H:%M:%S)" "$PWD" "$KIND" "$cls" "$KIND" "$*" \
  >>"$fwdir/wrap-audit.log" 2>/dev/null || true

# 5. Dispatch. Interesting -> the wrap exe; anything else / missing exe -> real.
if [ "$cls" = "interesting" ] && [ -x "$WRAP_EXE" ]; then
  exec "$WRAP_EXE" run --real "$REAL" --kind "$KIND" -- "$@"
fi
exec "$REAL" "$@"
''';

/// Renders the shim with the given absolute paths baked in.
String renderShim({
  required String realBinary,
  required String kind,
  required String wrapExe,
}) =>
    _shimTemplate
        .replaceAll('@REAL@', realBinary)
        .replaceAll('@KIND@', kind)
        .replaceAll('@WRAP_EXE@', wrapExe);
