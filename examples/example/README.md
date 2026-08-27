# flutterware_example

flutterware's sample project. It exists to be *looked at* by the tools in
`app/` — the asset inspector, the launcher-icon viewer, the previews catalog,
the scenario runner — so a fair amount of what is in here is fixture rather
than app.

**Several fixtures are wrong on purpose.** Fixing one breaks the case it stands
for. What each is meant to expose is written down beside it:

- `assets/README.md` — the asset inspector's fixtures.
- The rest of this file — the launcher icon's.

## Icon sets

The viewer calls the row above the plates **icon sets** rather than flavors,
and this project is why. A set is discovered from files — a
`flutter_launcher_icons-<name>.yaml`, an `android/app/src/<name>/`, an
`AppIcon-<name>.appiconset` — which is the generator's convention and not a
rule of Gradle or Xcode. A project that writes its own wiring can put those two
lists badly out of step, and both directions are here.

| set | what names it | what it exposes |
|---|---|---|
| *(none)* | `android/app/src/main/res/`, `AppIcon.appiconset` | the unflavored set every other one falls back to |
| `beta` | `flutter_launcher_icons-beta.yaml` alone | configured and never generated — the `· not generated` chip, and a panel where every file is inherited |
| `kiosk` | `android/app/src/kiosk/res/` alone | **a partial override**: one density of one role. Gradle merges the rest, so the plate reads `192×192 · 5 densities · 4 not overridden`, and the adaptive icon and background colour are main's |
| `partner` | `AppIcon-partner.appiconset` alone | an iOS-only set: Xcode uses it, and Android builds with main's icons entirely |
| `pro` | `android/app/src/pro/res/` + `AppIcon-pro.appiconset` | a complete set — and **not a product flavor**. `proMonthly` and `proYearly` both point at it through a `sourceSets` block |

And the other direction: **`free` is a product flavor with no chip at all**,
because it forks nothing. A build of it ships main's icons.

`pro`'s `mipmap-anydpi-v26/ic_launcher.xml` deliberately drops the
`<monochrome>` layer that main declares. A file resource is replaced whole, so
main's themed icon is still on disk, still inherited, and no longer reachable —
which is the finding the panel raises on that plate.

The art is main's own icons re-tinted — green for `pro`, red for `kiosk`,
purple for `partner` — so the sets are told apart at a glance and the iOS ones
keep the opaque, alpha-free PNGs the App Store insists on.

The Android half is wired for real, in `android/app/build.gradle.kts`. The iOS
half stops at the catalogs: pointing a build configuration at
`AppIcon-pro.appiconset` means `ASSETCATALOG_COMPILER_APPICON_NAME` in
`project.pbxproj`, and adding flavor configurations by hand to a sample app buys
nothing — **nothing in flutterware reads the pbxproj**, which is the same reason
the chips cannot claim to be the flavor list.

### Why not a config file per set?

Because the generator has one mode, not two. `flutter_launcher_icons` globs
`flutter_launcher_icons-*.yaml`, and the moment one exists it processes only
those and never reads the `flutter_launcher_icons:` block in `pubspec.yaml`
(`main.dart`, `hasFlavors`). On Android that costs nothing — a config named
`main` writes to `android/app/src/main/res/`, which is where the default one
writes anyway. On iOS there is no name that works: a flavored run always writes
`AppIcon-<flavor>.appiconset`, never the stock `AppIcon`, and the build-setting
edit meant to point at it (`changeIosLauncherIcon`) rewrites `ASSETCATALOG`
lines by matching the CocoaPods `.xcconfig` filename against `-<flavor>`, lower
case and by substring. So the audience that keeps the default catalog has to
leave the generator, whichever audience that is.

That is the trade a real project makes, and either half of it is a legitimate
setup for this viewer to have to read.
