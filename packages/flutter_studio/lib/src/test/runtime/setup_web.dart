import 'dart:html';
import 'package:stream_channel/stream_channel.dart';
import '../web_channel.dart';
import 'asset_bundle.dart';
import 'asset_bundle_web.dart';
import 'runner.dart';
import 'setup.dart' show BundleParameters;

Future<ScenarioBundle> createBundle(BundleParameters params) {
  return WebAssetBundle.create(params);
}

const environmentWebSocket = 'scenario-server-url';

StreamChannel<String> createChannel() {
  var serverUrl = const String.fromEnvironment(environmentWebSocket);
  if (serverUrl.isNotEmpty) {
    return connectToServer(Uri.parse('ws://$serverUrl/socket'));
  } else {
    return createWebChannel(window.parent!);
  }
}

const onConnectedMessage = 'onClientConnected';

void onConnected() {
  window.parent!.postMessage(onConnectedMessage, '*');
}
