import 'dart:io';
import 'package:process_runner/process_runner.dart';
import 'package:stream_channel/stream_channel.dart';
import 'asset_bundle.dart';
import 'asset_bundle_io.dart';
import 'runner.dart';
import 'setup.dart' show BundleParameters;

Future<ScenarioBundle> createBundle(BundleParameters params) async {
  await _buildBundle();
  return IOAssetBundle(
    'build/flutter_assets',
    bundleParams: params,
  );
}

const environmentWebSocket = 'scenario-server-url';

StreamChannel<String> createChannel() {
  var serverUrl = const String.fromEnvironment(environmentWebSocket);
  assert(serverUrl.isNotEmpty);

  return connectToServer(Uri.parse('ws://$serverUrl/socket'));
}

void onConnected() {
  // Not used in io mode
}

Future<void> _buildBundle() async {
  var emptyFile = File('lib/__empty__.dart')
    ..createSync()
    ..writeAsStringSync('void main() {}');

  var processRunner = ProcessRunner(printOutputDefault: true);

  try {
    await processRunner.runProcess(
        ['flutter', 'build', 'bundle', '--release', emptyFile.path]);
  } finally {
    emptyFile.deleteSync();
  }
}
