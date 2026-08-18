import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware_app/src/changes/diff_view.dart';
import 'package:flutterware_app/src/changes/file_body.dart';
import 'package:flutterware_app/src/ui/theme.dart';

import 'app_theme.dart';

/// The changes screen's non-diff bodies, stacked: rendered markdown, an SVG
/// preview (and one with broken bytes, because the refusal is part of the
/// design), an untracked file's numbered lines, and the refusal notice.
///
/// The image differ is deliberately not here: its two sides come from a
/// worktree and a git revision, and a demo faking both would be a stage set —
/// it is reviewed live, on a real delta.

@Preview(name: 'File bodies', group: 'Changes', wrapper: wrapInAppTheme)
Widget fileBodies() => const _FileBodies();

@Preview(name: 'File bodies (dark)', group: 'Changes', wrapper: wrapInDarkTheme)
Widget fileBodiesDark() => const _FileBodies();

class _FileBodies extends StatefulWidget {
  const _FileBodies();

  @override
  State<_FileBodies> createState() => _FileBodiesState();
}

class _FileBodiesState extends State<_FileBodies> {
  final _scrollX = DiffScrollX();

  @override
  void dispose() {
    _scrollX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var label = context.type.sectionLabel;
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.xxl),
      children: [
        Text('MARKDOWN, RENDERED', style: label),
        const Gap(FwSpacing.sm),
        SizedBox(
          height: 300,
          child: MarkdownFileBody(
            content: _markdown,
            imageDirectory: '/nowhere/',
          ),
        ),
        const Gap(FwSpacing.xl),
        Text('SVG PREVIEW', style: label),
        const Gap(FwSpacing.sm),
        SizedBox(height: 220, child: SvgFileBody(bytes: utf8.encode(_svg))),
        const Gap(FwSpacing.xl),
        Text('SVG PREVIEW, BROKEN BYTES', style: label),
        const Gap(FwSpacing.sm),
        SizedBox(
          height: 120,
          child: SvgFileBody(bytes: utf8.encode('<not really svg')),
        ),
        const Gap(FwSpacing.xl),
        Text('UNTRACKED TEXT', style: label),
        const Gap(FwSpacing.sm),
        SizedBox(
          height: 200,
          child: Builder(
            builder: (context) {
              var style = diffTextStyle(context);
              var painter = TextPainter(
                text: TextSpan(text: 'M' * 10, style: style),
                textDirection: TextDirection.ltr,
              )..layout();
              return TextFileBody(
                lines: _lines,
                scrollX: _scrollX,
                charWidth: painter.width / 10,
              );
            },
          ),
        ),
        const Gap(FwSpacing.xl),
        Text('REFUSAL', style: label),
        const Gap(FwSpacing.sm),
        const FileBodyNotice(
          'This file is 3.2 MB — past what the viewer reads. Open it in '
          'your editor.',
        ),
      ],
    );
  }
}

const _markdown = '''
# A new design note

This file is **new on the branch**, so its diff would be a wall of `+`
lines. Rendered, it reads like what it is: prose.

- one point
- a second point with `inline code`
- a [link](https://example.com) that opens in the browser

```dart
var code = 'blocks keep their monospace';
```

![missing asset](assets/not-there.png)
''';

const _svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
  <rect x="8" y="8" width="104" height="64" rx="10" fill="#1877f2"/>
  <circle cx="60" cy="40" r="18" fill="white" fill-opacity="0.9"/>
</svg>
''';

const _lines = [
  'A scratch file an agent wrote thirty seconds ago.',
  'Not staged, not tracked, and until now not shown at all.',
  '',
  'Numbered like a diff, tinted like nothing — "every line is new"',
  "is the header's claim, and repeating it in green for the length",
  'of the file would be noise.',
  'This line is deliberately long enough to give the shared horizontal scroll a reason to exist, which takes a certain amount of typing to achieve.',
];
