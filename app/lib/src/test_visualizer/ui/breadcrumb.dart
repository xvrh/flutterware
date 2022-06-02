import 'package:flutter/material.dart';
import '../../ui.dart';

class Breadcrumb extends StatelessWidget {
  final List<Widget> children;

  const Breadcrumb({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var separator = Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: SizedBox(
        width: 5,
        height: 16,
        child: _Separator(),
      ),
    );

    return SizedBox(
      height: 30,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var child in children) ...[
            child,
            if (child != children.last) separator
          ],
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SeparatorPainter(),
    );
  }
}

class _SeparatorPainter extends CustomPainter {
  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..color = const Color(0xFFc2c7c9);

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path()
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height);

    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(covariant _SeparatorPainter oldDelegate) {
    return false;
  }
}

class BreadcrumbItem extends StatelessWidget {
  static const defaultPadding = EdgeInsets.symmetric(vertical: 4);

  final Widget child;
  final VoidCallback? onTap;

  const BreadcrumbItem(this.child, {Key? key, this.onTap}) : super(key: key);

  static Widget withIcon(String text, IconData icon) {
    return BreadcrumbItem(
      Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: AppColors.iconLightBlue,
          ),
          const SizedBox(width: 5),
          Text(text)
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: defaultPadding,
        child: child,
      ),
    );
  }
}

class BreadcrumbItemWithMenu<T> extends StatefulWidget {
  final Widget child;
  final Map<T, Widget> options;
  final void Function(T) onTapOption;

  const BreadcrumbItemWithMenu(
    this.child, {
    Key? key,
    required this.options,
    required this.onTapOption,
  }) : super(key: key);

  @override
  State<BreadcrumbItemWithMenu> createState() =>
      _BreadcrumbItemWithMenuState<T>();
}

class _BreadcrumbItemWithMenuState<T> extends State<BreadcrumbItemWithMenu<T>> {
  final LayerLink layerLink = LayerLink();
  OverlayEntry? _currentMenu;

  void showMenu(Map<T, Widget> options) {
    _hideMenu();
    var overlay = _currentMenu = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideMenu,
            child: _Menu<T>(
              link: layerLink,
              options: options,
              onTapOption: (key) {
                _hideMenu();
                widget.onTapOption(key);
              },
            ),
          ),
        );
      },
    );
    Overlay.of(context)!.insert(overlay);
  }

  void _hideMenu() {
    _currentMenu?.remove();
    _currentMenu = null;
  }

  @override
  Widget build(BuildContext context) {
    var options = widget.options;
    return InkWell(
      onTap: () {
        showMenu(options);
      },
      child: CompositedTransformTarget(
        link: layerLink,
        child: Padding(
          padding: BreadcrumbItem.defaultPadding,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Menu<T> extends StatelessWidget {
  final LayerLink link;
  final Map<T, Widget> options;
  final void Function(T) onTapOption;

  const _Menu({
    Key? key,
    required this.link,
    required this.options,
    required this.onTapOption,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: link,
        offset: Offset(0, 22),
        child: Material(
          child: Container(
            constraints: BoxConstraints(maxHeight: 250),
            width: 170,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.separator, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(1, 1),
                )
              ],
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var option in options.entries)
                  _MenuTile(
                    onTap: () => onTapOption.call(option.key),
                    child: option.value,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _MenuTile({Key? key, required this.child, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          child: child,
        ),
      ),
    );
  }
}
