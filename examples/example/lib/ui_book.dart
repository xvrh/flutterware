import 'dart:core' as core;
import 'dart:core';
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
      'Dashboard': _DashboardBook(),
      'Weather': {
        'Loading': SizedBox(),
        'Error': ErrorWidget(''),
      },
      ...otherBooks,
    };

Map<String, dynamic> get otherBooks => {};

class _DashboardBook extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DashboardTile(
      title: context.book.knobs.string('title', 'My title'),
      count: context.book.knobs.int('count', 1, min: 0, max: 100),
      logoStyle: context.book.knobs.picker(
          'logoStyle',
          {for (var v in FlutterLogoStyle.values) v.toString(): v},
          FlutterLogoStyle.markOnly),
      logoSize: context.book.knobs.double('logoSize', 100),
      redBackground: context.book.knobs.bool('redBackground', false),
    );
  }
}

// lib

class DashboardTile extends StatelessWidget {
  final String title;
  final int count;
  final FlutterLogoStyle logoStyle;
  final double logoSize;
  final bool redBackground;

  const DashboardTile({
    super.key,
    required this.title,
    required this.count,
    required this.logoStyle,
    required this.logoSize,
    required this.redBackground,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: redBackground ? Colors.red : null,
        child: ListView(
          children: [
            FlutterLogo(
              style: logoStyle,
              size: logoSize,
            ),
            Text(title),
            for (var i = 0; i < count; i++) Text('Item $i')
          ],
        ),
      ),
    );
  }
}
