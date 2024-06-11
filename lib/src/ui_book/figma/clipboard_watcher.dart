

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/src/ui_book/figma/link.dart';

import '../../utils/value_stream.dart';

class ClipboardWatcher {
  late final Timer _timer;
  final proposedLink = ValueStream<String?>(null);

  ClipboardWatcher() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (kIsWeb) return;
      _check();
    });
  }

  void _check() async {
    var data = await Clipboard.getData('text/plain');
    var text = data?.text;
    String? urlToPropose;
    if (text != null) {
      try {
        FigmaId.parse(FigmaLink(text));
        urlToPropose = text;
      } catch (e) {
        // Not a valid link
      }
    }
    if (urlToPropose != proposedLink.value) {
      proposedLink.add(urlToPropose);
    }
  }

  void dispose() {
    proposedLink.dispose();
    _timer.cancel();
  }
}