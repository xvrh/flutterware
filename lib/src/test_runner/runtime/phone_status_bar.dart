import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PhoneStatusBar extends StatefulWidget {
  final Widget child;
  final String leftText;
  final Brightness brightness;
  final EdgeInsets viewPadding;

  const PhoneStatusBar({
    Key? key,
    required this.child,
    required this.leftText,
    required this.viewPadding,
    Brightness? brightness,
  })  : brightness = brightness ?? Brightness.light,
        super(key: key);

  @override
  PhoneStatusBarState createState() => PhoneStatusBarState();
}

class PhoneStatusBarState extends State<PhoneStatusBar> {
  late Brightness _topBrightness = widget.brightness;
  late Brightness _bottomBrightness = widget.brightness;

  @override
  void didUpdateWidget(covariant PhoneStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.brightness != oldWidget.brightness) {
      _topBrightness = widget.brightness;
      _bottomBrightness = widget.brightness;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bar = _StatusBar(
      widget,
      topBrightness: _topBrightness,
      bottomBrightness: _bottomBrightness,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: widget.child,
          ),
          bar,
        ],
      ),
    );
  }

  void setBrightness({required Brightness top, required Brightness bottom}) {
    setState(() {
      _topBrightness = top;
      _bottomBrightness = bottom;
    });
  }
}

class _StatusBar extends StatelessWidget {
  final PhoneStatusBar parent;
  final Brightness topBrightness;
  final Brightness bottomBrightness;

  const _StatusBar(
    this.parent, {
    Key? key,
    required this.topBrightness,
    required this.bottomBrightness,
  }) : super(key: key);

  static Color _colorFor(Brightness brightness) =>
      brightness == Brightness.light ? Colors.white : Colors.black;

  @override
  Widget build(BuildContext context) {
    var topColor = _colorFor(topBrightness);
    var bottomColor = _colorFor(bottomBrightness);

    return DefaultTextStyle.merge(
      style: TextStyle(
          color: topColor,
          fontFamily: defaultTargetPlatform == TargetPlatform.iOS
              ? '.SF Pro Display'
              : 'Roboto'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: SizedBox(
              width: 90,
              height: parent.viewPadding.top,
              child: Center(
                child: Text(
                  parent.leftText,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: SizedBox(
              width: 90,
              height: parent.viewPadding.top,
              child: Center(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.network_cell, color: topColor, size: 18),
                    const SizedBox(width: 5),
                    Icon(Icons.wifi, color: topColor, size: 18),
                    const SizedBox(width: 5),
                    Icon(Icons.battery_5_bar, color: topColor, size: 18),
                  ],
                ),
              ),
            ),
          ),
          if (parent.viewPadding.bottom > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: parent.viewPadding.bottom,
                child: FractionallySizedBox(
                  widthFactor: 0.36,
                  child: Center(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: bottomColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
