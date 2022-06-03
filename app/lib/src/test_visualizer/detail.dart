import 'package:collection/collection.dart';
import '../utils/router_outlet.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import '../ui.dart';
import 'app_connected.dart';
import 'detail/image.dart';
import 'detail/json.dart';
import 'service.dart';

class DetailPage extends StatelessWidget {
  final TestService service;
  final ProjectInfo project;
  final ScenarioRun run;
  final String screenId;

  const DetailPage(this.service, this.project, this.run, this.screenId,
      {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var screen = run.screens[screenId];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProjectView.of(context).header.setScreen(screen);
    });

    if (screen == null) {
      return Center(
        child: Text('Screen $screenId is loading'),
      );
    }

    var email = screen.email;
    if (email != null) {
      throw UnimplementedError();
    }

    var pdf = screen.pdf;
    if (pdf != null) {
      throw UnimplementedError();
    }

    var json = screen.json;
    if (json != null) {
      return JsonDetail(project, run, screen, json);
    }

    return ImageDetail(project, run, screen);
  }
}

class DetailSkeleton extends StatelessWidget {
  static final separator = Container(color: AppColors.separator, height: 1);

  final ProjectInfo project;
  final ScenarioRun run;
  final Screen screen;
  final Widget main;
  final List<Widget> sidebar;

  const DetailSkeleton(
    this.project,
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

    var parentScreen = screen;
    if (screen.collapsedScreens.isEmpty) {
      parentScreen = run.screens.values
              .firstWhereOrNull((s) => s.collapsedScreens.contains(screen)) ??
          screen;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: Colors.black.withOpacity(0.02),
            child: Column(
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
                    ],
                  ),
                ),
                if (parentScreen.collapsedScreens.isNotEmpty) ...[
                  Container(
                    color: AppColors.separator,
                    height: 1,
                  ),
                  _RelatedScreensList(parentScreen, selectedScreen: screen),
                ],
              ],
            ),
          ),
        ),
        Container(
          color: AppColors.separator,
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

class _RelatedScreensList extends StatelessWidget {
  final Screen parentScreen;
  final Screen selectedScreen;

  const _RelatedScreensList(
    this.parentScreen, {
    Key? key,
    required this.selectedScreen,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var allScreens = [parentScreen, ...parentScreen.collapsedScreens];
    return SizedBox(
      height: 80,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: Center(
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: allScreens.length,
            itemBuilder: (context, item) {
              var collapsedScreen = allScreens[item];
              return _CollapsedScreenshot(
                collapsedScreen,
                isSelected: collapsedScreen == selectedScreen,
                onTap: () {
                  context.router.go('../../detail/${collapsedScreen.id}');
                },
              );
            },
            separatorBuilder: (context, item) => const SizedBox(width: 10),
          ),
        ),
      ),
    );
  }
}

class _CollapsedScreenshot extends StatelessWidget {
  final Screen screen;
  final VoidCallback onTap;
  final bool isSelected;

  const _CollapsedScreenshot(
    this.screen, {
    Key? key,
    required this.onTap,
    required this.isSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var bytes = screen.imageBytes;
    Widget image;
    if (bytes != null) {
      image = Image.memory(bytes);
    } else {
      image = Center(
        child: Text(
          screen.name,
          style: const TextStyle(fontSize: 10),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(color: Colors.blueAccent, width: 2),
                )
              : null,
          child: image),
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
