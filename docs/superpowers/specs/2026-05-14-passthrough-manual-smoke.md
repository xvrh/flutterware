# Passthrough PTY — Manual Smoke Tests

Companion to `2026-05-14-passthrough-pty-design.md`. These tests cover behavior
that's awkward to automate (interactive TUIs, real terminal resize, real signal
forwarding via keyboard).

Run all from `app/`:

```bash
dart run bin/passthrough.dart run -- <command>
```

## Checklist

- [ ] **vi**: `dart run bin/passthrough.dart run -- vi /tmp/foo`
  - Edit a file, save (`:w`), quit (`:q`). Confirm normal exit.
  - While in vi, resize the terminal window; run `:set columns?` — it should reflect the new size.

- [ ] **top**: `dart run bin/passthrough.dart run -- top`
  - UI redraws cleanly, columns align.
  - Press `q` to quit. Confirm parent shell returns with normal tty modes (try typing — characters should echo).

- [ ] **bash interactive**: `dart run bin/passthrough.dart run -- bash -i`
  - Tab completion works.
  - Start `sleep 30`, press Ctrl+C — child should be interrupted promptly.
  - Press Ctrl+D — bash exits, parent shell returns cleanly.
  - Prompt colors render.

- [ ] **ssh** (if available): `dart run bin/passthrough.dart run -- ssh <some-host>`
  - Password prompt does not echo characters.
  - Interactive session usable; remote terminal sees correct dimensions.

- [ ] **External SIGINT**: in one terminal, run `dart run bin/passthrough.dart run -- sleep 30`. In another, find the parent's pid and `kill -INT <pid>`. The child sleep should exit; parent should print summary with exit 130.

## Pass criteria

All four interactive scenarios usable. Parent shell never left in a broken tty state.
