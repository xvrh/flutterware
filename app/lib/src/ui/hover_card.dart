import 'dart:async';

import 'package:flutter/widgets.dart';

import 'popover.dart';

/// A [Popover] that opens on **hover**, the way a tooltip does.
///
/// ## Why this exists at all
///
/// The explorer's changes cell had both: a `Tooltip` over the whole cell and a
/// click-popover over the 4 px fingerprint bar inside it. That is one target
/// with two interactions, and the cheap one wins every time — hovering always
/// worked and always produced the *text*, so the card was unreachable in
/// practice and unknown in principle. Driving the real window, every click
/// aimed at the bar landed on the row behind it instead.
///
/// So the card replaces the tip rather than competing with it: one gesture, one
/// result, on a target the size of the cell.
///
/// ## The three timings, and what each is for
///
/// - [enterDelay] — a pointer crossing the list on its way somewhere else must
///   not open anything. This is the difference between a hover card and a
///   screen that flashes at you.
/// - [exitDelay] — the gap between the trigger and the card is real space the
///   pointer has to cross. Closing the instant it leaves the trigger makes the
///   card unreachable, which is the classic hover-card bug.
/// - [settleDelay] — leaving the card itself. Shorter, because by then you have
///   decided.
///
/// The card registers its own hover, so travelling *into* it cancels the close.
/// That is what makes the footer link clickable at all.
class HoverCard extends StatefulWidget {
  const HoverCard({
    required this.anchor,
    required this.content,
    this.onTap,
    this.enterDelay = const Duration(milliseconds: 450),
    this.exitDelay = const Duration(milliseconds: 260),
    this.settleDelay = const Duration(milliseconds: 120),
    this.align = PopoverAlign.start,
    super.key,
  });

  /// The trigger. Built with a controller so a caller can drive it from a key
  /// binding as well — see the explorer's `c`.
  final Widget Function(BuildContext context, PopoverController controller)
  anchor;

  final Widget Function(BuildContext context, PopoverController controller)
  content;

  /// What clicking the trigger does. **Not** "toggle the card" — the card is
  /// already what hovering does, so the click is free to mean the next thing
  /// along, which for the explorer is opening the full screen.
  final VoidCallback? onTap;

  final Duration enterDelay;
  final Duration exitDelay;
  final Duration settleDelay;
  final PopoverAlign align;

  @override
  State<HoverCard> createState() => HoverCardState();
}

class HoverCardState extends State<HoverCard> {
  PopoverController? _popover;
  Timer? _timer;

  /// Whether the pointer is inside the card, as opposed to the trigger. The
  /// card lives in an overlay, so nothing else can tell.
  var _inCard = false;

  /// Opens now, skipping [HoverCard.enterDelay] — for a key binding, which has
  /// already expressed the intent that the delay exists to wait for.
  void show() {
    _timer?.cancel();
    _popover?.open();
  }

  void hide() {
    _timer?.cancel();
    _popover?.close();
  }

  bool get isOpen => _popover?.isOpen ?? false;

  void _after(Duration delay, VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, () {
      if (mounted) action();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Popover(
      align: widget.align,
      // **It must not take the focus.** The explorer's filter field holds it
      // the whole time you are on that screen, which is what lets you type to
      // filter and arrow through rows without reaching for anything.
      autofocus: false,
      anchor: (context, controller) {
        _popover = controller;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _after(widget.enterDelay, controller.open),
          onExit: (_) => _after(widget.exitDelay, () {
            if (!_inCard) controller.close();
          }),
          child: GestureDetector(
            // The inner detector wins the arena, so this does not also expand
            // the row underneath it.
            onTap: widget.onTap,
            child: widget.anchor(context, controller),
          ),
        );
      },
      content: (context, controller) => MouseRegion(
        onEnter: (_) {
          _inCard = true;
          _timer?.cancel();
        },
        onExit: (_) {
          _inCard = false;
          _after(widget.settleDelay, controller.close);
        },
        child: widget.content(context, controller),
      ),
    );
  }
}
