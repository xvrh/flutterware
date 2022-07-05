import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChangeLogPage extends StatefulWidget {
  const ChangeLogPage({super.key});

  @override
  State<ChangeLogPage> createState() => _ChangeLogPageState();
}

class _ChangeLogPageState extends State<ChangeLogPage> {
  late Future<String> _changelog;

  @override
  void initState() {
    super.initState();

    _changelog = _loadChangelog();
  }

  Future<String> _loadChangelog() async {
    var file = File('../CHANGELOG.md');
    return file.readAsString();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _changelog,
      builder: (context, snapshot) {
        return Markdown(data: snapshot.data ?? '');
      },
    );
  }
}
