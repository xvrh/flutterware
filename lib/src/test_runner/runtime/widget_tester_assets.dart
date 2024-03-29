import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

extension WidgetTesterAssetsExtension on WidgetTester {
  Iterable<_ImageAndContext> _listImages() sync* {
    final imageElements = find.byType(Image).evaluate();
    final containerElements = find.byType(DecoratedBox).evaluate();

    for (final imageElement in imageElements) {
      final widget = imageElement.widget;
      if (widget is Image) {
        yield _ImageAndContext(widget.image, imageElement);
      }
    }
    for (final container in containerElements) {
      final widget = container.widget as DecoratedBox;
      final decoration = widget.decoration;
      if (decoration is BoxDecoration) {
        var decorationImage = decoration.image;
        if (decorationImage != null) {
          yield _ImageAndContext(decorationImage.image, container);
        }
      }
    }
  }

  /// Tries to preload all `Image`s (except `NetworkImage`s) in the current widget tree.
  Future<void> waitForAssets() async {
    if (kIsWeb) {
      return;
    }

    await runAsync(() async {
      var futures = <Future>[];

      for (final image in _listImages()) {
        if (image.provider is! NetworkImage) {
          futures.add(precacheImage(image.provider, image.context));
        }
      }
      await Future.wait(futures);
    });
  }

  /// Tries to preload all `NetworkImage`s in the current widget tree.
  Future<void> waitForNetworkImages() async {
    if (kIsWeb) {
      return;
    }

    await runAsync(() async {
      var futures = <Future>[];
      for (final image in _listImages()) {
        if (image.provider is NetworkImage) {
          futures.add(precacheImage(image.provider, image.context));
        }
      }
      await Future.wait(futures);
    });
  }
}

class _ImageAndContext {
  final ImageProvider provider;
  final BuildContext context;

  _ImageAndContext(this.provider, this.context);
}
