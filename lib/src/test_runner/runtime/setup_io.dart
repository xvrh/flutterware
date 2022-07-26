import 'dart:io';
import 'package:stream_channel/stream_channel.dart';
import 'asset_bundle.dart';
import 'asset_bundle_io.dart';
import 'runner.dart';
import 'setup.dart' show BundleParameters;

Future<TestBundle> createBundle(BundleParameters params) async {
  await _buildBundle(params);
  return IOAssetBundle(
    'build/flutter_assets',
    bundleParams: params,
  );
}

StreamChannel<String> createChannel(Uri serverUri) {
  return connectToServer(serverUri);
}

void onConnected() {
  // Not used in io mode
}

Future<void> _buildBundle(BundleParameters params) async {
  var emptyFile = File('build/__empty__.dart')
    ..createSync()
    ..writeAsStringSync('void main() {}');

  try {
    var result = await Process.run(params.flutterBinPath,
        ['build', 'bundle', '--release', emptyFile.path]);
    if (result.exitCode != 0) {
      throw Exception('Failed to build bundle ${result.stderr}');
    }
  } finally {
    emptyFile.deleteSync();
  }
}
