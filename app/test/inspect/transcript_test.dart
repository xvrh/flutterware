import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/inspect/semantics_node.dart';
import 'package:flutterware_app/src/inspect/transcript.dart';

SemanticsSnapshotNode node({
  String label = '',
  String value = '',
  String hint = '',
  String tooltip = '',
  List<String> flags = const [],
  List<String> actions = const [],
  List<SemanticsSnapshotNode> children = const [],
}) => SemanticsSnapshotNode(
  rect: const Rect.fromLTWH(0, 0, 100, 40),
  label: label,
  value: value,
  hint: hint,
  tooltip: tooltip,
  flags: flags,
  actions: actions,
  children: children,
);

SemanticsTranscript read(List<SemanticsSnapshotNode> children) =>
    SemanticsTranscript.of(node(children: children));

void main() {
  test('speaks words in traversal order and skips silent structure', () {
    var transcript = read([
      node(
        children: [
          node(label: 'Menu', flags: ['isHeader']),
          node(label: 'Espresso', flags: ['isButton'], actions: ['tap']),
        ],
      ),
      node(label: 'Pay', flags: ['isButton'], actions: ['tap']),
    ]);
    expect(transcript.utterances.map((u) => u.words), [
      'Menu',
      'Espresso',
      'Pay',
    ]);
    expect(transcript.utterances.map((u) => u.index), [1, 2, 3]);
    expect(transcript.findingCount, 0);
  });

  test('composes label, value and tooltip into one announcement', () {
    var transcript = read([
      node(label: 'Volume', value: '80%', tooltip: 'Master output'),
    ]);
    expect(transcript.utterances.single.words, 'Volume, 80%, Master output');
  });

  test('hidden nodes are not read', () {
    var transcript = read([
      node(label: 'secret', flags: ['isHidden']),
      node(label: 'visible'),
    ]);
    expect(transcript.utterances.map((u) => u.words), ['visible']);
  });

  test('an interactive node with nothing to read is an error', () {
    var transcript = read([
      node(flags: ['isButton'], actions: ['tap']),
    ]);
    var finding = transcript.utterances.single.findings.single;
    expect(finding.severity, TranscriptSeverity.error);
    expect(finding.badge, 'nothing to read');
  });

  test('a hint rescues an otherwise empty control from the error', () {
    var transcript = read([
      node(hint: 'Double tap to pay', flags: ['isButton'], actions: ['tap']),
    ]);
    expect(transcript.utterances.single.findings, isEmpty);
  });

  test('a label without letters or digits is a symbol label', () {
    var transcript = read([
      node(label: '☕', flags: ['isButton'], actions: ['tap']),
      node(label: '→'),
      node(label: 'Café №3'),
    ]);
    expect(transcript.utterances.map((u) => u.findings.map((f) => f.badge)), [
      ['symbol label'],
      ['symbol label'],
      <String>[],
    ]);
  });

  test('identical announcements on interactives flag the later one', () {
    var transcript = read([
      node(label: 'View details', flags: ['isButton'], actions: ['tap']),
      node(label: 'view details ', flags: ['isButton'], actions: ['tap']),
    ]);
    var (first, second) = (transcript.utterances[0], transcript.utterances[1]);
    expect(first.findings, isEmpty);
    expect(second.findings.single.badge, 'duplicate of 1');
  });

  test('repeated static text is not a duplicate finding', () {
    var transcript = read([node(label: 'New'), node(label: 'New')]);
    expect(transcript.findingCount, 0);
  });

  test('a label that says its own role is flagged', () {
    var transcript = read([
      node(label: 'Pay button', flags: ['isButton'], actions: ['tap']),
      node(label: 'Buttonhole guide', flags: ['isButton'], actions: ['tap']),
    ]);
    expect(transcript.utterances[0].findings.single.badge, 'role in label');
    // 'Buttonhole' contains 'button' but is not the word — no finding.
    expect(transcript.utterances[1].findings, isEmpty);
  });
}
