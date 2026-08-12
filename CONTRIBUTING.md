# Contributing

## Development setup

The Flutter SDK is pinned in `flutter_version` and fetched by the committed
`./fw` wrapper — no version manager to install. The `flutter`/`dart` on PATH
are usually older than the pin and fail the workspace's SDK constraints —
always go through `./fw flutter ...` / `./fw dart ...` (from a subdirectory,
`../fw` and so on). The first run downloads the pinned SDK to
`~/.flutterware/sdks/<version>/`; after that the wrapper adds ~0.1s.

```sh
./fw flutter pub get             # first run also downloads the pinned SDK
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
`./fw flutter pub get` to enable it.
