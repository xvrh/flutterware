import 'dart:math';
import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'button.dart';

/// Display a simulated on screen keyboard at the bottom of a [child] widget.
///
/// When [isEnabled] is updated, a [transitionDuration] starts to display
/// or hide the virtual keyboard.
///
/// No interraction is available, its only purpose is to display
/// the visual and update media query's `viewInsets` for [child].
class VirtualKeyboard extends StatelessWidget {
  /// Indicates whether the keyboard is displayed or not.
  final bool isEnabled;

  /// The widget on top of which the keyboard is displayed.
  final Widget child;

  /// The transition duration when the keyboard is displayed or hidden.
  final Duration transitionDuration;

  final double? height;

  /// Display a simulated on screen keyboard on top of the given [child] widget.
  ///
  /// When [isEnabled] is updated, a [transitionDuration] starts to display
  /// or hide the virtual keyboard.
  ///
  /// No interraction is available, its only purpose is to display
  /// the visual and update media query's `viewInsets` for [child].
  const VirtualKeyboard({
    super.key,
    required this.child,
    this.isEnabled = false,
    this.transitionDuration = const Duration(milliseconds: 400),
    this.height,
  });

  static MediaQueryData mediaQuery(MediaQueryData mediaQuery,
      {required double height}) {
    final insets = EdgeInsets.only(
      bottom: height + mediaQuery.padding.bottom,
    );
    return mediaQuery.copyWith(
      viewInsets: insets,
      viewPadding: EdgeInsets.only(
        top: max(insets.top, mediaQuery.padding.top),
        left: max(insets.left, mediaQuery.padding.left),
        right: max(insets.right, mediaQuery.padding.right),
        bottom: max(insets.bottom, mediaQuery.padding.bottom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var height = this.height ?? _VirtualKeyboard.minHeight;
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: !isEnabled
          ? mediaQuery
          : VirtualKeyboard.mediaQuery(mediaQuery, height: height),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: child,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedCrossFade(
              firstChild: SizedBox(),
              secondChild: _VirtualKeyboard(
                height: height,
              ),
              crossFadeState: isEnabled
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: transitionDuration,
            ),
          ),
        ],
      ),
    );
  }
}

class _VirtualKeyboard extends StatelessWidget {
  static const double minHeight = 214;
  final double height;

  const _VirtualKeyboard({
    double? height,
  }) : height = height ?? minHeight;

  Widget _row(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 12,
        left: 12,
      ),
      child: Row(
        children: children,
      ),
    );
  }

  List<Widget> _letters(
      List<String> letters, Color backgroundColor, Color foregroundColor) {
    return letters
        .map<Widget>(
          (x) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: backgroundColor,
                child: Text(
                  x,
                  style: TextStyle(
                    fontSize: 14,
                    color: foregroundColor,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = DeviceFrameTheme.of(context).keyboardStyle;
    final mediaQuery = MediaQuery.of(context);
    return Container(
      height: height + mediaQuery.padding.bottom,
      padding: EdgeInsets.only(
        left: mediaQuery.padding.left,
        right: mediaQuery.padding.right,
      ),
      color: theme.backgroundColor,
      child: Column(
        children: <Widget>[
          _row(_letters(
            ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
            theme.button1BackgroundColor,
            theme.button1ForegroundColor,
          )),
          _row(_letters(
            ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
            theme.button1BackgroundColor,
            theme.button1ForegroundColor,
          )),
          _row([
            Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: theme.button2BackgroundColor,
                child: Icon(
                  Icons.keyboard_capslock,
                  color: theme.button2ForegroundColor,
                  size: 16,
                ),
              ),
            ),
            ..._letters(
              ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
              theme.button1BackgroundColor,
              theme.button1ForegroundColor,
            ),
            Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: theme.button2BackgroundColor,
                child: Icon(
                  Icons.backspace,
                  color: theme.button2ForegroundColor,
                  size: 16,
                ),
              ),
            ),
          ]),
          _row([
            Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: theme.button2BackgroundColor,
                child: Text(
                  '123',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.button2ForegroundColor,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: theme.button2BackgroundColor,
                child: Icon(
                  Icons.insert_emoticon,
                  color: theme.button2ForegroundColor,
                  size: 16,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: 12,
                ),
                child: VirtualKeyboardButton(
                  backgroundColor: theme.button2BackgroundColor,
                  child: Text(
                    'space',
                    style: TextStyle(
                        fontSize: 14, color: theme.button2ForegroundColor),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                right: 12,
              ),
              child: VirtualKeyboardButton(
                backgroundColor: theme.button2BackgroundColor,
                child: Text(
                  'return',
                  style: TextStyle(
                      fontSize: 14, color: theme.button2ForegroundColor),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
