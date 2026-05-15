import 'dart:io';
import 'package:flutterware_app/src/wrap/transport.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wrap_tx'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('runIntercepted captures child output and returns its exit code',
      () async {
    final file = File(p.join(tmp.path, 'cap.log'));
    final sink = file.openWrite();
    final code = await runIntercepted(
      executable: '/bin/echo',
      arguments: const ['hello-wrap-transport'],
      captureSink: sink,
    );
    await sink.flush();
    await sink.close();
    expect(code, 0);
    expect(file.readAsStringSync(), contains('hello-wrap-transport'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('runIntercepted propagates a non-zero exit code', () async {
    final sink = File(p.join(tmp.path, 'c2.log')).openWrite();
    final code = await runIntercepted(
      executable: '/bin/bash',
      arguments: const ['-c', 'exit 7'],
      captureSink: sink,
    );
    await sink.flush();
    await sink.close();
    expect(code, 7);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
