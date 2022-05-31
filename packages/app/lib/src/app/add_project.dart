import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_studio_app/src/utils/ui/message_dialog.dart';
import 'package:flutter_studio_app/src/workspace.dart';
import 'package:pub_semver/pub_semver.dart';

import '../ui.dart';
import '../flutter_sdk.dart';
import '../utils/data_loader.dart';

Future<void> openProject(BuildContext context, Workspace workspace) async {
  var path = await getDirectoryPath();
  await showDialog(
    context: context,
    builder: (context) => AddProjectScreen(
      workspace,
      initialPath: path,
    ),
  );
}

class AddProjectScreen extends StatefulWidget {
  final Workspace workspace;
  final String? initialPath;

  const AddProjectScreen(
    this.workspace, {
    super.key,
    this.initialPath,
  });

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  final _projectFolderController = TextEditingController();
  final _flutterSdkController = TextEditingController();
  FlutterSdk? _selectedSdk;
  Set<FlutterSdk>? _knownSdks;

  @override
  void initState() {
    super.initState();
    _loadSdk();

    var initialPath = widget.initialPath;
    if (initialPath != null) {
      _projectFolderController.text = initialPath;
    }
  }

  void _loadSdk() async {
    var sdks = await widget.workspace.possibleFlutterSdks();
    if (mounted) {
      setState(() {
        _knownSdks = sdks;
      });
      if (sdks.isNotEmpty) {
        _setSdk(sdks.first);
      }
    }
  }

  void _setSdk(FlutterSdk? sdk) {
    setState(() {
      _selectedSdk = sdk;
      _flutterSdkController.text = sdk?.root ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    var knownSdks = _knownSdks;
    return AlertDialog(
      title: Text('Open project'),
      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 25),
      content: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _projectFolderController,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Flutter project path',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.folder_open),
                  onPressed: () async {
                    var newPath = await getDirectoryPath();
                    if (newPath != null) {
                      _projectFolderController.text = newPath;
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _flutterSdkController,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Flutter SDK',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      suffixIcon: knownSdks != null && knownSdks.isNotEmpty
                          ? PopupMenuButton<FlutterSdk>(
                              constraints: const BoxConstraints(
                                minWidth: 2 * 56,
                                maxWidth: 10 * 56,
                              ),
                              shape: RoundedRectangleBorder(
                                  side: BorderSide(
                                      width: 1, color: Colors.black26)),
                              itemBuilder: (context) => [
                                for (var sdk in knownSdks)
                                  PopupMenuItem(
                                    value: sdk,
                                    child: ListTile(
                                      title: Text(sdk.root),
                                      subtitle: _SdkVersionText(sdk),
                                    ),
                                  ),
                              ],
                              onSelected: (sdk) {
                                _setSdk(sdk);
                              },
                            )
                          : null,
                    ),
                    onChanged: (s) {
                      setState(() {
                        _selectedSdk = FlutterSdk(s);
                      });
                    },
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.folder_open),
                  onPressed: _pickSdk,
                ),
              ],
            ),
            if (_selectedSdk != null) _SdkVersionText(_selectedSdk!),
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
          style: AppTheme.filledButton(context),
          onPressed: () {},
          child: Text('Open'),
        ),
      ],
    );
  }

  void _pickSdk() async {
    var sdkPath = await getDirectoryPath();
    if (sdkPath != null) {
      var flutterSdk = await FlutterSdk.tryFind(sdkPath);

      if (!mounted) return;
      if (flutterSdk == null) {
        await showMessageDialog(context,
            message: 'This folder is not recognized as a Flutter SDK path');
      }
      _setSdk(flutterSdk);
    }
  }

  @override
  void dispose() {
    _projectFolderController.dispose();
    _flutterSdkController.dispose();
    super.dispose();
  }
}

class _SdkVersionText extends StatelessWidget {
  final FlutterSdk sdk;

  const _SdkVersionText(this.sdk);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Snapshot<Version>>(
      valueListenable: sdk.version,
      builder: (context, value, child) {
        if (value.hasError) {
          return Tooltip(
            message: value.error?.toString() ?? '',
            child: Text(
              'Invalid Flutter SDK',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        var data = value.data;
        if (data == null) {
          return Text('');
        }

        return Text('Flutter v$data');
      },
    );
  }
}
