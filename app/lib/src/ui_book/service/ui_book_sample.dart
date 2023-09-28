import 'package:flutter/material.dart';
import 'package:flutterware/ui_book.dart';

void main() async {
  runApp(UIBook(
    title: 'My Storybook',
    books: () => books,
    appBuilder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: child,
    ),
  ));
}

Map<String, dynamic> get books => {
      'Sample 1': _MyView(),
    };

class _MyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FlutterLogo(
        size: context.book.knobs.double('size', 50, min: 20, max: 100),
      ),
    );
  }
}
