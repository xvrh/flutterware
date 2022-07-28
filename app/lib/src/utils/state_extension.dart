import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';
import 'ui/loading.dart';

extension StateExtension on State {
  Future<T> withLoader<T>(FutureOr<T> Function(Sink<String>) callback,
      {String? message}) async {
    var messages = BehaviorSubject<String>.seeded(message ?? '');
    var loadingEntry = showLoadingWithMessages(context, messages);
    try {
      return await callback(messages.sink);
    } finally {
      await messages.close();
      loadingEntry.remove();
    }
  }
}
