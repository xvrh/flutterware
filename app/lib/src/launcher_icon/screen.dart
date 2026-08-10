import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/plugins.dart';

import '../address/address_scope.dart';
import '../plugins/native/icon_core.dart';
import '../ui/design/design.dart';
import '../ui/empty_state.dart';
import '../ui/theme.dart';
import 'model/role.dart';
import 'model/scan.dart';
import 'model/wiring.dart';
import 'ui/detail.dart';
import 'ui/plate.dart';

/// Every launcher icon a package has: a plate per role on the left, and the
/// selected one shown where it actually lives on the right.
///
/// The two halves answer different questions, which is why both are here. The
/// plates answer *what have I got, and what does each platform do to it* — the
/// source beside every shape a launcher might clip it to, the finding attached
/// to the thing it is about. The stage answers *is it any good*, which is a
/// relative judgement no thumbnail can support: too heavy beside its
/// neighbours, invisible on a dark wallpaper, unreadable at the 16px a tab
/// gives it.
///
/// Master–detail rather than a stack, following the scenarios panel: the list
/// stays visible, so opening one icon never hides where you are among the rest.
class LauncherIconScreen extends StatefulWidget {
  const LauncherIconScreen(
    this.core, {
    super.key,
    required this.package,
    this.flavor,
    this.role,
    this.mask,
  });

  final LauncherIconCore core;
  final String package;

  /// Which Android source set, from the address.
  final String? flavor;

  /// The role the address names, if it names one.
  final IconRole? role;

  final AdaptiveMask? mask;

  @override
  State<LauncherIconScreen> createState() => _LauncherIconScreenState();
}

class _LauncherIconScreenState extends State<LauncherIconScreen> {
  AdaptiveMask? _mask;
  IconRole? _role;
  bool _rolePicked = false;
  bool _safeZone = false;
  bool _dark = true;

  /// The address wins when it names one, so a pasted link shows what it says;
  /// otherwise the local choice does.
  AdaptiveMask get _adaptiveMask =>
      widget.mask ?? _mask ?? AdaptiveMask.squircle;

  IconRole? get _selectedRole => _rolePicked ? _role : widget.role;

  @override
  void didUpdateWidget(LauncherIconScreen old) {
    super.didUpdateWidget(old);
    if (old.role != widget.role) _rolePicked = false;
  }

  Future<void> _reload() async {
    await widget.core.reload(widget.package, flavor: widget.flavor);
    if (mounted) setState(() {});
  }

  /// Held locally *and* written to the address, so the panel works with no
  /// [AddressScope] above it — a widget test, or a dev entry point.
  void _select(IconRole? role) {
    setState(() {
      _role = role;
      _rolePicked = true;
    });
    AddressScope.maybeWrite(context)?.setParam('role', role?.id);
  }

  @override
  Widget build(BuildContext context) {
    var core = widget.core;
    var failure = core.failureFor(widget.package, flavor: widget.flavor);
    if (failure != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not read the icons',
        message: failure,
      );
    }

    var scan = core.scanFor(widget.package, flavor: widget.flavor);
    if (scan == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (scan.isEmpty) {
      return const EmptyState(
        icon: Icons.image_outlined,
        title: 'No launcher icons found',
        message:
            'Nothing under android/, ios/, macos/, web/, windows/ or snap/ '
            'looks like an app icon.',
      );
    }

    var selected = _selectedRole;
    var selectedScan = selected == null ? null : scan.forRole(selected);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _Plates(
            scan: scan,
            selected: selected,
            adaptiveMask: _adaptiveMask,
            onSelect: _select,
            onReload: _reload,
            scanning: core.isScanning(widget.package, flavor: widget.flavor),
            flavor: widget.flavor,
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 380,
          child: selectedScan == null || selectedScan.isEmpty
              ? const EmptyState(
                  icon: Icons.smartphone_outlined,
                  title: 'Pick an icon',
                  message: 'Opening one shows it where it is actually seen.',
                )
              : _detail(scan, selectedScan),
        ),
      ],
    );
  }

  Widget _detail(IconScan scan, IconRoleScan role) {
    var background = _backgroundFor(scan, role.role);

    return IconDetail(
      key: ValueKey(role.role.id),
      role: role.role,
      image: _imageFor(role.largest),
      backgroundImage: _imageFor(background?.largest),
      backgroundColor: _colorOf(background?.color),
      color: role.color,
      files: [
        for (var file in role.files)
          (
            image: FileImage(File(file.absolutePath)),
            size: file.width,
            density: file.density,
          ),
      ],
      findings: _findingsFor(scan, role.role),
      context_: _contextLine(scan, role.role),
      adaptiveMask: _adaptiveMask,
      onMask: (mask) => setState(() => _mask = mask),
      showSafeZone: _safeZone,
      onSafeZone: (on) => setState(() => _safeZone = on),
      dark: _dark,
      onDark: (on) => setState(() => _dark = on),
    );
  }

  /// The adaptive background a layer is composited over, when it has one — a
  /// foreground drawn over nothing is not what a launcher shows.
  ///
  /// The **foreground only**. A themed icon throws the adaptive background away
  /// along with everything else and takes both its colours from the wallpaper,
  /// so handing it one would paint a ground Android never uses.
  IconRoleScan? _backgroundFor(IconScan scan, IconRole role) =>
      role == IconRole.androidAdaptiveForeground
      ? scan.forRole(IconRole.androidAdaptiveBackground)
      : null;

  /// The one line of project context that changes what a role means.
  String? _contextLine(IconScan scan, IconRole role) {
    var android = scan.android;
    if (android == null || role.platform != IconPlatform.android) return null;
    var minApi = role.minAndroidApi;
    if (minApi == null) return null;

    if (android.minSdk == null) {
      return 'minSdk could not be read, so how much of your install base sees '
          'this is unknown.';
    }
    return android.minSdk! >= minApi
        ? 'minSdk is ${android.minSdk}, so every device you ship to sees this.'
        : 'minSdk is ${android.minSdk}, below API $minApi — devices under that '
              'fall back to the bitmap launcher icon.';
  }

  List<({Tone tone, String message})> _findingsFor(
    IconScan scan,
    IconRole role,
  ) => [
    for (var finding in scan.findings)
      if (finding.role == role) (tone: finding.tone, message: finding.message),
  ];
}

ImageProvider? _imageFor(IconFile? file) =>
    file == null ? null : FileImage(File(file.absolutePath));

Color? _colorOf(String? value) {
  var parsed = parseResourceColor(value);
  return parsed == null ? null : Color(parsed);
}

/// The master pane: one plate per role, grouped by the platform whose rules
/// apply.
class _Plates extends StatelessWidget {
  const _Plates({
    required this.scan,
    required this.adaptiveMask,
    required this.onSelect,
    required this.onReload,
    required this.scanning,
    this.selected,
    this.flavor,
  });

  final IconScan scan;
  final IconRole? selected;
  final AdaptiveMask adaptiveMask;
  final ValueChanged<IconRole?> onSelect;
  final VoidCallback onReload;
  final bool scanning;
  final String? flavor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xxl),
      children: [
        _Header(
          scan: scan,
          selected: flavor,
          scanning: scanning,
          onReload: onReload,
        ),
        const Gap(FwSpacing.xxl),
        for (var platform in scan.platforms) ...[
          Text(platform.label, style: context.type.sectionLabel),
          const Gap(FwSpacing.lg),
          for (var role in scan.forPlatform(platform))
            if (role.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: FwSpacing.lg),
                child: IconPlate(
                  key: ValueKey(role.role.id),
                  role: role.role,
                  image: _imageFor(role.largest),
                  color: role.color,
                  backgroundImage: _imageFor(
                    role.role == IconRole.androidAdaptiveForeground ||
                            role.role == IconRole.androidMonochrome
                        ? scan
                              .forRole(IconRole.androidAdaptiveBackground)
                              ?.largest
                        : null,
                  ),
                  backgroundColor: _colorOf(
                    role.role == IconRole.androidAdaptiveForeground ||
                            role.role == IconRole.androidMonochrome
                        ? scan
                              .forRole(IconRole.androidAdaptiveBackground)
                              ?.color
                        : null,
                  ),
                  adaptiveMask: adaptiveMask,
                  detail: _detailLine(role),
                  findings: [
                    for (var finding in scan.findings)
                      if (finding.role == role.role)
                        (tone: finding.tone, message: finding.message),
                  ],
                  selected: role.role == selected,
                  onTap: () =>
                      onSelect(role.role == selected ? null : role.role),
                ),
              ),
          const Gap(FwSpacing.lg),
        ],
      ],
    );
  }

  /// Sizes and how many, in one line.
  String? _detailLine(IconRoleScan role) {
    var largest = role.largest;
    if (largest == null) return null;
    if (largest.icoFrames.isNotEmpty) {
      return '${largest.icoFrames.length} frames · '
          '${largest.icoFrames.first} → ${largest.icoFrames.last}px';
    }
    if (largest.width == null) return '${role.files.length} files';
    var size = '${largest.width}×${largest.height}';
    return role.files.length == 1
        ? size
        : '$size · ${role.files.length} ${role.role.platform == IconPlatform.android ? 'densities' : 'sizes'}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.scan,
    required this.onReload,
    this.selected,
    this.scanning = false,
  });

  final IconScan scan;
  final VoidCallback onReload;
  final String? selected;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;
    var android = scan.android;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              scan.packagePath == '.' ? 'root' : scan.packagePath,
              style: type.heading,
            ),
            const Gap(FwSpacing.md),
            Text(
              '${scan.fileCount} files',
              style: type.caption.copyWith(color: colors.mut),
            ),
            const Spacer(),
            if (android != null)
              Text(
                android.minSdk == null
                    ? 'minSdk unknown'
                    : 'minSdk ${android.minSdk}',
                style: type.caption.copyWith(
                  color: android.minSdk == null ? colors.amber : colors.mut,
                ),
              ),
            const Gap(FwSpacing.lg),
            // The files are written by something outside this process — a
            // generator in another terminal, a designer dropping a PNG in — so
            // there has to be a way to look again without reopening the panel.
            IconButton(
              onPressed: scanning ? null : onReload,
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              tooltip: 'Read the icons again',
              icon: scanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        if (scan.ios == IosCatalog.iconComposer ||
            scan.ios == IosCatalog.both) ...[
          const Gap(FwSpacing.sm),
          Text(
            scan.ios == IosCatalog.both
                ? 'An Icon Composer bundle and a classic asset catalog are both '
                      'present — Xcode uses one, decided by the target settings.'
                : 'iOS icons come from the Icon Composer bundle '
                      '${scan.iconBundles.join(', ')}; Xcode generates every '
                      'size at build time, so there are no per-size PNGs to '
                      'show.',
            style: type.caption.copyWith(color: colors.mut),
          ),
        ],
        if (scan.flavors.isNotEmpty) ...[
          const Gap(FwSpacing.lg),
          Wrap(
            spacing: FwSpacing.sm,
            children: [
              _Chip(label: 'main', selected: selected == null),
              for (var flavor in scan.flavors)
                _Chip(label: flavor, selected: flavor == selected),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.lg,
        vertical: FwSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.panel2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? colors.accent : colors.line),
      ),
      child: Text(label, style: context.type.caption),
    );
  }
}
