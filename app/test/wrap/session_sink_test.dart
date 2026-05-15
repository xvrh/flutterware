import 'dart:convert';
import 'dart:io';
import 'package:flutterware_app/src/wrap/session_sink.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_sink'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('newSessionId yields a non-empty filesystem-safe id', () {
    final id = newSessionId();
    expect(id, isNotEmpty);
    expect(id, isNot(contains('/')));
    expect(id, isNot(contains(':')));
  });

  test('SessionSink creates a per-session dir and writes output + meta',
      () async {
    final sink = SessionSink(tmp, 'sess-1');
    final out = sink.openOutput();
    out.add('hello'.codeUnits);
    await out.flush();
    await out.close();
    sink.writeMeta({'exitCode': 0, 'worktree': 'main'});

    final dir = p.join(tmp.path, 'sessions', 'sess-1');
    expect(File(p.join(dir, 'output.log')).readAsStringSync(), 'hello');
    final meta = jsonDecode(File(p.join(dir, 'meta.json')).readAsStringSync());
    expect(meta['exitCode'], 0);
    expect(meta['worktree'], 'main');
  });
}
