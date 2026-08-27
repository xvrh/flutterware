# Store: what is live, and the identity that makes it addressable — design

**Date:** 2026-08-27
**Status:** **Paused, 2026-08-27.** Nothing here is wired to a store and
nothing is being built from it. What landed instead is the half that stands on
its own — the app model of §1, which separates several exports on disk and has
nothing to do with an API. §4a is measured rather than reasoned; §5 is settled
against a rendered mockup (`app/tool/catalog/demos/store_live.dart`).

The reason for the pause is in §4a and §11: every measurement made the lane
larger. Two key kinds with two filename spellings, per-team scoping, multi-key
resolution, a version list whose obvious query returns the wrong release, and
display types that outlive the classes we model — and on Google's side no read
path at all without edit permission. None of it is our complexity, and all of
it would be ours to carry.

**Not in the code:** the identity fields §1 and §2 describe. `bundleId` and
`packageName` were built and then pulled before landing, on the grounds that
published API with no reader is a promise with nothing behind it. Adding a
named parameter to a `const factory` is not breaking, so they cost nothing to
re-add the day this resumes.
**Builds on:** `2026-08-26-store-screenshots-design.md`, whose §11 decision 12
this document half-reverses and whose one-app-per-package model (§2) it
replaces.

The store plugin produces a listing's images and stops there. Everything after
that — is this what is actually on the store, is it stale, did the last release
ship the set we think it did — is answered by opening two web consoles in a
browser and squinting.

This is the lane that answers it in the panel, and it reads before it writes.
Nothing here uploads anything.

## Decisions taken before writing this

Twelve — nine before writing, three from looking at the mockup — and the
first reverses a decision that is three weeks old.

1. **`.itmsp` is dropped.** §11 called it *"the one listing format either store
   has"* and put it in scope with uploading. It is not a format we may target:
   Apple's own Transporter guide says *"Delivering applications using .itmsp
   packages is deprecated"* and, flatly, *"Using .itmsp packages to update app
   content is no longer supported."* What survives is non-app content —
   audiobooks, books, music, video — and app *binaries*, which go through
   Transporter's `-assetFile` rather than through a package.

   So writing one would produce a directory Apple would refuse for the one
   thing we would be writing it for. The half of decision 12 that keeps
   uploading in scope stands; the half that promised a format does not, and
   §5's fastlane tree remains the only interop target there is.

2. **Reading is the first lane, and it is a lane rather than a step toward
   one.** A panel that can show what is live is useful to a project that never
   uploads from here at all — it answers *did the last release ship this* — and
   it is how both API clients get built, credentialed and trusted before
   anything of ours can change a store.

3. **The unit is an app, not a package.** `StoreShots(packages: …)` becomes
   `StoreShots(apps: …)`, and a package may carry several. A project shipping
   two products from one codebase — white-label, or two flavors with two store
   records — cannot express that today, and it is the ordinary case rather than
   an exotic one.

   The change is a rename and one field, because everything that differs
   between two such apps is already the per-package configuration: `file`,
   `frame`, `clock`, `listings`. The unit was always an app. It merely happened
   to be named after the package it was built from.

4. **Identity is declared, never inferred.** Two strings — Apple's bundle id,
   Google's package name — written in `tool/flutterware.dart`.

   Inference was examined and is not merely expensive, it is unavailable.
   Nothing in this repo reads a bundle identifier today: the flavor machinery
   in the icon and splash plugins discovers flavor *names* from directory
   conventions (`flutter_launcher_icons-<flavor>.yaml`,
   `android/app/src/<flavor>/`, `AppIcon-<flavor>.appiconset`) and never opens
   a Gradle file or a pbxproj. Adding that would mean parsing two build
   systems, or shelling to them for seconds, per flavor.

   And then it would still have nothing to choose with, because **this plugin
   never builds**. Pass one runs in `flutter_tester`, which has no flavor, no
   bundle identifier and no native project in the picture. There is no flavor
   in scope to infer *from*. A wrong inference reads — and later writes — a
   different app's listing, which is the worst class of thing to make
   automatic.

5. **Identity lives on `Listing`, not on the app.** The class is already sealed
   with a constructor per store, and its doc comment gives the reason: *"the
   two stores ask different questions."* This is such a question. `bundleId`
   and `packageName` are different fields with different resolution paths, and
   an app that ships to one store only should not carry the other's.

6. **A bundle id, not the numeric App Store Connect app id.** The number is
   stable and saves a lookup per session; it is also opaque, and a wrong one is
   invisible to a human reading the file. The bundle id is verifiable by eye
   against the project, and the lookup that resolves it is one request whose
   failure can name what the key *can* see.

7. **The declaration says where a credential is, never what it is.**
   `tool/flutterware.dart` is committed. Nothing that would be a secret in a
   public repository may be expressible in it, and the identity fields above
   are public precisely so that they can be.

8. **Read-only is a type, not a flag.** The client this ships has no write
   methods on it. Not a `dryRun:` parameter, not a guard — nothing to call by
   accident and nothing to audit. §4 explains why this has to be structural:
   on Play there is no such thing as a read-only credential, so the guarantee
   cannot come from the store and has to come from us.

9. **No `flavor:` field.** It would be documentation with no reader — see
   decision 4. It becomes meaningful the day something here builds, and the
   app's `name` already carries whatever a project wants to call the thing.

### Taken looking at the mockup (2026-08-27)

10. **Pixels get a strip, an absence gets a line.** A ghost promises a thing
    that is coming, so it may not stand for a thing we were refused. §5.
11. **A fact belongs at the level it is true at**, which for most of §4's
    matrix is above the card rather than on it. §5.
12. **Every absence is one short line with a hover card behind it**, and the
    copy is in §5 rather than left to whoever writes the widget.

## 1. The model

### An app is what ships; a package is where the code is

```dart
fw.use(
  StoreShots(
    apps: [
      StoreShotsApp(
        example,
        // name: defaults to the package's name
        file: 'test/scenarios/mobile/shop_test.dart',
        frame: 'lib/store_frame.dart',
        listings: [
          Listing.appStore(
            bundleId: 'com.example.shop',
            locales: {'en': 'en-US', 'fr': 'fr-FR'},
          ),
          Listing.play(
            packageName: 'com.example.shop',
            locales: {'en': 'en-US', 'fr': 'fr-FR'},
          ),
        ],
      ),
      StoreShotsApp(
        example,
        name: 'shop-pro',
        file: 'test/scenarios/mobile/shop_pro_test.dart',
        listings: [
          Listing.appStore(
            bundleId: 'com.example.shop.pro',
            locales: {'en': 'en-US'},
          ),
        ],
      ),
    ],
  ),
);
```

`StoreShotsPackage` becomes `StoreShotsApp`, gains `name`, and the two
identity fields land on the listings. `name` defaults to the package's, so a
one-app project writes no more than it writes today.

**What makes two apps look different is their scenarios**, which is why `file`
is per app and why no other mechanism is needed. Brand B's pixels come from
brand B's scenario file. That is already how the field works.

The identity fields are **optional**. `export` needs neither and continues to
take no arguments — §7's requirement survives untouched. They are required by
the actions in §6, and their absence is a refusal that names the line to add.

### What a second app costs downstream

Mechanical, and all of it in one direction:

| | today | with apps |
| --- | --- | --- |
| tree | `<output>/ios/…` | `<output>/<app>/ios/…` |
| narrowing | `--listing --locale --class --shot` | `+ --app` |
| report key | `store/class/appLocale` | `app/store/class/appLocale` |
| panel | a sub-entry per package | a sub-entry per app |

The app level appears **always**, including for a single app, rather than only
when there are two. A tree whose depth depends on how many things are in it is
a tree every consumer has to branch on, and §5's replace rule would need two
spellings. A project pointing `--output` at a fastlane metadata directory
narrows with `--app` and gets the shape `deliver` expects underneath.

`StoreShotsSet` gains `app` and `storeShotsReportVersion` goes to 2. The gate
does its job: a reader built before this says *nothing exported* rather than
decoding half a listing. Nothing has shipped, so it costs nobody a migration —
what it buys is that yesterday's local export reads as *nothing exported*
rather than as a listing belonging to an app called `null`.

### Three things building it changed (2026-08-27)

**The manifest stays per app, not one file over all of them.** This document
had one manifest at the root with `app` on each set. It cannot be: an app's
`output:` is its own, so two apps can sit under two unrelated roots and there
is no shared directory to put a joint file in. Per-app is also what the plugin
already did per package, and `StoreShotsReport.read` already takes a directory.
`app` stays on the set — a script that reads two exports and puts them in one
list would otherwise have nothing to tell them apart by — and so does the app
in `key`, so that list behaves if anyone builds it.

**`--output` names a root, and the app's segment is still under it.** The draft
implied a narrowed `--app --output` would land the tree bare, which is the
conditional shape §1 argues against everywhere else. It is one rule instead:
the app is always the last segment, of the default, of a declared `output:`,
and of a redirect. It also fixes something that predates this — two *packages*
redirected to one `--output` used to write over each other.

**Two apps on one package need two build directories.** They are two scenario
files and therefore two dills, and the runners are cached and long-lived, so a
shared `build/flutterware/store_harness` is the tear the comparison lane
already paid for once. It would not even have taken two exports at the same
time. Now `store_harness/<name>`.

Also settled, having looked: nothing validates `PluginPackage.path` for
duplicates, so two apps sharing a package pass the framework's join untouched.

## 2. Identity, and the lookup behind it

What the declaration carries, what we find ourselves, and what is resolved over
the wire:

| | App Store | Google Play |
| --- | --- | --- |
| app identity | declared `bundleId` | declared `packageName` |
| internal id | resolved — `GET /v1/apps?filter[bundleId]=`, cached per session | none; `packageName` is the id |
| which version | resolved — `appStoreVersions` | n/a, a listing is not versioned |
| the sets | `appStoreVersionLocalizations` → `appScreenshotSets` (by `screenshotDisplayType`) → `appScreenshots` | `edits.insert` → `edits.images.list(language, imageType)` → discard |
| pixels | `imageAsset.templateUrl` | each image's `url`, plus `sha1`/`sha256` |
| locale slot | declared, already | declared, already |
| class → store slot | derived from `AppStoreClass` | derived from `PlayClass` |

Two strings per app per store, both public. Everything else is already
declared, derived from an enum, discovered on disk, or asked of the store.

Both are optional and both are `null` until a project says otherwise —
`Listing.identity` reads whichever of the two its store asks for, and
`identityLabel` names it for a refusal. An export needs neither.

## 3. Credentials

### Apple: an individual key needs nothing declared at all

App Store Connect issues two kinds of key, and the difference decides this
whole section. A **team key** is generated by an Admin, covers every app in the
team regardless of its role, and its JWT carries an `iss` claim — the team's
issuer id. An **individual key** is generated by a developer from their own
profile, inherits that person's role and their per-app restrictions, and its
JWT carries **no issuer at all**: `sub: "user"`, `aud: "appstoreconnect-v1"`,
`exp`, with the key id in the header.

So for an individual key the entire credential is one file, and the key id is
in its name — `AuthKey_<keyId>.p8`. Dropped into a directory Apple's own tools
already look in, there is nothing left to configure:

```
~/.appstoreconnect/private_keys/     the convention altool, notarytool and
~/.private_keys/                     fastlane all honour, in this order
./private_keys/
```

Matching `(AuthKey|ApiKey)_<id>.p8`, and **both spellings are load-bearing** —
Apple downloads a team key as `AuthKey` and an individual one as `ApiKey`. See
§4a, where globbing only the first was the mistake this section shipped.

That is the answer to *how does every developer who has access get set up*: they
generate their own key, download it once, and drop it in. Nothing per-developer
ever reaches the committed file — which it could not anyway, since with
individual keys the key id **is** per-developer.

**One key is one team**, measured in §4a. Somebody working across several has
several keys in that directory, so the resolver tries each against the declared
bundle id rather than taking the first it finds — and the trace says which one
answered.

Two consequences worth stating: the filename is load-bearing, so the
documentation has to say do not rename it; and the **Marketing** role is enough
to read and manage screenshots, so a designer can be given this lane without
being given the ability to ship anything.

A team key is the only case with something to declare, and it is a
non-secret UUID. Read `APP_STORE_CONNECT_ISSUER_ID` first; allow it in the
declaration for a project that prefers it visible.

Individual keys cannot reach provisioning, sales, or notarization. None of
that is wanted here.

### Google: a path, and no shortcut

A service-account JSON, resolved from `GOOGLE_APPLICATION_CREDENTIALS` or
`SUPPLY_JSON_KEY`. It is created in Google Cloud and granted in the Play
Console, and it belongs to the *account* rather than to a person — the opposite
of Apple's individual key, and there is no version of it that is per-developer
without an administrator making one each.

The alternative is a user OAuth flow, which would mean shipping a client id
and submitting flutterware to Google's verification for a sensitive scope. Not
worth it. Accept the asymmetry and say so in the panel rather than pretending
the two stores are alike.

### The rules, in one place

- **A path may be asked for. A value may not.** No secret is typed into a
  field, stored by us, printed, written to the run journal, or returned in an
  MCP reply.
- **The panel shows the resolution, not the outcome.** Which sources were
  tried, in order, and which answered. *Why can it not see my key* is the
  failure this lane will actually produce, and it should diagnose itself the
  way the run plugin's refusals teach rather than saying "not configured".
- **Nothing is cached to disk by us.** A JWT lives for its 20 minutes in
  memory; a resolved app id lives for the session.

## 4. What "live" is, and it differs by store

### Apple has a real read-only lane, and two answers

Screenshots hang off an `appStoreVersionLocalization`, which hangs off an
`appStoreVersion`. There are two versions in flight at any time — the one
people can download, and the editable one being prepared — so *what is live*
and *what is about to be* are different questions with different answers, and
both are plain GETs. Nothing is created to look.

Which gives the panel three columns it can fill honestly: **live**, **draft**,
and what the last export wrote.

Images come back as an `imageAsset` carrying a `templateUrl` — a CDN URL with
size and format placeholders — so live pixels can be shown beside ours rather
than merely counted. Confirmed against a real listing: see §4a.

### Google has neither

There is no listing read outside an edit. `edits.insert` creates a draft
populated from the app's current state, `edits.listings.list` and
`edits.images.list` read it, and we never commit — the edit expires on its own,
and is deleted explicitly anyway.

And the permission this needs is not a read permission. *View app information
and download bulk reports (read-only)* cannot call `edits.insert`; that
requires edit-level access. **On Play, the ability to look is the ability to
change**, which is decision 8's whole argument: the read-only guarantee cannot
be delegated to the credential, so it is a type with no write methods on it.

One thing Play gives that Apple does not: `edits.images.list` returns `sha1`
and `sha256`, so *identical* and *differs* are free and true. Apple's CDN
re-encodes, so the same claim on that side would be a lie — the App Store
column may say what is there and how much of it, never whether it matches.

## 4a. What the API actually says, measured 2026-08-27

Read-only reconnaissance against a real team — a published app with three
localizations and several years of history. Every request was a GET. Six
findings, and two of them contradict this document.

### The key's kind is in its filename, and §3's glob had it wrong

Apple names the two kinds differently, and **an individual key is not called
`AuthKey`**:

| downloaded as | kind | token |
| --- | --- | --- |
| `AuthKey_<id>.p8` | team | `iss: <issuer>` |
| `ApiKey_<id>.p8` | individual | `sub: "user"`, no issuer |

§3 said to glob `AuthKey_*.p8`, which would have found no individual key at
all — the path this document recommends as the primary one. The resolver
matches `(AuthKey|ApiKey)_([A-Z0-9]+)\.p8`.

The prefix also predicts the token shape reliably: signed the wrong way round,
each key is refused with a clean `401 NOT_AUTHORIZED` and nothing else. So the
kind can be read off the name and confirmed by one request, rather than
declared.

**Neither is Apple's own naming honoured elsewhere.** One of the two keys
tested had been renamed with a leading underscore, and `altool`, `notarytool`
and fastlane all match the name exactly — so that file was invisible to every
one of them while ours found it. Lenient, and say so: *using
`_AuthKey_XXXXXXXXXX.p8` — Apple's own tools expect `AuthKey_XXXXXXXXXX.p8`.*

### An individual key is scoped to one team

Its owner belongs to several. Asked for `/v1/apps` it returned exactly the four
apps of the team it was generated in — the same four the team key of that team
returns, no more.

So §3's zero-config story survives, with one correction: a person in several
teams has **several individual keys**, and the resolver cannot glob one and
stop. It has to try each against the declared bundle id and say which answered.
Which is what §3's resolution trace was already for.

### Both version-state attributes exist, and both are populated

The same `appStoreVersion` carries `appStoreState: READY_FOR_SALE` — the
deprecated one — and `appVersionState: READY_FOR_DISTRIBUTION` beside it. Read
the second. §11's open question is closed.

### The live version is not *the one in that state*

`appStoreVersions` returns **every version the app has ever shipped**, and they
all read `READY_FOR_DISTRIBUTION`. Filtering by state gives a list, not an
answer, and taking the first of it is a coin toss between this release and one
from two years ago.

Not a detail: it is the difference between showing the current listing and
showing an old one, and nothing on screen would say which. Phase 2 has to
establish the right query — a sort, a limit, or a relationship on the app that
names the current version — and prove it against an app with history.

### `templateUrl` is real, and it fetches

The shape is `…/pr_source.png/{w}x{h}bb.{f}`, with the placeholders spelled
exactly `{w}`, `{h}` and `{f}` and the `bb` baked into the path. Substituting
the asset's own width, height and `png` returned `200 image/png`, 657 KB, with
no authentication on the request at all.

So the panel can show live pixels beside ours. §5's live strip is buildable.

`assetDeliveryState` is an object rather than a string —
`{state: COMPLETE, errors: [], warnings: null}`.

### A real listing has display types we do not declare, and this is normal

The sets came back as `APP_IPHONE_58` and `APP_IPHONE_55` — the 5.8" and 5.5"
families. Apple keeps historical display types on a listing indefinitely, and
this one predates the 2024 change that made two sizes sufficient.

So `screenshotDisplayType` is a much larger vocabulary than our two classes,
and **a live listing carrying sets a project does not declare is the ordinary
case rather than the exception**. §5 already says an undeclared live set is
shown and never reconciled; this is the evidence that the rule earns its
keep rather than covering an edge.

## 5. What the panel shows

Settled by rendering it, 2026-08-27. The mockup is
`app/tool/catalog/demos/store_live.dart`, group **Store live** — four candidate
layouts, ten per-set states and the levels above them, all painted, no
credential involved. The set card came out of `store_plugin.dart` into
`app/lib/src/store/ui/set_card.dart` to make that possible.

### Pixels get a strip. An absence gets a line.

Three layouts were drawn — the store's set as a second, shorter strip under
ours; one strip with a Local/Live switch in the header; a line under the card
with the pixels behind a third dialog. All three are fine when the store
answered, which is why none of them won on its own.

**The state matrix decided it.** Under a second strip, five states draw the
same picture: not checked, nothing published in that slot, no credential, the
key cannot see this app, and the key was refused. A ghost strip and a different
sentence over it, five times.

And for three of them the ghosts are a **lie**. A dashed canvas means *this
will fill* — which is the local strip's whole argument, and it is true of a
slot the store has and empty, and false of one nobody let us look at.

So the rule, rather than a layout:

| the store | the card |
| --- | --- |
| answered, with screenshots | a second strip, at 62% of the export's height |
| answered, the slot is empty | a second strip of ghosts — the slot is real and will fill |
| did not answer, for any reason | no strip: one line under the export's |

Two things fall out of it without being asked for. A set that has never been
checked loses the `THIS EXPORT` label, because with one strip there is nothing
to tell apart. And **a card grows nothing until it has something to put on it**
— an app with no identity declared draws exactly today's card, which is the
property being protected: a project that does not use this lane never learns it
exists.

### A fact belongs at the level it is true at

Only the bottom of §4's matrix is per-set. Today every message on this panel is
on a card because every fact it had was per-set; a missing credential put there
prints the same apology four times on one screen.

| level | where it is said |
| --- | --- |
| account — no credential, refused, connected | the panel header's summary line, one clause per store |
| app — no identity declared | the header, as an offer, with the Check stores button absent |
| listing — no record in that store yet | beside the store's own heading, cards below unchanged |
| set — never exported, never checked, empty, denied | the card |

The summary line grows a clause per store and stays one line:
`exported 4 days ago · App Store checked just now · Google Play not connected`.

### An absence somebody chose is an offer, not a warning

Three tones, and the card already has the machinery for the last two:

- **neutral** — not declared, not exported, not checked, not connected. Nobody
  has failed at anything; the line says what would fill the gap.
- **amber** — a fact about access rather than a fault: this key cannot see this
  app, Play wants edit permission.
- **red**, and the only red on the panel — something that was set up has
  stopped working: a key that was found and refused.

### Every absence is a short line, with the long answer behind it

Two audiences and one line cannot serve both: somebody scanning four cards
needs to know *whether* there is a problem, somebody who has found one needs
the path, the permission or the fix. Putting both on the card makes the line
unscannable and still leaves the detail too cramped to hold a file path.

So the card carries a sentence and hovering carries the rest, on the house
`HoverCard` rather than a `Tooltip`: the detail runs to two lines, often wants
a path in it, and a tooltip that long is a wall that vanishes when you move to
read it. A small `?` after the line is the affordance — a hover target that
looks like prose is a hover target nobody hovers.

The copy, which is part of the design and not a detail of it:

| line | hovering |
| --- | --- |
| Not exported yet. | Export runs your scenarios on an iPhone 16 Pro Max and saves every shot you named, at 1320 × 2868. |
| Not checked. | Nobody has asked the App Store what it is showing. Checking only reads the listing — it cannot change it. |
| Nothing published here. | The app is on the App Store, but this size and this language have no screenshots on it yet. |
| No App Store key on this Mac. | Create a key in App Store Connect under your own profile, then save it as `~/.appstoreconnect/private_keys/AuthKey_XXXXX.p8`. It only reaches the apps you can already see. |
| This key cannot see com.example.shop. | The key works — it just has no access to this app. It can see com.example.brew and com.example.pos. |
| The App Store refused the key. | The key was found but not accepted. It may have been revoked, or the file may not match the key id in its name. |
| Google Play needs edit access. | Reading a Play listing opens a draft edit that we throw away, and view-only permission cannot open one. Ask for release access on this app. |

Two rules the table is written to. **Name the thing that is missing, not the
state of the machine** — *No App Store key on this Mac* rather than *not
configured*. And **the hover ends with what to do**, or with the fact that
makes the next step obvious: which apps the key can see, which permission to
ask for, where the file goes.

### The rest of it

- The header says **which version it read** — `1.4.2 · Ready for Distribution`
  — because on Apple that is a real choice and an unlabelled column is a guess.
- **Comparison is by position within the set, never by content.** Decision 1 of
  the screenshots design holds: we show what is there and the eye judges. Play's
  checksums are the one place a stronger word is available, offered as a fact
  about two files rather than as a verdict about a listing.
- A locale live in the store that the declaration does not name is **shown, not
  reconciled**. The report's asymmetry is deliberate and this must not undo it.
- **Live is a state the panel enters**, not one it always shows: a *Check
  stores* action beside Export. Opening a panel to look at your own screenshots
  must not call two APIs.
- Live pixels are fetched **lazily, for the locale on screen**.

## 6. The actions

```sh
fw run store live            # what the stores have, per app, per listing
fw run store live --app=…    # narrowing, like every other override
```

Narrowing only, per §7's rule, and the same set: `--app`, `--listing`,
`--locale`, `--class`. Over MCP the same, plus the panel projection through
`flutterware_status`.

`live` never writes to a store and never writes to the export tree. It is
readable output and a panel, and nothing on disk changes.

## 7. Refusals

Each of these is a sentence a person can act on, and the last two are the ones
that will actually be hit. **The wording is §5's table**, not something to
reinvent at the call site — the panel and the CLI say the same thing, and the
CLI simply prints both halves:

- **No identity declared.** Names the app, the store, and the exact line to
  add.
- **No credential found.** Lists every location tried, in order, with what was
  at each — this is the resolution trace of §3, and it is the refusal, not a
  detail behind it.
- **The bundle id is not visible to this key.** Lists what the key *can* see.
  With individual keys this is usually the truth rather than a typo: the person
  has access to a different subset than they expected.
- **Play returned 403 on `edits.insert`.** Says that reading a Play listing
  requires edit-level access and that read-only permission is not enough — the
  API's error will not say this, and nobody guesses it.

## 8. Testing

No test touches a network. Both clients take a transport, and the suites feed
recorded response shapes:

- **`store_identity_test.dart`** — the declaration: two apps on one package,
  the tree they produce, `--app` narrowing and its replace scope, report v2
  round-trip and the v1 refusal.
- **`store_credentials_test.dart`** — resolution order per store, the trace a
  failure produces, an individual key's JWT carrying no `iss` and a team key's
  carrying one, key id read off the filename.
- **`store_live_test.dart`** — the Apple walk against fixtures, the Play
  walk including the discarded edit, and both refusals above.

The one thing tests cannot cover is whether the shapes are right, which is
what phase 2's first hour is for.

## 9. Phases

1. **The app model.** Declaration, tree, `--app`, report v2, panel grouping.
   No network, no credentials, nothing new to trust — and it is a prerequisite
   for every later phase, since a listing has to be addressable before it can
   be looked up.
2. **Apple, counts.** Credential resolution and its trace, the JWT, the app
   lookup, versions, sets. The panel gains a live column with counts. First
   hour of this phase settles `templateUrl` and which version-state attribute
   to read.
3. **Apple, pixels.** The live image beside ours in the shot dialog.
4. **Play.** The discarded edit, images, checksums, and the 403 refusal.
5. **Upload.** Not designed here — see §10.

## 10. Not in this, and why

- **Uploading.** Still v2 rather than never, on decision 12's surviving
  argument. It wants its own document, and it wants this one built first: the
  reservation dance Apple's screenshots need is per-image and **not
  transactional**, so a failure halfway leaves a half-replaced set, while
  Google's edit is all-or-nothing. That asymmetry is the design, and it is not
  worth designing before something here can read what a failure left behind.
- **Metadata and copy.** Description, keywords, what's new. The screenshots
  design declined a copy system on purpose (its decision 6); pushing copy would
  drag it back in through the side door.
- **The binary.** TestFlight and Play tracks are a different plugin, and the
  proportions are the argument: in an existing Dart implementation of both
  upload paths, the store-facing code is under 150 lines and the build,
  keychain, provisioning and archive machinery around it is more than ten times
  that. flutterware builds no release artifact at all today. That is a product
  decision to take on its own terms, not a flag on a screenshot exporter.
- **Alt text.** §11 defers it on the grounds that Play accepts a
  140-character per-screenshot string and that `supply` carries it. **That claim
  did not survive checking**: `edits.images` carries `id`, `url`, `sha1` and
  `sha256` and nothing else, and `supply`'s documentation does not mention it.
  Before the deferral is honoured, somebody has to establish that the field
  exists.

## 11. Still open

1. **Does the panel show Apple's draft version, or only what is live?** Three
   columns is more truthful and is a lot of panel. Leaning live-only for phase
   2, with the draft arriving if anybody asks what changed before a release.
2. **Play's permission ask.** Requesting edit-level access to *look* is a real
   thing to ask an administrator for. An honest alternative is to ship App
   Store first and let Play arrive with the write lane, where the permission
   is proportionate.
3. **A team key's issuer id in the declaration, or env only?** Env only is
   cleaner and one more thing to set up.
4. **Two listings of the same store for one app.** A single app with two App
   Store records is still not expressible. Where it would go: `listings` keyed
   by name, and a level in the tree. Waiting for somebody to ask.
5. **`StoreShotsApp.clock` is not in the declaration above**, and its absence is
   deliberate but is not this document's to settle — the scenario clock defaults
   to the wall clock, three consumers pin it independently, and only the store
   plugin makes a user type it. Being cleaned up separately.
