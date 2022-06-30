import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/icon/image_provider.dart';
import 'package:flutter_studio_app/src/utils/state_extension.dart';
import 'package:flutter_studio_app/src/utils/ui/loading.dart';
import '../project.dart';
import '../utils/async_value.dart';
import '../utils/ui/error_panel.dart';
import '../utils/ui/warning_box.dart';
import 'icons.dart';
import 'package:path/path.dart' as p;

class IconScreen extends StatelessWidget {
  final Project project;

  const IconScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ValueListenableBuilder<Snapshot<AppIcons>>(
      valueListenable: project.icons.icons,
      builder: (context, snapshot, child) {
        var data = snapshot.data;
        var error = snapshot.error;
        return ListView(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'App icon',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (data != null && data.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _changeIcon(context, data),
                    icon: Icon(Icons.photo),
                    label: Text('Change icon'),
                  ),
                PopupMenuButton(
                    itemBuilder: (context) => [
                          PopupMenuItem(
                            child: Text('Reload icons'),
                            onTap: () {
                              project.icons.icons.refresh();
                              project.icons.sample.refresh();
                            },
                          ),
                        ]),
              ],
            ),
            const SizedBox(height: 30),
            if (data != null)
              ..._icons(context, data)
            else if (error != null)
              ErrorPanel(
                message: 'Failed to load icons',
                onRetry: project.icons.icons.refresh,
              )
            else
              LoadingPanel(),
          ],
        );
      },
    );
  }

  void _changeIcon(BuildContext context, AppIcons icons) async {
    await showDialog(
        context: context,
        builder: (context) => _ChangeIconDialog(project, icons));
  }

  Iterable<Widget> _icons(BuildContext context, AppIcons icons) sync* {
    var theme = Theme.of(context);

    for (var entry in icons.icons.entries) {
      if (entry.value.isEmpty) continue;

      var files = entry.value.sortedByCompare((e) => e.path, compareNatural);

      yield Text(
        ' ${entry.key.name}',
        style: theme.textTheme.bodyMedium,
      );
      yield const SizedBox(height: 5);
      var table = Table(
        columnWidths: {
          0: FixedColumnWidth(80),
          1: FixedColumnWidth(100),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var icon in files)
            TableRow(
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                    ),
                    child: Image(
                      image: AppIconImageProvider(icon),
                    ),
                  ),
                ),
                Text(
                  '${icon.originalWidth}x${icon.originalHeight}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  p.relative(icon.path, from: project.directory.path),
                  style: const TextStyle(color: Colors.black45),
                ),
              ],
            ),
        ],
      );
      yield Card(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: table,
      ));
      yield const SizedBox(height: 30);
    }
  }
}

class _ChangeIconDialog extends StatefulWidget {
  final Project project;
  final AppIcons icons;

  const _ChangeIconDialog(this.project, this.icons);

  @override
  State<_ChangeIconDialog> createState() => __ChangeIconDialogState();
}

class __ChangeIconDialogState extends State<_ChangeIconDialog> {
  final _platformSwitches = <IconPlatform, bool>{
    for (var platform in IconPlatform.values) platform: true,
  };
  Uint8List? _image;

  @override
  Widget build(BuildContext context) {
    var biggest = widget.icons.biggestForPlatforms(_selectedPlatforms);
    var image = _image;
    return AlertDialog(
      title: Text('Change icon'),
      content: SizedBox(
        width: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: _pick,
              icon: Icon(Icons.file_upload),
              label: Text('Choose icon'),
            ),
            if (image != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Image.memory(image),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  'Recommended size: ${biggest.originalWidth}x${biggest.originalHeight}'),
            ),
            for (var platform in widget.icons.icons.keys)
              Row(
                children: [
                  Switch(
                      value: _platformSwitches[platform]!,
                      onChanged: (v) {
                        setState(() {
                          _platformSwitches[platform] = v;
                        });
                      }),
                  Text(platform.name),
                ],
              ),
            WarningBox(
              message: 'This feature is limited and experimental.  \n'
                  'If you have suggestions to improve it, [open issues on Github](https://github.com/xvrh/flutter_studio)',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: image != null ? () => _apply(image) : null,
          child: Text('Apply'),
        ),
      ],
    );
  }

  void _pick() async {
    var imagesGroup = XTypeGroup(
      label: 'images',
      extensions: ['png'],
    );
    var result = await openFile(acceptedTypeGroups: [imagesGroup], initialDirectory: widget.project.absolutePath);
    if (result != null) {
      var bytes = await result.readAsBytes();
      setState(() {
        _image = bytes;
      });
    }
  }

  List<IconPlatform> get _selectedPlatforms => _platformSwitches.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  void _apply(Uint8List image) async {
    await withLoader((_) async {
      await widget.icons.changeIcon(image, platforms: _selectedPlatforms);
    }, message: 'Applying new icon...');

    unawaited(widget.project.icons.icons.refresh());
    unawaited(widget.project.icons.sample.refresh());
    if (mounted) {
      Navigator.pop(context);
    }
  }
}
