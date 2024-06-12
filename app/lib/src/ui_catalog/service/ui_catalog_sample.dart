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
  ));
}

Map<String, dynamic> get catalog => {
      'Sample 1': _MyView(),
    };

class _MyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: FlutterLogo(
        size:
            context.uiCatalog.parameters.double('size', 50, min: 20, max: 100),
      ),
    );
  }
}
