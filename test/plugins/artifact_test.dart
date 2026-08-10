import 'package:flutterware/plugins.dart';
import 'package:test/test.dart';

void main() {
  var address = Address.parse(
    'fw:///worktrees/main/flutterware.previews/admin/Team?theme=dark',
  );

  test('needs somewhere to live', () {
    expect(
      () => Artifact(kind: Artifact.png, address: address),
      throwsArgumentError,
    );
  });

  test('round-trips through JSON, axes included', () {
    var artifact = Artifact(
      kind: Artifact.png,
      address: address,
      path: '.flutterware/artifacts/01HX.png',
      meta: {'compileMs': 7, 'reloadMs': 94},
    );

    var decoded = Artifact.fromJson(artifact.toJson());
    expect(decoded.kind, Artifact.png);
    expect(decoded.address, address);
    expect(decoded.address.axes, {'theme': 'dark'});
    expect(decoded.path, '.flutterware/artifacts/01HX.png');
    expect(decoded.text, isNull);
    expect(decoded.meta, {'compileMs': 7, 'reloadMs': 94});
  });

  test('inline text needs no path', () {
    var decoded = Artifact.fromJson(
      Artifact(
        kind: Artifact.plainText,
        address: address,
        text: 'Team list\n  3 avatars',
      ).toJson(),
    );
    expect(decoded.text, 'Team list\n  3 avatars');
    expect(decoded.path, isNull);
  });

  test('an empty meta is omitted rather than serialised', () {
    var json = Artifact(
      kind: Artifact.json,
      address: address,
      text: '{}',
    ).toJson();
    expect(json.containsKey('meta'), isFalse);
  });
}
