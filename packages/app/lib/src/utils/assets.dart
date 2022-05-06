import 'package:flutter/widgets.dart';
import 'assets.gen.dart';

export 'assets.gen.dart';

extension AssetExtension on AssetImageInfo {
  Image toImage({bool? withSize}) {
    withSize ??= false;

    if (withSize) {
      return Image.asset(path, width: width, height: height);
    } else {
      return Image.asset(path);
    }
  }

  ImageProvider get provider => AssetImage(path);
}
