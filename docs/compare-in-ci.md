# Comparison in CI — a PR comment with pictures

`fw compare --report=<dir>` emits everything a pull-request comment needs;
what it deliberately does not do is host or post. A GitHub comment can only
show images by URL, and where those URLs live — an orphan branch, GitHub
Pages, a bucket — is the repository's business. So the report is three files
with two placeholders, and the workflow below is the fifteen lines that
finish the job.

## What `--report` emits

```
<dir>/
  comment.md    the verdict in the heading, the viewer link up top, and the
                table of findings folded into a <details> whose rows
                deep-link into the page (`#previews/<entry>`,
                `#scenarios/<flow>/<step>`) — with __MOSAIC_URL__ and
                __VIEWER_URL__ placeholders
  mosaic.png    a grid of the findings (capped at 20), base beside head,
                changed regions boxed — only written when something changed
  web/          the browsable page: viewer, index.json, a PNG per frame.
                Serve over HTTP; file:// cannot fetch its own frames.
```

The page resolves everything against its own URL, so it runs at a bucket root
and under `…/comparisons/42/` alike with nothing to configure. The one host
that needs telling is one that serves a directory without redirecting to a
trailing slash — give it `--base-href=/comparisons/42/`.

## A workflow that hosts on an orphan branch

One self-contained way to do it — raw.githubusercontent serves the mosaic,
and the viewer page goes wherever your static hosting is (the mosaic works
without it; leave `__VIEWER_URL__` pointing at the artifact if you have
none).

```yaml
comparison:
  runs-on: macos-latest        # anywhere `flutter test` runs
  steps:
    - uses: actions/checkout@v4
      with: { fetch-depth: 0 } # the base is the merge base; a shallow clone has none
    - uses: subosito/flutter-action@v2
    - name: Cache the shot cache
      uses: actions/cache@v4
      with:
        path: ~/.flutterware/shots
        key: fw-shots-${{ runner.os }}
    - name: Compare
      run: dart run flutterware compare --report=comparison-report
    - name: Host the images
      run: |
        git checkout --orphan comparison-artifacts || git checkout comparison-artifacts
        mkdir -p pr-${{ github.event.number }}
        cp comparison-report/mosaic.png pr-${{ github.event.number }}/ 2>/dev/null || true
        git add pr-* && git commit -m "comparison for #${{ github.event.number }}" && git push -f origin comparison-artifacts
        git checkout -
    - name: Comment
      env: { GH_TOKEN: ${{ github.token }} }
      run: |
        RAW=https://raw.githubusercontent.com/${{ github.repository }}/comparison-artifacts/pr-${{ github.event.number }}
        sed -e "s|__MOSAIC_URL__|$RAW/mosaic.png|" \
            -e "s|__VIEWER_URL__|${{ steps.pages.outputs.url || 'about:blank' }}|" \
            comparison-report/comment.md > comment.md
        gh pr comment ${{ github.event.number }} --body-file comment.md
```

Adapt freely — the contract is only: substitute the two placeholders, then
post `comment.md`.

## What to know before turning it on

- **The shot cache is the whole performance story, and CI starts cold.**
  Locally the skip rule plus a warm `~/.flutterware/shots` answers most
  entries in milliseconds; a runner without the cache renders *both sides of
  every entry, every run*. Cache `~/.flutterware/shots` (as above) and the
  second run is back to skip-rule speed.
- **`fetch-depth: 0`.** The base is the merge base with the default branch; a
  shallow clone has no common commit and the compare refuses, naming the ref.
- **The viewer page needs real static hosting** (Pages, a bucket). It is a
  Flutter web app: raw.githubusercontent serves the wrong MIME types and a
  downloaded artifact opens on `file://`, and neither can run it. A prefix
  per pull request needs nothing said about it — see `--base-href` above.
- **Updating instead of stacking comments** is `gh pr comment --edit-last`
  (or find-and-update by a marker); the emitted comment is stable enough to
  overwrite.
