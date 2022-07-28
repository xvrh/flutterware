import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class PhoneStatusBar extends StatelessWidget {
  final Widget child;
  final String leftText;
  final Brightness topBrightness;
  final Brightness bottomBrightness;
  final EdgeInsets viewPadding;

  const PhoneStatusBar({
    Key? key,
    required this.child,
    required this.leftText,
    required this.viewPadding,
    required this.topBrightness,
    required this.bottomBrightness,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget bar = _StatusBar(this);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned.fill(
            child: child,
          ),
          bar,
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final PhoneStatusBar parent;

  const _StatusBar(this.parent, {Key? key}) : super(key: key);

  static Color _colorFor(Brightness brightness) =>
      brightness == Brightness.light ? Colors.white : Colors.black;

  @override
  Widget build(BuildContext context) {
    var topColor = _colorFor(parent.topBrightness);
    var bottomColor = _colorFor(parent.bottomBrightness);

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
                    SvgPicture.string(_networkSvg, color: topColor),
                    const SizedBox(width: 5),
                    SvgPicture.string(_wifiSvg, color: topColor),
                    const SizedBox(width: 5),
                    SvgPicture.string(_batterySvg, color: topColor),
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

final _batterySvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24.5" height="11.5" viewBox="0 0 24.5 11.5">
  <g id="Battery" transform="translate(0 -0.56)">
    <path id="Rectangle" d="M3.589,11.5a4.057,4.057,0,0,1-2.156-.374A2.543,2.543,0,0,1,.374,10.067,4.05,4.05,0,0,1,0,7.911V3.589A4.048,4.048,0,0,1,.374,1.433,2.543,2.543,0,0,1,1.433.374,4.048,4.048,0,0,1,3.589,0H18.41a4.052,4.052,0,0,1,2.157.374,2.543,2.543,0,0,1,1.058,1.058A4.059,4.059,0,0,1,22,3.589V7.911a4.061,4.061,0,0,1-.374,2.156,2.543,2.543,0,0,1-1.058,1.058,4.061,4.061,0,0,1-2.157.374ZM23,3.69s1.5.763,1.5,2-1.5,2-1.5,2Z" transform="translate(0 0.56)" fill="rgba(255,255,255,0.36)" fill-opacity="0.36" />
    <rect id="Rectangle-2" data-name="Rectangle" width="18" height="7.667" rx="1.6" transform="translate(2 2.477)" fill="#fff"/>
  </g>
</svg>
''';

final _networkSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="17.1" height="10.7" viewBox="0 0 17.1 10.7">
  <path id="Combined_Shape" data-name="Combined Shape" d="M15.3,10.7a1.2,1.2,0,0,1-1.2-1.2V1.2A1.2,1.2,0,0,1,15.3,0h.6a1.2,1.2,0,0,1,1.2,1.2V9.5a1.2,1.2,0,0,1-1.2,1.2Zm-4.7,0A1.2,1.2,0,0,1,9.4,9.5V3.6a1.2,1.2,0,0,1,1.2-1.2h.6a1.2,1.2,0,0,1,1.2,1.2V9.5a1.2,1.2,0,0,1-1.2,1.2ZM6,10.7A1.2,1.2,0,0,1,4.8,9.5V5.9A1.2,1.2,0,0,1,6,4.7h.6A1.2,1.2,0,0,1,7.8,5.9V9.5a1.2,1.2,0,0,1-1.2,1.2Zm-4.8,0A1.2,1.2,0,0,1,0,9.5V7.9A1.2,1.2,0,0,1,1.2,6.7h.6A1.2,1.2,0,0,1,3,7.9V9.5a1.2,1.2,0,0,1-1.2,1.2Z" fill="#fff"/>
</svg>
''';

final _wifiSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="15.4" height="11.057" viewBox="0 0 15.4 11.057">
  <path id="Wi-Fi" d="M7.7,11.057a.315.315,0,0,1-.223-.094L5.462,8.932a.317.317,0,0,1,.01-.461,3.451,3.451,0,0,1,4.457,0,.312.312,0,0,1,.1.228.319.319,0,0,1-.094.233L7.924,10.964A.315.315,0,0,1,7.7,11.057ZM11.237,7.49a.309.309,0,0,1-.215-.086,4.945,4.945,0,0,0-6.641,0A.312.312,0,0,1,3.945,7.4L2.78,6.222a.325.325,0,0,1,0-.463,7.22,7.22,0,0,1,9.834,0,.325.325,0,0,1,0,.463L11.459,7.4A.31.31,0,0,1,11.237,7.49ZM13.92,4.783a.308.308,0,0,1-.217-.088,8.714,8.714,0,0,0-12.006,0,.311.311,0,0,1-.217.088.306.306,0,0,1-.22-.092L.094,3.515a.325.325,0,0,1,0-.46,10.989,10.989,0,0,1,15.205,0,.324.324,0,0,1,0,.46L14.14,4.691A.306.306,0,0,1,13.92,4.783Z" transform="translate(0 0)" fill="#fff"/>
</svg>
''';
