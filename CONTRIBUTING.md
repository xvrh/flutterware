# Contributing

## Development setup

The Flutter SDK is pinned in `.fvmrc` and managed with [fvm](https://fvm.app).
The `flutter`/`dart` on PATH are usually older than the pin and fail the
workspace's SDK constraints — always go through `fvm flutter ...` /
`fvm dart ...` (equivalently `.fvm/flutter_sdk/bin/...`).

```sh
fvm install                      # once per machine: installs the .fvmrc-pinned SDK
fvm use --skip-pub-get           # once per clone/worktree: creates .fvm/flutter_sdk
fvm flutter pub get
git config core.hooksPath hooks  # once per clone; worktrees inherit it
```

`core.hooksPath hooks` points git at the version-controlled `hooks/` directory.
The value is relative, so it resolves against each worktree's own root — added
worktrees inherit it from the shared config and need no extra step.

## Pre-commit hook

`hooks/pre-commit` formats staged Dart files (and re-stages them) before each
commit, so unformatted code never reaches CI. It compiles
`tool/format_pre_commit.dart` to a cached AOT binary on first use — subsequent
commits are near-instant.

The hook uses the same formatter configuration as `tool/prepare_submit.dart`
(which CI runs); keep the two in sync. Code style beyond formatting (analyzer
lints) is still enforced by CI, not the hook.

If dependencies aren't resolved yet, or the pinned SDK isn't installed, the
hook skips itself gracefully and lets the commit through — run
`fvm flutter pub get` (and `fvm install` + `fvm use` if needed) to enable it.
