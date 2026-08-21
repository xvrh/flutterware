import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/plugins.dart';
import 'package:flutterware/translations.dart';
// ignore: implementation_imports
import 'package:flutterware/src/log_client.dart';
import 'package:flutterware_app/src/context.dart';
import 'package:flutterware_app/src/plugins/native/translations_core.dart';
import 'package:flutterware_app/src/plugins/plugin_host.dart';
import 'package:flutterware_app/src/shell/workspace.dart';
import 'package:flutterware_app/src/shell/worktree.dart';
import 'package:flutterware_app/src/utils/flutter_sdk.dart';
import 'package:path/path.dart' as p;

/// Read through [PluginReport] wherever the sidebar reads through it, because
/// what the rail says is the subject of half of this file.
void main() {
  late Directory scratch;
  late Directory root;

  TranslationsCore core() {
    var worktree = Worktree(path: root.path);
    return TranslationsCore(
      PluginHost(
        id: translationsPluginId,
        label: 'Translations',
        worktree: worktree,
        workspace: Workspace(
          root: worktree.path,
          declared: [Pkg('.')],
          discovered: const ['.'],
          appContext: AppContext(logger: LogClient.print()),
          flutterSdk: FlutterSdkPath('/tmp/flutter'),
        ),
        config: {
          'packages': [
            {
              'path': '.',
              'catalogs': [
                {'name': 'app', 'files': 'i18n/*.json', 'template': 'en'},
              ],
            },
          ],
        },
      ),
    );
  }

  void write(String relative, Object json) {
    var file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(json));
  }

  /// An export where every key was declared and none was ever read — what an
  /// unwired seam leaves behind.
  void writeUntracedExport(List<String> keys) => write(
    'build/translations/$translationExportFile',
    TranslationExport(
      keys: [for (var key in keys) ExportedKey(catalog: 'app', key: key)],
      findings: ExportFindings(
        notReached: [
          for (var key in keys) ExportedKeyRef(catalog: 'app', key: key),
        ],
      ),
    ).toJson(),
  );

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('fw_translations_core_test');
    root = Directory(p.join(scratch.path, 'app'))..createSync();
    write('i18n/en.json', {'save': 'Save', 'cancel': 'Cancel'});
    write('i18n/nl.json', {'save': 'Bewaren'});
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('the rail says nothing about keys that are not translated yet', () async {
    var it = core();
    await it.computeAll();

    // The count itself is real — `cancel` has no Dutch.
    expect(it.missingFor('.'), 1);
    // And it stays off the rail. A number that is true for months is not news,
    // and an amber dot that never clears is how a rail stops being read.
    expect(it.report.badge.tone, isNot(Tone.warn));
    expect(it.report.status.tone, isNot(Tone.warn));
    expect(
      it.report.children.single.status.message,
      isNot(contains('untranslated')),
    );
    expect(it.report.children.single.status.message, '2 keys · en, nl');
  });

  test('a catalog that will not read still reaches the rail', () async {
    File(p.join(root.path, 'i18n', 'en.json')).writeAsStringSync('{not json');
    var it = core();
    await it.computeAll();

    expect(it.report.badge.tone, Tone.error);
  });

  test('the rows are held, not rebuilt for every look', () async {
    var it = core();
    await it.computeAll();

    // One sidebar frame asks eight times, and every plugin's notification is a
    // frame. Identity is the assertion because the alternative — joining the
    // catalogs against the export again — is what froze the studio.
    expect(identical(it.rowsFor('.'), it.rowsFor('.')), isTrue);
  });

  test('an edited catalog is a new set of rows', () async {
    var it = core();
    await it.computeAll();
    var before = it.rowsFor('.');

    write('i18n/nl.json', {'save': 'Bewaren', 'cancel': 'Annuleren'});
    it.invalidate('.');
    await it.computeAll();

    expect(identical(before, it.rowsFor('.')), isFalse);
    expect(it.missingFor('.'), 0);
  });

  test('an export that traced nothing says so', () async {
    writeUntracedExport(['save', 'cancel']);
    var it = core();
    await it.computeAll();

    expect(it.exportFor('.'), isNotNull);
    expect(it.untracedFor('.'), isTrue);
  });

  test('an export that photographed one key is not called untraced', () async {
    write(
      'build/translations/$translationExportFile',
      const TranslationExport(
        keys: [
          ExportedKey(
            catalog: 'app',
            key: 'save',
            representative: ExportedShot(
              image: 'shots/a.png',
              scenario: 'home',
              step: 'open',
              stepIndex: 0,
            ),
          ),
          ExportedKey(catalog: 'app', key: 'cancel'),
        ],
        findings: ExportFindings(
          notReached: [ExportedKeyRef(catalog: 'app', key: 'cancel')],
        ),
      ).toJson(),
    );
    var it = core();
    await it.computeAll();

    expect(it.untracedFor('.'), isFalse);
  });

  test('no export at all is not an untraced one', () async {
    var it = core();
    await it.computeAll();

    expect(it.untracedFor('.'), isFalse);
  });
}
