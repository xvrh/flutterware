import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

const _members = [
  ('DS', 'Dr. Sarah Chen', 'Dermatologist'),
  ('DL', 'Dr. Lena Kruger', 'Pathologist'),
  ('DJ', 'Dr. James Okafor', 'Plastic Surgeon'),
];

const _longText = [
  (
    'VL',
    'Dr. Valentina Lowenstein-Schwarzenberg',
    'Senior Consultant in Dermatology and Venereology',
  ),
];

@Demo(name: 'Members', wrapper: wrapInApp)
Widget avatarTileMembers() => _list(_members);

@Demo(name: 'Empty', wrapper: wrapInApp)
Widget avatarTileEmpty() => _list(const []);

@Demo(name: 'Long text', wrapper: wrapInApp)
Widget avatarTileLongText() => _list(_longText);

Widget _list(List<(String, String, String)> people) {
  return Scaffold(
    appBar: AppBar(title: const Text('Team')),
    body: people.isEmpty
        ? const Center(child: Text('No members yet'))
        : ListView(
            children: [
              for (var (initials, name, subtitle) in people)
                ListTile(
                  leading: CircleAvatar(child: Text(initials)),
                  title: Text(name),
                  subtitle: Text(subtitle),
                ),
            ],
          ),
  );
}

/// The real-device path: every demo file is its own runnable app.
void main() => runApp(wrapInApp(avatarTileMembers()));
