import 'dart:developer';

void setupAppIntegration({required int serverPort}) async {
  // Register hook, so UIBook widget will delegate to a custom implementation

  print('Integration $serverPort');

  var info = await Service.getInfo();
  print('Info ${info.serverUri}');
}
