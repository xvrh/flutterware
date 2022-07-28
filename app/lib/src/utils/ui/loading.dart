import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

class LoadingPanel extends StatelessWidget {
  final String? message;

  const LoadingPanel({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _LoadingView(
        message: message,
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String? message;

  const _LoadingView({this.message});

  @override
  Widget build(BuildContext context) {
    var message = this.message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(),
        if (message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          )
      ],
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  final String? message;
  final VoidCallback? onCancel;

  const _LoadingDialog({this.message, this.onCancel});

  @override
  Widget build(BuildContext context) {
    var content = _LoadingView(message: message);

    if (onCancel == null) {
      return SimpleDialog(
        contentPadding: EdgeInsets.symmetric(vertical: 60),
        children: [
          Center(child: content),
        ],
      );
    } else {
      return AlertDialog(
        content: content,
        actions: [
          TextButton(
            onPressed: onCancel,
            child: Text('Cancel'),
          )
        ],
      );
    }
  }
}

OverlayEntry showLoading(BuildContext context,
    {String? message, VoidCallback? onCancel}) {
  return _showLoading(
    context,
    _LoadingDialog(
      message: 'Loading...',
      onCancel: onCancel,
    ),
  );
}

OverlayEntry showLoadingWithMessages(
    BuildContext context, Stream<String> messages,
    {VoidCallback? onCancel}) {
  return _showLoading(
    context,
    StreamBuilder<String>(
      stream: messages,
      initialData:
          messages is ValueStream<String> ? messages.valueOrNull : null,
      builder: (context, snapshot) {
        var data = snapshot.data;
        String message;
        if (data == null || data.isEmpty) {
          message = 'Loading...';
        } else {
          message = data;
        }

        return _LoadingDialog(
          message: message,
          onCancel: onCancel,
        );
      },
    ),
  );
}

OverlayEntry _showLoading(BuildContext context, Widget content) {
  var entry = OverlayEntry(builder: (context) {
    return Container(
      alignment: Alignment.center,
      color: Colors.black12,
      child: content,
    );
  });
  Overlay.of(context)!.insert(entry);

  return entry;
}

class LoadingDialogOverlay extends StatelessWidget {
  final String? message;

  const LoadingDialogOverlay({this.message, super.key});

  @override
  Widget build(BuildContext context) {
    var dialog = SimpleDialog(
      children: [
        Center(child: _LoadingView(message: message)),
      ],
    );

    return Container(
      alignment: Alignment.center,
      color: const Color(0x80000000),
      child: dialog,
    );
  }
}
