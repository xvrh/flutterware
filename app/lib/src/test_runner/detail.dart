import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'runtime.dart';
import '../utils.dart';
import 'screens/detail_image.dart';

class DetailPage extends StatelessWidget {
  final TestRun run;
  final String screenId;

  const DetailPage(this.run, this.screenId, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screen = run.screens[screenId];
    if (screen == null) {
      return Center(
        child: Text('Screen $screenId is loading'),
      );
    }

    return ImageDetail(run, screen);
  }
}

class DetailSkeleton extends StatelessWidget {
  static final separator = Container(color: AppColors.divider, height: 1);

  final TestRun run;
  final Screen screen;
  final Widget main;
  final List<Widget> sidebar;
  final void Function(ScreenLink?) onOverLink;

  const DetailSkeleton(
    this.run,
    this.screen, {
    Key? key,
    required this.main,
    required this.sidebar,
    required this.onOverLink,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var previousScreen = run.screens.values
        .firstWhereOrNull((s) => s.next.any((l) => l.to == screen.id));

    Widget? previousScreenLink;
    if (previousScreen != null) {
      previousScreenLink = Positioned(
        bottom: 0,
        left: 0,
        child: _ScreenLink(previousScreen, isNext: false),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _ScreenView(
                  run,
                  screen,
                  child: main,
                ),
              ),
              if (previousScreenLink != null) previousScreenLink,
              Positioned(
                  right: 0,
                  bottom: 0,
                  child: Column(
                    children: [
                      for (var next in screen.next)
                        MouseRegion(
                          key: ValueKey(next),
                          onEnter: (_) {
                            onOverLink(next);
                          },
                          onExit: (_) {
                            onOverLink(null);
                          },
                          child:
                              _ScreenLink(run.screens[next.to]!, isNext: true),
                        ),
                    ],
                  ))
            ],
          ),
        ),
        Container(
          color: AppColors.divider,
          width: 1,
        ),
        SizedBox(
          width: 200,
          child: Column(
            children: sidebar,
          ),
        )
      ],
    );
  }
}

class _ScreenView extends StatelessWidget {
  final TestRun run;
  final Screen screen;
  final Widget child;

  const _ScreenView(this.run, this.screen, {Key? key, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black87, width: 1),
        ),
        child: SizedBox(
          width: run.args.device.width * run.args.imageRatio,
          height: run.args.device.height * run.args.imageRatio,
          child: child,
        ),
      ),
    );
  }
}

class _ScreenLink extends StatelessWidget {
  final Screen screen;
  final bool isNext;

  const _ScreenLink(this.screen, {required this.isNext});

  @override
  Widget build(BuildContext context) {
    var name = screen.name;
    if (screen.splitName != null) {
      name += ' (${screen.splitName})';
    }

    return TextButton(
      onPressed: () {
        context.router.go('../../detail/${screen.id}');
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isNext) Icon(Icons.arrow_back_ios, size: 13),
          Text(
            name,
            style: const TextStyle(
              fontSize: 10,
            ),
          ),
          if (isNext) Icon(Icons.arrow_forward_ios, size: 13),
        ],
      ),
    );
  }
}
