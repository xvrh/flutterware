import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

/// A flow whose point is the document it produces, rather than the screen
/// that announces it.
void main() {
  scenario('Exports a receipt', (s) async {
    await s.pumpWidget(const _ReceiptApp());
    await s.tap('Export');
    // A real flow gets these back from the app — `tester.runAsync(() =>
    // report.generatePdf())` and its like. What matters here is where they
    // go: attached before the capture, they ride the next step.
    s.attach(
      'receipt',
      utf8.encode('{"total": 12.5, "currency": "EUR"}'),
      fileName: 'receipt.json',
      mimeType: 'application/json',
    );
    // The push the backend would have sent when the export landed. The
    // viewer draws it the way the recipient's phone would: a banner over
    // the screen it arrived on.
    s.notification('Receipt #1042 is ready to download', title: 'Receipts');
    await s.screen('Exported');
    // Fetched after the final screen: it lands on that step, marked as
    // arriving after it, and the story ends with the document.
    s.attach(
      'summary',
      utf8.encode('Receipt #1042\nTotal 12.50 EUR\nPaid by card'),
      fileName: 'summary.txt',
      mimeType: 'text/plain',
    );
  });
}

class _ReceiptApp extends StatefulWidget {
  const _ReceiptApp();

  @override
  State<_ReceiptApp> createState() => _ReceiptAppState();
}

class _ReceiptAppState extends State<_ReceiptApp> {
  var _exported = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _exported
              ? const Text('Receipt exported')
              : TextButton(
                  onPressed: () => setState(() => _exported = true),
                  child: const Text('Export'),
                ),
        ),
      ),
    );
  }
}
