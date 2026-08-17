# Running asset transformers in the catalog's bundle

**Date:** 2026-08-17
**Status:** Design. The reporting half shipped 2026-07-30; this is the execution
half the spike deferred.
**Follows:** `2026-07-30-asset-transformers-spike.md`, which costed this and
closed with *"execution waits for a project that needs it."*

## The project arrived

A consumer migrating a real single-app project from v1 hit it as the first of
two blocking findings. Their pubspec declares five asset directories through
`vector_graphics_compiler` and ships 21 SVGs; at run time the app loads them
with `VectorGraphic(loader: AssetBytesLoader(path))`, which needs the compiled
bytes. The catalog serves the source, so the loader gets raw SVG and draws
nothing.

**They are not worked around.** The app carries a fallback written long before
flutterware:

```dart
bool get _isTestEnvironment => WidgetsBinding.instance is! WidgetsFlutterBinding;
if (_isTestEnvironment) return SvgPicture.asset(path, …);  // parse the source
return VectorGraphic(loader: AssetBytesLoader(path), …);   // decode the output
```

The previews guest is a real engine with a real `WidgetsFlutterBinding`, so this
never fires there. It compensates for `flutter test`, and the panel is the one
environment it does not reach.

**It is a third of their catalog, not two entries.** 13 of their 37
preview-bearing files reference a widget that draws a vector — every onboarding
page, the profile and activities screens, login, the mascots, the rewards, the
building illustrations. That is the illustration-heavy end of a catalog, which
is the end a preview tool exists for.

**And every surface calls it healthy.** The preview renders blank; `previews
audit` reports it fine; `previews inspect` reports `ok: true, errors: []`; and
`assets audit` reports five findings against *their* declarations, under the
slug `declared-missing`, exiting 1 — so they dropped that job rather than run it
permanently red. The reader is told their widget is wrong, which is the most
expensive wrong answer a preview tool can give.

The one asymmetry worth knowing: `previews build-web` is already correct. It
shells out to `flutter build web`, which runs the real asset pipeline. So the
exported page renders what the app renders and the panel does not.

## What it costs, measured

On the consumer's own 21 SVGs, `vector_graphics_compiler`, M-series macOS.
Numbers include `fvm` process overhead the real implementation would not pay.

| | wall clock |
|---|---|
| one file, cold | 0.45s |
| 21 files, one process each, sequential | 7.66s (~365ms each) |
| 21 files, one process, `--input-dir` | 0.89s (405% CPU) |

This agrees with the spike: the cost is process startup, not transformation.
Pooled four ways the way `flutter_tools`' own `DevelopmentAssetTransformer`
pools, 21 assets land at roughly 1.9s — **paid once**, because the cache below
makes an unchanged asset never pay again. An edited SVG costs one invocation.

`--input-dir` is a flag of that one package, not part of the contract, so the
design does not lean on it. It is recorded because it shows where the headroom
is if a project ever turns out to have hundreds of transformed assets.

**`dart run <package>` is the invocation, and it is the fast one** — which is
the opposite of what this note first assumed. `dart run` was expected to cost
the package-graph re-resolution the dev-stack `StackRun.script` change measured,
so spawning the resolved `bin/<name>.dart` directly looked like the saving.
Alternated five times each, one asset, SDK `dart` (no `fvm` in the path):

| | wall clock |
|---|---|
| `dart run vector_graphics_compiler …` | 0.17 / 0.13 / 0.12 / 0.12 / 0.12 |
| `dart --packages=… <pubcache>/bin/….dart …` | 0.92 / 0.85 / 0.84 / 0.86 / 0.86 |

**Seven times faster, because pub precompiles executables.** `.dart_tool/pub/
bin/<package>/<name>.dart-<sdk>.snapshot` is what `dart run` executes; spawning
the source recompiles it on every asset. The snapshot is keyed by SDK version,
so a project resolved under a different SDK pays one ~0.9s recompile and is warm
after. Output byte-identical either way.

So the contract's invocation is also the right one, and the per-asset cost is
**~0.12s** rather than the 0.365s above — that figure was `fvm`'s overhead, not
the transformer's. 21 assets sequential is ~2.5s, pooled four ways ~0.7s, paid
once.

**The output is exactly the tool's.** All 21 were compiled both ways — the
per-file `--input`/`--output` invocation `flutter_tools` uses, and the batch —
and compared byte for byte: 21 identical, 0 differing. So this is not
approximating what the app ships; it is the same compiler, the same arguments,
the same bytes.

## Two of the three deferred risks do not exist

The spike listed depfile invalidation, `FLUTTER_BUILD_MODE`, and failure
surfacing as the costs that are not milliseconds. Against the transformer that
actually turned up:

- **`FLUTTER_BUILD_MODE`.** `vector_graphics_compiler` never reads
  `Platform.environment` at all. Its output is a pure function of the input
  bytes and the arguments, so the guest being a debug build changes nothing. The
  variable is still passed, because matching the tool's invocation is what makes
  the bytes match for a transformer we have not read.
- **Depfiles.** It writes none. Invalidation is the input file's bytes, which
  the content-addressed cache already keys on. Honouring a `<output>.d` when one
  appears stays on the list, but it is additive rather than a precondition.
- **Failure surfacing.** Real, and the one genuine cost. Below.

## The shape

Three parts, and the third one already exists in this file.

**1. The catalog carries the chain.** `AssetCatalog` parses `transformers:`
today only to file a problem; it drops the arguments and keeps no link from a
resolved file to the transformers that apply to it. `AssetDeclaration` gains the
chain — package plus args, in order — and a resolved file can reach its
declaration's. Parsing only, so `resolve` stays inside `computeAll`'s budget and
every surface can go on calling it freely.

**2. A content-addressed cache.** Transformed payloads cannot be symlinks to the
source, so they are produced under
`~/.flutterware/transformed/<hash>` and the bundle entry links *that*.

The key is sha1 over: the input bytes, and for each transformer in the chain its
resolved package root and its arguments. **The package root rather than the
package name** — a hosted root is `…/vector_graphics_compiler-1.2.6/`, so a
consumer bumping the compiler changes the key for free, which a name would not.
The bytes rather than the mtime, so a checkout that rewrites a file to its own
content does not recompile the world.

Cached outside the project, beside the shader cache, for the reason the shader
cache is: it is a pure function of its inputs, so two worktrees of one repository
share every hit, and it survives a `build/` that someone deleted.

**3. `_link` points at the output.** `AssetBundleBuilder._linkPayloads` links
`file.path` today. For a file with a chain it links the cached output instead.
Everything downstream — the manifests, the pruning, the in-place update, the
`changed` flag that decides whether a running guest is told to evict — is
untouched, because the builder's whole job was already "decide a target for each
key" and this only changes the target for some of them.

**The precedent is `_linkCompiledShaders`, in the same class.** It compiles the
framework's `.frag` sources with the tool's exact `impellerc` invocation, caches
per engine revision, and links the compiled artefact — because
`FragmentProgram.fromAsset` parses compiled bytes and throws on source. That is
this problem exactly, for a payload we did not choose. Transformers are the same
mechanism for payloads the project chose.

The `dart` that runs a transformer is `cache.dart`, the SDK's own — never a bare
`dart`, which `test/ambient_sdk_test.dart` fails the build over.

## The consequence that is not obvious

**Fixing this changes what the audit lane serves, and that can break an app
that was compensating.**

`previews audit` renders under `flutter_tester` through `TesterHost`, which syncs
its assets with the same `AssetBundleBuilder`. So the audit reads whatever the
guest reads. Today that is untransformed source, and the consumer's fallback
handles it — `TestWidgetsFlutterBinding` extends `BindingBase`, not
`WidgetsFlutterBinding`, so `_isTestEnvironment` is true and `flutter_svg`
parses the source successfully. That lane currently works *because* the bundle
is wrong in the way their branch expects.

Serve transformed bytes and that branch hands compiled binary to an XML parser.
The audit lane goes from working to broken for exactly the projects this change
is meant to help.

Nor can they fix it by narrowing the boolean, because after this change one
binding kind means two different bundles: plain `flutter test` still has
untransformed assets, and flutterware's audit does not. A single
`is! WidgetsFlutterBinding` cannot separate them.

The end state is right — one code path in the app, correct bytes on every
flutterware surface, no environment-conditional rendering — but it is reached by
the consumer deleting a branch, not by the change landing silently. So:

- the changelog entry says it plainly, naming the shape of the code that breaks
  rather than only the improvement;
- the transformed bundle is not a surprise a project discovers at run time. The
  assets panel says which keys are served transformed, and by what.

An alternative considered and rejected: transform only the guest's bundle and
leave the audit's untransformed. It keeps the branch working, and it costs the
property the audit exists for — the two lanes' rows are comparable because they
mount the same tree over the same bytes. Two bundles is two answers to "does
this catalog render", and the one the CI job trusts would be the one further
from the app.

## What a failure becomes

`AssetProblemKind.unsupportedTransformer` is a standing accusation today: it
fires on a correct declaration, says the catalog does not run it, and flips
`ok`. Once the catalog runs it, that problem has nothing to describe and goes.

What replaces it is narrower and genuinely the project's business: a transformer
that **failed** — a non-zero exit, or an output file that is not there. Reported
per declaration with the process's own stderr, and flipping `ok`, because a
bundle whose bytes did not get produced is a broken bundle. `fw run assets
audit` becomes wireable into CI for a project with transformers, which is what
the consumer wanted and could not have.

There is one residual for a transformer we never run — one whose package is not
resolvable, say. That keeps a report, and it keeps a slug that says what it is:
`untransformed`, not `declared-missing`. Nothing is missing in either case, and
the current slug sends the reader to look for a file that is right there.

## Deliberately not in this

- **`flavors:` on an asset entry, and `.lottie` archives.** Both still absent
  rather than half-done, as `AssetCatalog`'s dartdoc says.
- **Making plain `flutter test` correct.** Out of reach and out of scope; it is
  the deficiency the consumer's branch exists for, and it stays.
- **A transform on the inspector's read path.** The asset inspector reports what
  a key resolves to; it does not decode. A transformed key's *size* changes,
  which the inspector should read from the cached output rather than the source,
  but that is a follow-on and not what unblocks anybody.

## Open, to settle before building

1. **Where the pool's width comes from.** Four, because the tool uses four; or
   the core count, which is what the one transformer we have measured picks for
   itself.
2. **Whether a transform failure quarantines the entry or the bundle.** The
   compiler daemon quarantines a preview that will not build so the rest still
   serve. The equivalent here — link the source, report the failure, let the
   rest of the catalog render — is friendlier and is also how the blank icon got
   shipped in the first place. Leaning towards failing the sync loudly instead.
