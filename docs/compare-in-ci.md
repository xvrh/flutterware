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

One self-contained way to do it, on stock GitHub and nothing else. An orphan
branch holds the files; raw.githubusercontent serves the **mosaic** and
GitHub Pages serves the **viewer** from that same branch. Two hosts on
purpose: the viewer is a Flutter web app and raw serves scripts as
`text/plain` with nosniff, which browsers refuse — while Pages takes a
minute to build after a push, which the click on "Open the full comparison"
can afford and the inline image cannot.

One-time setup: Settings → Pages → deploy from a branch →
`comparison-artifacts`, `/ (root)`.

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
    - name: Host the report
      env: { PR: ${{ github.event.number }} }
      run: |
        git fetch origin comparison-artifacts:comparison-artifacts 2>/dev/null \
          && git worktree add site comparison-artifacts \
          || git worktree add --orphan -b comparison-artifacts site
        rm -rf "site/pr-$PR" && mkdir -p "site/pr-$PR"
        cp comparison-report/mosaic.png "site/pr-$PR/" 2>/dev/null || true
        cp -R comparison-report/web "site/pr-$PR/web"
        git -C site add -A
        git -C site -c user.name=fw-compare -c user.email=fw-compare@invalid \
          commit -q -m "comparison for #$PR" || true
        git -C site push origin comparison-artifacts
    - name: Comment
      env:
        GH_TOKEN: ${{ github.token }}
        PR: ${{ github.event.number }}
      run: |
        RAW=https://raw.githubusercontent.com/${{ github.repository }}/comparison-artifacts/pr-$PR
        PAGES=https://${{ github.repository_owner }}.github.io/${{ github.event.repository.name }}
        # `g` matters: a scenario row carries two viewer links on one line.
        sed -e "s|__MOSAIC_URL__|$RAW/mosaic.png|g" \
            -e "s|__VIEWER_URL__|$PAGES/pr-$PR/web/|g" \
            comparison-report/comment.md > comment.md
        # One comment per PR, updated in place — found again by its marker.
        id=$(gh api "repos/${{ github.repository }}/issues/$PR/comments" \
          --jq '[.[] | select(.body | startswith("<!-- fw-compare -->"))][0].id // empty')
        if [ -n "$id" ]; then
          gh api -X PATCH "repos/${{ github.repository }}/issues/comments/$id" -F body=@comment.md
        else
          gh pr comment "$PR" --body-file comment.md
        fi
```

Adapt freely — the contract is only: substitute the two placeholders
everywhere they appear (`sed …g` — `__VIEWER_URL__` is once per table row),
then post `comment.md`. The comment's first line is `<!-- fw-compare -->`
precisely so a workflow can find its own comment and update it rather than
stack a new one per push; the footer's `@<sha>` says which push the report
still describes.

## Several packages, one comment

`fw compare` covers **every** package either half declares — previews in
`app` and `packages/gallery`, scenarios in `app` and `packages/notes` — and
writes one `index.json`, one `comment.md` and one page for all of them. There
is nothing to configure and no reason to run it once per package; doing so
would produce a comment each, and each run would overwrite the last one's
artifact.

`--package=` narrows, and it is repeatable:

```sh
dart run flutterware compare --package=app --package=packages/notes
```

Two things change in the output when a run covers more than one package, and
nothing changes when it covers one:

- **A row's id carries its package** — `packages/gallery/demo/card.dart#card`,
  which is the file's path plus the name it was declared under. Without it two
  packages that both declare `demo/card.dart#card` are one row.
- **A row also carries a `package` field**, recorded whether or not the id was
  qualified, so a script over `index.json` never has to take an id apart.

A package whose catalog or harness will not compile against the base is one
package's worth of silence, not the end of the run: the others still report,
the half records a note naming the package and the compiler's output, and the
comment leads with **no verdict** so the failure cannot read as a pass. `fw
compare` still exits non-zero. When it is the *only* package, it is still the
whole comparison — the command prints the diagnostics and exits 64.

Packages are compared one at a time. Each is two `frontend_server`s and two
guests, and a runner sized for one build will not hold four of those at once;
since the scenario half stopped building harnesses it does not need, a package
a branch did not touch costs milliseconds anyway.

## What to know before turning it on

- **The shot cache is the whole performance story, and CI starts cold.**
  Locally the skip rule plus a warm `~/.flutterware/shots` answers most
  entries in milliseconds; a runner without the cache renders *both sides of
  every entry, every run*. Cache `~/.flutterware/shots` (as above) and the
  second run is back to skip-rule speed.
- **`fetch-depth: 0`.** The base is the merge base with the default branch; a
  shallow clone has no common commit and the compare refuses, naming the ref.
- **The very first comment of a repository may briefly 404 its page link**:
  Pages builds after the push, in about a minute. Every later run updates a
  site that already exists. A downloaded artifact opens on `file://`, which
  cannot run the page — it has to be served, and the branch is the serving.
- **Old directories are just directories.** A closed pull request's `pr-N/`
  on the branch is linked by nothing; delete whenever the branch feels heavy.
