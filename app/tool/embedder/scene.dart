import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Color(0xFF1565C0),
      body: Center(
        child: Text('Flutterware embedder',
            style: TextStyle(color: Colors.white, fontSize: 48)),
      ),
    ),
  ));
}
