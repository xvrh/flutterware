import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/plugins.dart';

import 'package:flutterware/store_report.dart';

import '../../store/viewers.dart';
import '../../store/tree.dart';
import '../../ui/age.dart';
import '../../ui/design/design.dart';
import '../../ui/menu.dart';
import '../../ui/tappable.dart';
import '../../ui/panel_header.dart';
import '../../ui/split_button.dart';
import '../../ui/theme.dart';
import '../native_plugin.dart';
import 'no_packages.dart';
import 'store_core.dart';
import 'store_results.dart';

export 'store_core.dart' show StoreCore, storePluginId;

/// The listing, as it was last exported.
///
/// **Two truths, and they come from different places.** The *structure* — which
/// listings, which display classes, which locales, what canvas each is — is the
/// declaration, in hand with no I/O. The *pixels* are the last export, read
/// from `StoreShotsReport`. The panel walks the first and looks each set up in the
/// second, which is why there is one layout here rather than an empty screen
/// and a full one: a set with no export draws the same card with placeholders
/// where its shots will be.
///
/// That asymmetry is decision 11 made visible. A source scan would have filled
/// those placeholders with real shot names before the first export, at the cost
/// of a parser tracking two naming spellings forever. What it would have bought
/// is the difference between a card that says *five shots, not yet exported*
/// and one that says *not yet exported* — and the declaration alone already
/// says everything else on the card.
class StorePlugin extends NativePlugin<StoreCore> {
  StorePlugin(super.core);

  @override
  Widget buildPanel(BuildContext context) => _StorePanel(this);
}

class _StorePanel extends StatefulWidget {
  const _StorePanel(this.plugin);

  final StorePlugin plugin;

  @override
  State<_StorePanel> createState() => _StorePanelState();
}

class _StorePanelState extends State<_StorePanel> {
  bool _running = false;
  String? _outcome;

  /// The **app's** locale, not the store's slot, because that is what the
  /// declaration spells and what the reader typed. Null until the declaration
  /// is read, then the first one declared.
  String? _locale;

  StoreCore get _core => widget.plugin.core;

  List<String> get _locales => {
    for (var package in _core.packages)
      for (var listing in package.listings) ...listing.locales.keys,
  }.toList();

  Future<void> _run(
    String action, {
    Map<String, Object?> arguments = const {},
  }) async {
    setState(() {
      _running = true;
      _outcome = null;
    });
    try {
      var result = (await _core.invoke(action, arguments: arguments))!;
      if (!mounted) return;
      setState(() {
        _outcome = switch (result) {
          StoreExportResult(:var count, :var packages) =>
            packages.map((p) => p.error).nonNulls.firstOrNull ??
                '$count ${count == 1 ? 'image' : 'images'} written',
          _ => null,
        };
      });
    } catch (error) {
      if (mounted) setState(() => _outcome = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// The one-click export, with the narrowed forms behind the chevron.
  ///
  /// **Capture and framing are one thing here**, and the menu says nothing
  /// about the split. It carried a *Re-frame existing screenshots* entry for a
  /// while — the second pass, offered on its own — and it was two things at
  /// once: obscure, because nobody thinks of a listing as two passes, and
  /// barely worth it, because moving the PNG codec off the main isolate took a
  /// full export from ~48s to ~26s against a recompose's ~17s. A menu entry
  /// that asks the reader to learn the internals to save nine seconds is a
  /// menu entry that should not be there.
  Widget _exportButton(BuildContext context, {DateTime? exported}) =>
      FwSplitButton(
        label: _running ? 'Exporting…' : 'Export',
        onPressed: _running ? null : () => _run('export'),
        entries: [
          MenuItem(
            'Export App Store only',
            onSelected: _running
                ? null
                : () => _run('export', arguments: {'listing': 'app-store'}),
          ),
          MenuItem(
            'Export Google Play only',
            onSelected: _running
                ? null
                : () => _run('export', arguments: {'listing': 'play'}),
          ),
          const MenuDivider(),
          MenuItem(
            'Reveal in Finder',
            onSelected: exported == null ? null : () => _run('open'),
          ),
          MenuItem('Copy CLI command', onSelected: _copyCommand),
        ],
      );

  /// A thumbnail was clicked: show that image, as large as the window allows.
  void _showShot(String key, int index) {
    var found = _setFor(key);
    if (found == null) return;
    var (package, target, listing, set) = found;
    showStoreShot(
      context,
      files: [for (var image in set.images) File(set.pathOf(image))],
      titles: [
        for (var image in set.images)
          storeTitleOf(package.layout, target, image),
      ],
      index: index,
      setLabel: '${listing.storeLabel} · ${target.label} · ${set.storeLocale}',
      width: target.canvas.width,
      height: target.canvas.height,
    );
  }

  /// The card's own action: the whole set, arranged as a listing.
  void _showListing(String key) {
    var found = _setFor(key);
    if (found == null) return;
    var (package, target, listing, set) = found;
    showStoreListing(
      context,
      files: [for (var image in set.images) File(set.pathOf(image))],
      aspect: target.canvas.width / target.canvas.height,
      appName: _core.identityOf(package).name,
      subtitle: _core.identityOf(package).subtitle,
      setLabel: '${listing.storeLabel} · ${target.label} · ${set.storeLocale}',
    );
  }

  /// Everything a viewer needs, from a manifest key.
  (StoreShotsPackage, StoreTarget, Listing, StoreShotsSet)? _setFor(
    String key,
  ) {
    for (var package in _core.packages) {
      var set = _core.manifestOf(package)[key];
      if (set == null || set.images.isEmpty) continue;
      var target = _targetFor(package, key);
      if (target == null) continue;
      return (package, target.$1, target.$2, set);
    }
    return null;
  }

  /// The declared target and its listing, from a manifest key.
  (StoreTarget, Listing)? _targetFor(StoreShotsPackage package, String key) {
    for (var listing in package.listings) {
      for (var target in listing.targets) {
        if (key.startsWith('${target.store}/${target.id}/')) {
          return (target, listing);
        }
      }
    }
    return null;
  }

  void _copyCommand() {
    unawaited(
      Clipboard.setData(const ClipboardData(text: 'fw run store export')),
    );
    setState(() => _outcome = 'Command copied');
  }

  @override
  Widget build(BuildContext context) {
    var packages = _core.packages;
    if (packages.isEmpty) {
      return const NoPackagesConfigured(icon: Icons.storefront_outlined);
    }
    var locales = _locales;
    var locale = _locale ?? locales.firstOrNull;

    // Subscribed, not merely read. The core narrates by calling
    // `notifyChanged`, which the plugin relays as a `ChangeNotifier`; without
    // this the rail's status line moved through a whole export while the panel
    // below it sat on the first line it had happened to build with.
    return ListenableBuilder(
      listenable: widget.plugin,
      builder: (context, _) => _body(context, packages, locales, locale),
    );
  }

  Widget _body(
    BuildContext context,
    List<StoreShotsPackage> packages,
    List<String> locales,
    String? locale,
  ) {
    var manifests = {
      for (var package in packages) package.path: _core.manifestOf(package),
    };
    var exported = manifests.values
        .map((m) => m.exportedAt)
        .nonNulls
        .fold<DateTime?>(
          null,
          (best, at) => best == null || at.isAfter(best) ? at : best,
        );
    var progress = _core.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header pads itself — gutter, top and bottom — so the list adds
        // only the side gutter. Padding both was three helpings of the same
        // space: doubled gutters, a doubled top inset, and a gap under the
        // header on top of the header's own.
        FwPanelHeader(
          'Store',
          subtitle: [
            for (var package in packages)
              if (packages.length > 1) package.path,
            if (progress != null)
              progress.line
            else if (exported == null)
              'never exported'
            else
              'exported ${ageOf(exported)}',
            if (progress == null) ?_outcome,
          ],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locales.length > 1 && locale != null) ...[
                _LocaleSwitch(
                  locales: locales,
                  selected: locale,
                  onChanged: (value) => setState(() => _locale = value),
                ),
                const Gap(FwSpacing.md),
              ],
              _exportButton(context, exported: exported),
            ],
          ),
        ),
        // Determinate, because the total is known before the first set starts
        // — a spinner would be the one thing a long job must not be, which is
        // silent about how much is left.
        if (progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: panelGutter),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.radii.pill),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 4,
                backgroundColor: context.colors.line,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              panelGutter,
              FwSpacing.md,
              panelGutter,
              FwSpacing.xxxl,
            ),
            children: [
              for (var package in packages)
                for (var listing in package.listings)
                  _ListingBlock(
                    listing: listing,
                    manifest: manifests[package.path]!,
                    locale: locale,
                    working: progress?.key,
                    onShot: _showShot,
                    onListing: _showListing,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Which locale every card on the screen is showing.
///
/// A switch rather than a fourth level of nesting, per §6: changing it changes
/// every image at once, where nesting it turns four screenshots into sixteen
/// rows.
///
/// A **dropdown**, and the same one the Translations panel uses. It was a row
/// of pills first, which is the right control for two or three choices and the
/// wrong one here — a listing declares as many locales as it ships, and twenty
/// of them wrap into a block of chrome taller than the title it sits under.
/// One compact control is also what lets this live beside Export in the title
/// row instead of in a band of its own below it.
class _LocaleSwitch extends StatelessWidget {
  const _LocaleSwitch({
    required this.locales,
    required this.selected,
    required this.onChanged,
  });

  final List<String> locales;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return MenuAnchor(
      menuChildren: [
        for (var locale in locales)
          MenuItemButton(
            onPressed: () => onChanged(locale),
            leadingIcon: Icon(
              locale == selected ? Icons.check : null,
              size: FwIconSize.sm,
              color: colors.accent,
            ),
            child: Text(locale, style: context.type.body),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Which locale the screenshots below are from',
        child: Tappable(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            height: 28,
            padding: const EdgeInsets.only(
              left: FwSpacing.lg,
              right: FwSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colors.bg,
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(context.radii.radiusSmall),
            ),
            child: Row(
              children: [
                Text(selected, style: context.type.bodySmall),
                Icon(Icons.expand_more, size: FwIconSize.sm, color: colors.mut),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One store's half of the listing: a heading, then a card per display class.
class _ListingBlock extends StatelessWidget {
  const _ListingBlock({
    required this.listing,
    required this.manifest,
    required this.locale,
    required this.working,
    required this.onShot,
    required this.onListing,
  });

  final Listing listing;
  final StoreShotsReport manifest;
  final String? locale;

  /// A shot was clicked — the set's key and its 0-based position.
  final void Function(String key, int index) onShot;

  /// The card's listing action — the set's key.
  final ValueChanged<String> onListing;

  /// The `store/class/appLocale` key of the set an export is on right now, so
  /// exactly that card can say so while the others stay as they were.
  final String? working;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: FwSpacing.lg),
          child: Text(listing.storeLabel, style: context.type.heading),
        ),
        for (var target in listing.targets)
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.lg),
            child: _SetCard(
              listing: listing,
              target: target,
              set: locale == null
                  ? null
                  : manifest['${target.store}/${target.id}/$locale'],
              storeLocale: locale == null ? null : listing.locales[locale],
              working: working == '${target.store}/${target.id}/$locale',
              onShot: (index) =>
                  onShot('${target.store}/${target.id}/$locale', index),
              onListing: () =>
                  onListing('${target.store}/${target.id}/$locale'),
            ),
          ),
        const Gap(FwSpacing.lg),
      ],
    );
  }
}

/// One set — one listing, one display class, one locale.
///
/// The corner is deliberately **neutral and unabbreviated**: canvas, locale,
/// and how many shots there are. It first read `1320×2868 · 15 of 10 · en-US`
/// in amber, which nobody could decode — two numbers with no unit, coloured as
/// a warning about something the card never named, and shots past the tenth
/// dimmed with nothing on screen saying why.
///
/// So the cap is stated in words, once, under the strip, and only when it
/// actually bites. Nothing here judges the screenshots: decision 1. A store
/// publishing ten of fifteen is arithmetic against a published limit, and it
/// is the one thing on this card that changes what gets shipped.
class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.listing,
    required this.target,
    required this.set,
    required this.storeLocale,
    required this.working,
    required this.onShot,
    required this.onListing,
  });

  final Listing listing;
  final StoreTarget target;
  final StoreShotsSet? set;
  final String? storeLocale;
  final ValueChanged<int> onShot;
  final VoidCallback onListing;

  /// This set is the one being exported right now.
  final bool working;

  /// How tall a thumbnail is. The strip is the card's whole point, so it gets
  /// the room; the width follows from the canvas, which is why a 2:1 Play
  /// phone and a 4:3 iPad read as visibly different shapes on one screen.
  static const _thumbHeight = 168.0;

  double get _thumbWidth =>
      _thumbHeight * target.canvas.width / target.canvas.height;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var images = set?.images ?? const <String>[];
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(context.radii.radius),
        border: Border.all(color: colors.line),
      ),
      padding: const EdgeInsets.all(FwSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(target.label, style: context.type.bodyStrong),
              if (images.isNotEmpty) ...[
                const Gap(FwSpacing.lg),
                // The set's own action, on the set's own card. A listing is a
                // property of the set — which is why there is no such thing as
                // previewing "the listing of shot 4", and why the page that
                // tried to be one had a selection it could not justify.
                _CardAction(
                  label: 'Preview listing',
                  icon: Icons.storefront_outlined,
                  onTap: onListing,
                ),
              ],
              if (working) ...[
                const Gap(FwSpacing.md),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                [
                  '${target.canvas.width} × ${target.canvas.height} px',
                  ?storeLocale,
                  if (images.isNotEmpty)
                    '${images.length} ${images.length == 1 ? 'shot' : 'shots'}',
                ].join('  ·  '),
                style: context.type.bodySmall.copyWith(color: colors.mut),
              ),
            ],
          ),
          const Gap(FwSpacing.lg),
          SizedBox(
            height: _thumbHeight,
            child: images.isEmpty
                ? _GhostStrip(width: _thumbWidth)
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    separatorBuilder: (_, _) => const Gap(FwSpacing.md),
                    itemBuilder: (context, index) => _Thumb(
                      file: File(set!.pathOf(images[index])),
                      name: images[index],
                      width: _thumbWidth,
                      store: listing.storeLabel,
                      cap: listing.maxShots,
                      position: index + 1,
                      onTap: () => onShot(index),
                    ),
                  ),
          ),
          if (images.length > listing.maxShots) ...[
            const Gap(FwSpacing.lg),
            _Note(
              tone: colors.amber,
              icon: Icons.info_outline,
              text:
                  'Only the first ${listing.maxShots} are published — '
                  "${listing.storeLabel}'s limit per display class.",
            ),
          ],
          if (images.isEmpty) ...[
            const Gap(FwSpacing.lg),
            // Under the strip rather than beside it. Beside it, the sentence
            // starts wherever three thumbnails happen to end — and a thumbnail
            // is as wide as its canvas, so four cards on one screen put the
            // same sentence at four different left edges.
            Text(
              target.needsComposition
                  ? 'Not exported yet. Export runs the scenarios at '
                        '${target.device.label}, then composes each named shot '
                        'onto this canvas.'
                  : 'Not exported yet. Export runs the scenarios at '
                        '${target.device.label} and keeps every named shot.',
              style: context.type.bodySmall.copyWith(color: colors.mut2),
            ),
          ],
          if (set != null && set!.failed > 0) ...[
            const Gap(FwSpacing.md),
            _Note(
              tone: colors.red,
              icon: Icons.error_outline,
              text:
                  '${set!.failed} scenario${set!.failed == 1 ? '' : 's'} '
                  'failed while producing this set — it may be short.',
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet text button on a card's title row.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: FwIconSize.sm, color: colors.accent),
            const Gap(FwSpacing.xs),
            Text(
              label,
              style: context.type.bodySmall.copyWith(color: colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of explanation under a card's strip.
///
/// Every marking on this panel that is not a screenshot has to say what it
/// means where it means it. A colour alone is a riddle: amber on `15 of 10`
/// told the reader something was wrong without telling them what, and dimmed
/// thumbnails read as a rendering fault rather than as a store's limit.
class _Note extends StatelessWidget {
  const _Note({required this.tone, required this.icon, required this.text});

  final Color tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: FwIconSize.sm, color: tone),
      const Gap(FwSpacing.sm),
      Expanded(
        child: Text(text, style: context.type.bodySmall.copyWith(color: tone)),
      ),
    ],
  );
}

/// One exported screenshot, at 1×.
///
/// The export pays for the device's real pixel ratio; the panel does not — the
/// same split `captureScale` already makes. A file that has gone missing under
/// the panel draws as a gap rather than as an exception, because a deleted
/// build directory is an ordinary thing and not an error to report.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.file,
    required this.name,
    required this.width,
    required this.store,
    required this.cap,
    required this.position,
    required this.onTap,
  });

  final File file;

  /// The file's name, which is also the shot's — shown on hover, because at
  /// this size the picture cannot say which shot it is.
  final String name;

  final double width;

  /// Whose limit [cap] is, so the tooltip can name it.
  final String store;
  final int cap;

  /// 1-based place in the set.
  final int position;

  final VoidCallback onTap;

  /// Past the store's limit. Dimmed rather than hidden: the shots exist, and
  /// which of them will not be published is the thing worth seeing. The card
  /// says so in words underneath — a dimmed thumbnail on its own reads as a
  /// bug.
  bool get _overCap => position > cap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tooltip(
      message: _overCap
          ? "$name — past $store's limit of $cap, not published"
          : name,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Opacity(
            opacity: _overCap ? 0.35 : 1,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: colors.panel2,
                borderRadius: BorderRadius.circular(context.radii.radiusSmall),
                border: Border.all(color: colors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                file,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty arm of a card, and the reason this panel has no separate empty
/// screen.
///
/// Ghost canvases at the set's real aspect ratio, filling the strip — which
/// says more than a sentence can: the shapes on screen are the shapes the
/// store will receive, so a 2:1 Play phone sitting two cards above a 4:3 iPad
/// shows what §1's canvas-is-not-a-device argument means without a word of it.
///
/// They fade rightwards because the count is unknown. A fixed number of solid
/// placeholders would be a claim about how many shots this set has, and the
/// panel has no idea — that is what the source scan decision 11 declined would
/// have bought.
class _GhostStrip extends StatelessWidget {
  const _GhostStrip({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    var color = context.colors.mut3;
    return LayoutBuilder(
      builder: (context, constraints) {
        var step = width + FwSpacing.md;
        var count = (constraints.maxWidth / step).ceil().clamp(1, 12);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: count * step,
            child: Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  Opacity(
                    opacity: (1 - i / count).clamp(0.15, 1.0),
                    child: DottedFrame(
                      width: width,
                      color: color,
                      radius: context.radii.radiusSmall,
                    ),
                  ),
                  const Gap(FwSpacing.md),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A dashed outline of the canvas — the shape an export will fill.
class DottedFrame extends StatelessWidget {
  const DottedFrame({
    super.key,
    required this.width,
    required this.color,
    required this.radius,
  });

  final double width;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, double.infinity),
    painter: _DashedBorder(color: color, radius: radius),
    child: SizedBox(width: width, height: double.infinity),
  );
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    var rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    // Walked rather than stroked: Flutter has no dashed stroke, and a metric
    // walk is the whole of what a dash pattern is.
    for (var metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 8) {
        canvas.drawPath(
          metric.extractPath(at, (at + 4).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
