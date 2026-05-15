# Contributing

## Development setup

```sh
flutter pub get
dart tool/install_hooks.dart
```

`install_hooks.dart` points git at the version-controlled `hooks/` directory
(`core.hooksPath=hooks`). Run it once per clone — and once per added worktree,
since `core.hooksPath` is shared but each worktree needs it set.

## Pre-commit hook

`hooks/pre-commit` formats staged Dart files (and re-stages them) before each
commit, so unformatted code never reaches CI. It compiles
`tool/format_pre_commit.dart` to a cached AOT binary on first use — subsequent
commits are near-instant.

The hook uses the same formatter configuration as `tool/prepare_submit.dart`
(which CI runs); keep the two in sync. Code style beyond formatting (analyzer
lints) is still enforced by CI, not the hook.

If dependencies aren't resolved yet, the hook skips itself gracefully and lets
the commit through — run `flutter pub get` to enable it.
