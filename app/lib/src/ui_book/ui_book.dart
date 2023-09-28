import 'dart:io';

import 'package:flutter/material.dart';
import '../app/paths.dart' as paths;
import '../project.dart';
import '../ui/side_menu.dart';

class UIBookScreen extends StatelessWidget {
  final Project project;

  const UIBookScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NetworkInterface>>(
        future: NetworkInterface.list(),
        builder: (context, snapshot) {
          var interfaces = StringBuffer();
          for (var interface in snapshot.data ?? <NetworkInterface>[]) {
            interfaces.writeln(
                '${interface.name} ${interface.addresses} ${interface.index}');
          }

          return Center(
            child: Column(
              children: [
                ElevatedButton(
                    onPressed: () {
                      project.uiBook.start();
                    },
                    child: Text('Start')),
                Text('''
UIBook

Steps:
- Start the flutter-tester device
        - Check if there is an example/widget_book.dart, else create it
        - Create the entry point wrapping the target example/widget_book.dart
        - Start the server
        - Run flutter run -d flutter-tester
        - Wait for the client to connect
        - Implement the communication protocol (send selected screen, take screenshot)
        - Allow to hot-reload/hot-restart
        - Create new device
        $interfaces
'''),
              ],
            ),
          );
        });
  }
}

class UIBookMenu extends StatelessWidget {
  const UIBookMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: MenuLink(
        url: paths.uiBook,
        title: Text('UI Book'),
      ),
    );
  }
}
