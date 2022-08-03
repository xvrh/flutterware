import 'dart:html';
import 'package:stream_channel/stream_channel.dart';
import '../web_channel.dart';
import 'asset_bundle.dart';
import 'asset_bundle_web.dart';
import 'runner.dart';
import 'setup.dart' show BundleParameters;

// ignore_for_file: avoid_web_libraries_in_flutter

Future<TestBundle> createBundle(BundleParameters params) {
  return WebAssetBundle.create(params);
}

StreamChannel<String> createChannel(Uri? serverUrl) {
  if (serverUrl != null) {
    return connectToServer(Uri.parse('ws://$serverUrl/socket'));
  } else {
    return createWebChannel(window.parent!);
  }
}

const onConnectedMessage = 'onClientConnected';

void onConnected() {
  window.parent!.postMessage(onConnectedMessage, '*');
}
