import 'dart:core' as core;
import 'dart:core';
import 'package:flutter/material.dart';
import 'package:flutterware/ui_catalog.dart';

void main() async {
  runApp(UICatalog(
    title: 'My UI Catalog',
    catalog: () => catalog,
    appBuilder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: child,
    ),
    figmaLinksPath: '_ui_catalog_figma_links.json',
  ));
}

Map<String, dynamic> get catalog => {
      'Dashboard': _DashboardBook(),
      'Weather': {
        'Loading': CircularProgressIndicator(),
        'Logo': FlutterLogo(),
        'With text field': WithTextField(),
      },
      ...otherBooks,
    };

Map<String, dynamic> get otherBooks => {};

class _DashboardBook extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Figma(
      links: [
        'https://www.figma.com/design/aaa/bbb?node-id=93-2293',
      ],
      child: DashboardTile(
        title: context.uiCatalog.parameters.string('title', 'My title'),
        count: context.uiCatalog.parameters.int('count', 1, min: 0, max: 100),
        logoStyle: context.uiCatalog.parameters.picker(
            'logoStyle',
            {for (var v in FlutterLogoStyle.values) v.toString(): v},
            FlutterLogoStyle.markOnly),
        logoSize: context.uiCatalog.parameters.double('logoSize', 100),
        redBackground:
            context.uiCatalog.parameters.bool('redBackground', false),
      ),
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

class WithTextField extends StatelessWidget {
  const WithTextField({super.key});

  @override
  Widget build(BuildContext context) {
    var count = context.uiCatalog.parameters.int('counter', 0);
    return Scaffold(
      appBar: AppBar(
        title: Text('With text fields'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('Name'),
            subtitle: TextFormField(),
          ),
          for (var i = 0; i < count; i++) Text('Count $i'),
        ],
      ),
    );
  }
}
