import 'package:flutter/material.dart';

class MockupOverlay extends StatefulWidget {
  const MockupOverlay({Key? key}) : super(key: key);

  @override
  State<MockupOverlay> createState() => _MockupOverlayState();
}

class _MockupOverlayState extends State<MockupOverlay> {
  /*
    static final channelName = 'clipboard/image';
  Future<Uint8List?> getClipboardImage() async {
    final methodChannel = MethodChannel(channelName);
    try {
      final result = await methodChannel.invokeMethod('getClipboardImage');
      //print("Reslt $result");
      return result as Uint8List?;
      //ImageProvider prov = Image.memory(result).image;
      //callback(prov);
    } on PlatformException catch (e) {
      print("error in getting clipboard image");
      print(e);
    }
  }

   */

  @override
  Widget build(BuildContext context) {
    //TODO(xha): overlay above FlowGraph page
    // Handle ctrl+v inside them
    //  Add image with handles to resize/reposition it
    //  Allow to change opacity
    //  Allow to delete it

    return Container();
  }
}
