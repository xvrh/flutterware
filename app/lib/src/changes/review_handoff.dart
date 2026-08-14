/// Handing the batch over, and closing it.
///
/// **The markdown is the artefact; the routes are two ways of moving it.** The
/// clipboard and a file render the identical text — see [reviewMarkdown] — so
/// there is one format to keep readable, one to test, and no way for the thing
/// you previewed to differ from the thing that left.
///
/// **Handing off is what closes a batch, and it is the only thing that does.**
/// There is no *Clear*: a button that empties the list asks *are you sure*
/// about work whose only copy is on this screen, and it makes *I already sent
/// these* and *I gave up on these* the same gesture. Accumulate, hand off,
/// history.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tappable.dart';
import '../ui/theme.dart';
import 'review_comment.dart';

/// How a batch left.
enum HandoffRoute {
  /// Onto the clipboard, to be pasted into the agent's chat.
  copy,

  /// Written to a file the agent can be pointed at.
  file,
}

/// What the sheet decided, or null if it was cancelled.
typedef HandoffResult = ({HandoffRoute route, String? savedTo});

/// Asks how the batch should go, shows what will leave, and does it.
///
/// Returns null when nothing left — cancelled, or a save the user backed out
/// of. The caller closes the batch only on a non-null answer, so an abandoned
/// save cannot silently file six comments away as sent.
Future<HandoffResult?> showHandoffSheet(
  BuildContext context, {
  required String markdown,
  required int count,
  required String worktree,
  String? base,
}) => showDialog<HandoffResult>(
  context: context,
  builder: (context) => _HandoffSheet(
    markdown: markdown,
    count: count,
    worktree: worktree,
    base: base,
  ),
);

class _HandoffSheet extends StatefulWidget {
  const _HandoffSheet({
    required this.markdown,
    required this.count,
    required this.worktree,
    this.base,
  });

  final String markdown;
  final int count;
  final String worktree;
  final String? base;

  @override
  State<_HandoffSheet> createState() => _HandoffSheetState();
}

class _HandoffSheetState extends State<_HandoffSheet> {
  var _route = HandoffRoute.copy;
  var _busy = false;

  /// What went wrong, shown in place.
  ///
  /// A handoff that fails silently is the worst outcome here: the sheet would
  /// simply sit there, and the obvious reading of that is *the button does not
  /// work*. A disk that is full and a clipboard channel that is not answering
  /// are both things the person in front of it can act on.
  String? _failure;

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      switch (_route) {
        case HandoffRoute.copy:
          await Clipboard.setData(ClipboardData(text: widget.markdown));
          if (mounted) {
            Navigator.of(
              context,
            ).pop((route: HandoffRoute.copy, savedTo: null));
          }
        case HandoffRoute.file:
          var location = await getSaveLocation(
            suggestedName: _suggestedName(widget.worktree),
            acceptedTypeGroups: const [
              XTypeGroup(label: 'Markdown', extensions: ['md']),
            ],
          );
          // Backing out of the picker is backing out of the handoff. Closing
          // the batch here would file the comments as sent to nowhere.
          if (location == null) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          await File(location.path).writeAsString(widget.markdown);
          if (mounted) {
            Navigator.of(
              context,
            ).pop((route: HandoffRoute.file, savedTo: location.path));
          }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Dialog(
      backgroundColor: colors.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FwSpacing.xxl,
                FwSpacing.xl,
                FwSpacing.xxl,
                FwSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hand off ${widget.count} '
                    '${widget.count == 1 ? 'comment' : 'comments'}',
                    style: context.type.bodyStrong,
                  ),
                  const Gap(FwSpacing.xxs),
                  Text(
                    [
                      widget.worktree,
                      if (widget.base case var it?) 'against $it',
                    ].join(' · '),
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
                ],
              ),
            ),
            _Channel(
              on: _route == HandoffRoute.copy,
              title: 'Copy as markdown',
              body: 'Paste it straight into the agent’s chat.',
              onTap: () => setState(() => _route = HandoffRoute.copy),
            ),
            _Channel(
              on: _route == HandoffRoute.file,
              title: 'Save to a file…',
              body:
                  'Point the agent at the path. Save it outside the checkout '
                  'unless you want it showing up as an untracked row on this '
                  'very screen.',
              onTap: () => setState(() => _route = HandoffRoute.file),
            ),
            const Gap(FwSpacing.md),
            // **What leaves, shown before it leaves.** A handoff you cannot
            // preview is one you re-check by pasting it somewhere else first.
            Flexible(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: FwSpacing.xxl),
                padding: const EdgeInsets.all(FwSpacing.md),
                decoration: BoxDecoration(
                  color: colors.panel2,
                  borderRadius: BorderRadius.circular(
                    context.radii.radiusSmall,
                  ),
                  border: Border.all(color: colors.line),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.markdown,
                    style: context.type.micro.copyWith(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const [
                        'Menlo',
                        'Consolas',
                        'Courier New',
                      ],
                      color: colors.mut,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(FwSpacing.xxl),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _failure ??
                          'Moves these to history. You can copy a past batch '
                              'again.',
                      style: context.type.micro.copyWith(
                        color: _failure == null ? colors.mut3 : colors.red,
                      ),
                    ),
                  ),
                  Tappable.builder(
                    onTap: () => Navigator.of(context).pop(),
                    builder: (context, hovered) => Padding(
                      padding: const EdgeInsets.all(FwSpacing.sm),
                      child: Text(
                        'Cancel',
                        style: context.type.bodySmall.copyWith(
                          color: hovered ? colors.ink : colors.mut2,
                        ),
                      ),
                    ),
                  ),
                  const Gap(FwSpacing.md),
                  Tappable.builder(
                    onTap: _busy ? null : () => unawaited(_go()),
                    builder: (context, hovered) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FwSpacing.xl,
                        vertical: FwSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: _busy
                            ? colors.mut3
                            : hovered
                            ? colors.accentDark
                            : colors.accent,
                        borderRadius: BorderRadius.circular(
                          context.radii.radiusSmall,
                        ),
                      ),
                      child: Text(
                        'Hand off',
                        style: context.type.bodySmall.copyWith(
                          color: colors.primaryOnMenu,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Channel extends StatelessWidget {
  const _Channel({
    required this.on,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool on;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Tappable.builder(
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: on
            ? colors.accentSoft
            : hovered
            ? colors.hoverOverlay
            : null,
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.xxl,
          vertical: FwSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: FwIconSize.md,
                color: on ? colors.accent : colors.mut3,
              ),
            ),
            const Gap(FwSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.type.bodySmall),
                  const Gap(FwSpacing.xxs),
                  Text(
                    body,
                    style: context.type.micro.copyWith(color: colors.mut2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `review-<worktree>.md`, with anything a filesystem would object to replaced.
String _suggestedName(String worktree) {
  var cleaned = worktree.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return 'review-${cleaned.isEmpty ? 'changes' : cleaned}.md';
}
