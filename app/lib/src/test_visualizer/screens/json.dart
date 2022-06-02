import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';

class JsonBody extends StatelessWidget {
  final ScenarioRun run;
  final JsonInfo json;

  const JsonBody(this.run, this.json, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        scaleEnabled: false,
        constrained: false,
        child: HighlightView(
          json.data,
          padding: EdgeInsets.all(10),
          language: 'json',
          theme: githubTheme,
        ),
      ),
    );
  }
}
