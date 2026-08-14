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
    // [AlertDialog], like the teardown and web-export dialogs: this was a bare
    // [Dialog] with a hand-built title block and a hand-built action row, so
    // the app's three dialogs sat at three corner radii with three button
    // treatments.
    return AlertDialog(
      backgroundColor: colors.bg,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hand off ${widget.count} '
            '${widget.count == 1 ? 'comment' : 'comments'}',
            style: context.type.heading,
          ),
          const Gap(FwSpacing.xxs),
          Text(
            [
              widget.worktree,
              if (widget.base case var it?) 'against $it',
            ].join('  ·  '),
            style: context.type.caption.copyWith(color: colors.mut2),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Channel(
              on: _route == HandoffRoute.copy,
              title: 'Copy as markdown',
              body: 'Paste it straight into the agent’s chat.',
              onTap: () => setState(() => _route = HandoffRoute.copy),
            ),
            const Gap(FwSpacing.md),
            _Channel(
              on: _route == HandoffRoute.file,
              title: 'Save to a file…',
              body:
                  'Point the agent at the path. Save it outside the checkout '
                  'unless you want it showing up as an untracked row on this '
                  'very screen.',
              onTap: () => setState(() => _route = HandoffRoute.file),
            ),
            const Gap(FwSpacing.xl),
            const _Label('What leaves'),
            const Gap(FwSpacing.sm),
            // **What leaves, shown before it leaves.** A handoff you cannot
            // preview is one you re-check by pasting it somewhere else first.
            //
            // **Flexible, then capped** — not capped alone. A flat 300 px is a
            // height the dialog does not have in a 600 px window, and the
            // overflow it caused was the preview pushing the buttons off the
            // bottom: the one part of the sheet that may not go missing.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(FwSpacing.lg),
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
                      style: context.type.mono.copyWith(
                        color: colors.mut,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Gap(FwSpacing.lg),
            Text(
              _failure ??
                  'Moves these to history. You can copy a past batch again.',
              style: context.type.caption.copyWith(
                color: _failure == null ? colors.mut3 : colors.red,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Tappable.builder(
          onTap: () => Navigator.of(context).pop(),
          builder: (context, hovered) => Padding(
            padding: const EdgeInsets.all(FwSpacing.sm),
            child: Text(
              'Cancel',
              style: context.type.caption.copyWith(
                color: hovered ? colors.ink : colors.mut2,
              ),
            ),
          ),
        ),
        const Gap(FwSpacing.md),
        // The house primary — the same one the composer and the Review footer
        // wear. This was the last solid accent fill in the feature, which made
        // the loudest object on the screen the confirmation of an action you
        // had already chosen.
        Tappable.builder(
          onTap: _busy ? null : () => unawaited(_go()),
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(
              horizontal: FwSpacing.xl,
              vertical: FwSpacing.md,
            ),
            decoration: BoxDecoration(
              color: _busy
                  ? null
                  : hovered
                  ? colors.accentSoft2
                  : colors.accentSoft,
              borderRadius: BorderRadius.circular(context.radii.radius),
              border: Border.all(color: _busy ? colors.line : colors.accent),
            ),
            child: Text(
              _busy ? 'Handing off…' : 'Hand off',
              style: context.type.caption.copyWith(
                color: _busy ? colors.mut3 : colors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A heading inside the sheet. Uppercase `fieldLabel`, the app's section voice.
class _Label extends StatelessWidget {
  const _Label(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: context.type.fieldLabel.copyWith(color: context.colors.mut),
  );
}

/// One of the two ways a batch can leave.
///
/// **A card, not a band.** The chosen one was a full-bleed accent stripe across
/// the dialog and the other was bare text on the background, so the two options
/// did not look like two of anything — only the radio glyph said they were a
/// pair. Bordered and inset, they are the same object in two states, which is
/// what a choice looks like.
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
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: on
              ? colors.accentSoft
              : hovered
              ? colors.hoverOverlay
              : null,
          borderRadius: BorderRadius.circular(context.radii.radius),
          border: Border.all(color: on ? colors.accent : colors.line),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FwSpacing.lg,
          vertical: FwSpacing.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
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
                  Text(
                    title,
                    style: context.type.bodySmall.copyWith(
                      color: on ? colors.accent : colors.ink,
                    ),
                  ),
                  const Gap(FwSpacing.xxs),
                  Text(
                    body,
                    style: context.type.caption.copyWith(color: colors.mut2),
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
