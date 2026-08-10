import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware_app/src/capture/capture_request.dart';

/// Did the window land where `fw capture` sent it?
///
/// The only question between "a picture was taken" and "a picture of the right
/// thing was taken", and both ways of getting it wrong are silent: the shell
/// falls back to the home screen for a plugin it cannot build, and a catalog
/// panel opens on some other entry when it cannot reach the one it was asked
/// for. Neither is an error anywhere else, and both are one here.
void main() {
  Address at(String plugin, List<String> segments) => Address(
    worktree: 'wt',
    plugin: plugin,
    segments: segments,
    axes: const {'device': 'iphone-16'},
  );

  test('landing where it was sent is no complaint', () {
    expect(
      landingError(
        wanted: at('flutterware.previews', ['.', 'demo/buttons.dart#buttons']),
        landedPlugin: 'flutterware.previews',
        landedSegments: ['.', 'demo/buttons.dart#buttons'],
        declared: ['flutterware.previews'],
      ),
      isNull,
    );
  });

  test('the wrong panel names the ones this worktree has', () {
    // Almost always a short name where a full one belongs.
    var complaint = landingError(
      wanted: at('ui_catalog', const []),
      landedPlugin: null,
      landedSegments: const [],
      declared: ['flutterware.previews', 'flutterware.assets'],
    );

    expect(complaint, contains('did not land on "ui_catalog"'));
    expect(complaint, contains('flutterware.previews'));
  });

  test('the right panel showing the wrong entry is a complaint too', () {
    // **The measured one.** A capture of `buttons` came back reporting
    // `ok: true` with a picture of `asset_smoke`, because the check stopped at
    // the plugin and the panel had quietly opened on another entry.
    var complaint = landingError(
      wanted: at('flutterware.previews', [
        'examples/example',
        'demo/buttons.dart#buttons',
      ]),
      landedPlugin: 'flutterware.previews',
      landedSegments: ['examples/example', 'demo/asset_smoke.dart#assetSmoke'],
      declared: ['flutterware.previews'],
    );

    expect(complaint, isNotNull);
    expect(complaint, contains('demo/asset_smoke.dart#assetSmoke'));
    expect(
      complaint,
      contains('demo/buttons.dart#buttons'),
      reason: 'both, or the reader cannot see what went wrong',
    );
  });

  test('an address naming only a plugin accepts wherever that panel opens', () {
    // `fw capture fw:///worktrees/~/flutterware.assets` is a picture of the
    // assets panel, and which package it opens on is the panel's business.
    expect(
      landingError(
        wanted: at('flutterware.assets', const []),
        landedPlugin: 'flutterware.assets',
        landedSegments: ['examples/example'],
        declared: ['flutterware.assets'],
      ),
      isNull,
    );
  });

  test('no address is no expectation', () {
    // Capturing the home screen — there is nowhere it was supposed to go.
    expect(
      landingError(
        wanted: null,
        landedPlugin: null,
        landedSegments: const [],
        declared: ['flutterware.previews'],
      ),
      isNull,
    );
  });
}
