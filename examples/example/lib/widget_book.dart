import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutterware/widget_book.dart';

void main() {
  runApp(WidgetBook(
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
      title: context.book.string('title', 'My title'),
      count: context.book.int('count', 1),
    );
  }
}

// lib

class DashboardTile extends StatelessWidget {
  final String title;
  final int count;

  const DashboardTile({super.key, required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FlutterLogo(),
        Text('Tile'),
      ],
    );
  }
}
