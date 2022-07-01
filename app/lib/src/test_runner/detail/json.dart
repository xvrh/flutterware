import 'dart:convert';
import 'dart:typed_data';
import 'package:flutterware/internals/test_runner.dart' hide TextInfo;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../detail.dart';

class JsonDetail extends StatelessWidget {
  final ProjectInfo project;
  final ScenarioRun run;
  final Screen screen;
  final JsonInfo json;

  const JsonDetail(
    this.project,
    this.run,
    this.screen,
    this.json, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var body = SelectableText(json.data);

    return DetailSkeleton(
      project,
      run,
      screen,
      main: body,
      sidebar: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 4),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: OutlinedButton(
                  onPressed: () async {
                    var path = await getSavePath(
                      suggestedName: json.fileName,
                    );
                    if (path != null) {
                      var data = Uint8List.fromList(utf8.encode(json.data));
                      var file = XFile.fromData(data,
                          name: p.basename(path), mimeType: 'application/json');
                      await file.saveTo(path);
                    }
                  },
                  child: Text('Download file'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: OutlinedButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: json.data));
                  },
                  child: Text('Copy to clipboard'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
