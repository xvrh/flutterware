import 'package:flutterware_app/src/session/gui.dart';
import 'package:test/test.dart';

/// What the terminal shows while the GUI runs, minus the terminal.
void main() {
  group('isEngineChatter', () {
    test('drops the backend banner every launch prints', () {
      expect(
        isEngineChatter(
          '[IMPORTANT:flutter/shell/platform/embedder/'
          'embedder_surface_metal_impeller.mm(53)] Using the Impeller '
          'rendering backend (MetalSDF).',
        ),
        isTrue,
      );
    });

    test('keeps engine errors, which wear the same shape', () {
      // The whole reason this is a level test and not a prefix test.
      for (var line in const [
        '[ERROR:flutter/shell/common/shell.cc(1055)] Dart Error: something',
        '[FATAL:flutter/fml/memory/ref_counted.h(37)] check failed',
      ]) {
        expect(isEngineChatter(line), isFalse, reason: line);
      }
    });

    test('keeps what the app itself printed', () {
      for (var line in const [
        'flutter: Flutterware GUI is ready',
        'Tools are declared in tool/flutterware.dart:',
        '- Pub dependencies manager',
        '',
        '[IMPORTANT] not the engine, no source file',
      ]) {
        expect(isEngineChatter(line), isFalse, reason: line);
      }
    });
  });
}
