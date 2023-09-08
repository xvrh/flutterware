import 'package:flutter/material.dart';

class ErrorPanel extends StatelessWidget {
  final String message;
  final void Function()? onRetry;

  ErrorPanel({required this.message, super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Icon(
              Icons.error,
              size: 40,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (onRetry != null)
            OutlinedButton(
              onPressed: onRetry,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0),
                child: Icon(Icons.refresh),
              ),
            ),
        ],
      ),
    );
  }
}
