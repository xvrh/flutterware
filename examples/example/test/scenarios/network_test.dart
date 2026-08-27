import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutterware/flutter_test.dart';

/// What a screen that loads an image over http does in a scenario, and the
/// three answers there are.
///
/// The default is that nothing leaves the process, so a screen like this one
/// used to render a blank box and say nothing about why — worse over https,
/// where the request neither succeeded nor failed and the step simply reported
/// a settled, empty frame. Now it says so, and stating an answer is one line.
void main() {
  scenario('nothing stated — the refusal is on the step', (s) async {
    await s.pumpWidget(const _Profile(avatar: 'https://example.com/ada.png'));
    await s.screen('the broken avatar');
    // The step's Events pane carries `GET https://example.com/ada.png`,
    // marked as an error, with the whole refusal as its body.
    expect(s.network.requests.single.outcome, 'off');
  });

  scenario('stated — a real PNG, and no socket anywhere', (s) async {
    s.network.image(
      'https://example.com/ada.png',
      scenarioPlaceholderPng(width: 96, height: 96, red: 0x4C, green: 0x7A),
    );
    await s.pumpWidget(const _Profile(avatar: 'https://example.com/ada.png'));
    await s.screen('the avatar');
  });

  scenario('the phone is on a train', (s) async {
    s.network.any(throws: const SocketException('Network is unreachable'));
    await s.pumpWidget(const _Profile(avatar: 'https://example.com/ada.png'));
    await s.screen('the offline state');
  });
}

class _Profile extends StatelessWidget {
  const _Profile({required this.avatar});

  final String avatar;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.network(
                avatar,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Container(
                  width: 96,
                  height: 96,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.person_outlined, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Ada Lovelace'),
          ],
        ),
      ),
    ),
  );
}
