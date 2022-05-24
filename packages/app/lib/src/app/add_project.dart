import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_studio_app/src/workspace.dart';

import '../ui.dart';
import '../utils/flutter_sdk.dart';

Future<void> openProject(BuildContext context, Workspace workspace) async {
  await showDialog(
      context: context, builder: (context) => AddProjectScreen(workspace));
}

class AddProjectScreen extends StatefulWidget {
  final Workspace workspace;

  const AddProjectScreen(this.workspace, {super.key});

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  final _projectFolderController = TextEditingController();
  final _flutterSdkController = TextEditingController();
  late Future<Set<FlutterSdk>> _knownSdks;

  @override
  void initState() {
    super.initState();
    _knownSdks = widget.workspace.possibleFlutterSdks();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<FlutterSdk>>(
        future: _knownSdks,
        builder: (context, snapshot) {
          var knownSdks = snapshot.data ?? {};
          print(snapshot.error);
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
                            hintText: 'Your Flutter project folder path',
                            labelText: 'Project path',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.folder_open),
                        onPressed: () {
                          getDirectoryPath();
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
                            hintText: 'Select the Flutter SDK path',
                            labelText: 'Flutter SDK',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                      ),
                      PopupMenuButton(
                        itemBuilder: (context) => [
                          for (var sdk in knownSdks)
                            PopupMenuItem(
                              child: ListTile(
                                title: Text(sdk.root),
                                subtitle: Text(sdk.version.toString()),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Text('Flutter v3.0.1'),
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
        });
  }

  @override
  void dispose() {
    _projectFolderController.dispose();
    _flutterSdkController.dispose();
    super.dispose();
  }
}
