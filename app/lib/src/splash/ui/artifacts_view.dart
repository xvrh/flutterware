import 'dart:io';

import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../model/generated.dart';
import '../model/surface.dart';

/// What the generator actually wrote, as pictures.
///
/// **Ground truth, next to a prediction.** Everything above this in the panel is
/// derived from the config through a hand-transcription of somebody else's
/// `cli_commands.dart`; these are the files themselves. The scan has walked them
/// since the plugin shipped and rendered the result as the string
/// `"12 files generated"`, which is the least interesting true thing that could
/// be said about a directory full of images.
///
/// It shows layers rather than splashes, and says so. `splash.png` is the logo
/// on nothing — the background is a separate PNG and the stacking lives in
/// `launch_background.xml`. Compositing those into the real splash is worth
/// doing and is not this; drawing a bare layer beside a composed prediction and
/// calling it a comparison would be the kind of picture that makes people trust
/// the wrong one.
class SplashArtifactsView extends StatelessWidget {
  const SplashArtifactsView({
    super.key,
    required this.artifacts,
    required this.packageRoot,
    this.stale = false,
  });

  final List<SplashArtifact> artifacts;

  /// Absolute, so a package-relative artifact path can be opened.
  final String packageRoot;

  /// The config has been edited since these were written, so this is what
  /// *shipped*, not what the matrix above predicts.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    if (artifacts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generated output', style: type.sectionLabel),
          const SizedBox(height: 6),
          Text(
            // The command, not a button — there is no button. This panel
            // reads; the generator is run by whoever edited the config, and it
            // reports what it did through `fw run splash generate`, which hands
            // back the exit code and the generator's own output.
            'Nothing has been generated yet. The matrix above is what the '
            'config will produce; nothing on disk has been made from it.\n\n'
            'Run `dart run flutter_native_splash:create` in this package, or '
            '`fw run splash generate`, which runs exactly that with the version '
            'the project pins and reports how it went.',
            style: type.caption.copyWith(color: colors.mut),
          ),
        ],
      );
    }

    // Grouped by cell, because that is the unit everything else in this plugin
    // is addressed by. A flat list sorted by path would put an Android dark
    // drawable between two light ones.
    var groups = <(SplashSurface, SplashTheme), List<SplashArtifact>>{};
    for (var artifact in artifacts) {
      groups
          .putIfAbsent((artifact.surface, artifact.theme), () => [])
          .add(artifact);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Generated output', style: type.sectionLabel),
            const SizedBox(width: 8),
            Text(
              stale
                  ? 'the config has changed since these were written'
                  : '${artifacts.length} files',
              style: type.caption.copyWith(
                color: stale ? colors.amber : colors.mut,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'These are layers, not splashes — the background is its own file and '
          'the stacking lives in launch_background.xml.',
          style: type.micro.copyWith(color: colors.mut3),
        ),
        const SizedBox(height: 12),
        for (var entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${entry.key.$1.label} · ${entry.key.$2.label}',
              style: type.bodyStrong,
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var artifact in entry.value..sort(_byRoleThenDensity))
                _Artifact(artifact: artifact, packageRoot: packageRoot),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  static int _byRoleThenDensity(SplashArtifact a, SplashArtifact b) {
    var role = a.role.index.compareTo(b.role.index);
    if (role != 0) return role;
    return (a.density ?? '').compareTo(b.density ?? '');
  }
}

class _Artifact extends StatelessWidget {
  const _Artifact({required this.artifact, required this.packageRoot});

  final SplashArtifact artifact;
  final String packageRoot;

  @override
  Widget build(BuildContext context) {
    var type = context.type;
    var colors = context.colors;

    // A checkerboard behind it, because half of these are transparent and a
    // transparent logo on a panel-coloured square looks like a logo with a
    // background it does not have.
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 68,
            decoration: BoxDecoration(
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(4),
              color: colors.panel2,
            ),
            padding: const EdgeInsets.all(4),
            child: Image.file(
              File('$packageRoot${Platform.pathSeparator}${artifact.path}'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, _, _) => Center(
                child: Text(
                  'unreadable',
                  style: type.micro.copyWith(color: colors.red),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            artifact.density ?? artifact.role.name,
            style: type.caption,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _size(artifact),
            style: type.micro.copyWith(color: colors.mut3),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Pixels always; dp only where the rule has been checked against the
  /// generator — it writes `source * density ~/ 4`, so every Android density of
  /// one image should report the same dp, and one that does not was edited by
  /// hand.
  static String _size(SplashArtifact artifact) {
    if (artifact.pixelWidth == null) return '';
    var pixels = '${artifact.pixelWidth}×${artifact.pixelHeight}';
    var logical = artifact.logicalWidth;
    return logical == null ? pixels : '$pixels · ${logical.round()}dp';
  }
}
