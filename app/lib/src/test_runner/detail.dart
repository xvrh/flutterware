import 'package:collection/collection.dart';
import '../utils.dart';
import 'package:flutterware/internals/test_runner.dart';
import 'package:flutter/material.dart';
import 'detail/image.dart';

class DetailPage extends StatelessWidget {
  final ScenarioRun run;
  final String screenId;

  const DetailPage(this.run, this.screenId, {Key? key})
      : super(key: key);

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

  final ScenarioRun run;
  final Screen screen;
  final Widget main;
  final List<Widget> sidebar;

  const DetailSkeleton(
    this.run,
    this.screen, {
    Key? key,
    required this.main,
    required this.sidebar,
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
        child: TextButton(
          onPressed: () {
            context.router.go('../../detail/${previousScreen.id}');
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.arrow_back_ios, size: 13),
              Text(
                previousScreen.name,
                style: const TextStyle(
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: Colors.black.withOpacity(0.02),
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
              ],
            ),
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
  final ScenarioRun run;
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
