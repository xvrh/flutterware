import 'package:flutter/material.dart';
import '../../utils/value_stream.dart';
import '../devbar.dart';
import '../utils/animated_clip_rrect.dart';
import 'buttons_overlay.dart';
import 'service.dart';

class DevbarPanel extends StatelessWidget {
  const DevbarPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _Home(this),
    );
  }
}

class _Home extends StatelessWidget {
  final DevbarPanel parent;

  _Home(this.parent, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var devbar = DevbarState.of(context);
    return _SubTabs(
      devbar.ui.tabs,
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: devbar.ui.close,
      ),
    );
  }
}

class _SubTabs extends StatelessWidget {
  final ValueStream<List<DevbarTab>> tabs;
  final Widget? leading;

  const _SubTabs(this.tabs, {this.leading});

  @override
  Widget build(BuildContext context) {
    return ValueStreamBuilder<List<DevbarTab>>(
      stream: tabs,
      builder: (context, tabs) {
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              leading: leading,
              title: TabBar(
                tabs: [
                  for (var t in tabs)
                    switch (t) {
                      DevbarTabWithContent() => t.tab,
                      DevbarTabWithSubTabs() => Tab(text: t.title),
                    }
                ],
                isScrollable: true,
              ),
            ),
            body: TabBarView(
              children: [
                for (var t in tabs)
                  switch (t) {
                    DevbarTabWithContent() => t.content,
                    DevbarTabWithSubTabs() => _SubTabs(t.tabs),
                  }
              ],
            ),
          ),
        );
      },
    );
  }
}

class DevbarAppWrapper extends StatelessWidget {
  final _containerKey = GlobalKey();
  final Widget child;

  DevbarAppWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var devbar = DevbarState.of(context);

    return ValueStreamBuilder<OpenState?>(
      stream: devbar.ui.openState,
      builder: (context, openState) {
        var appWidget = _withWrappers(devbar, child);

        appWidget = Stack(children: [
          appWidget,
          Positioned.fill(child: ButtonsOverlay()),
        ]);

        var mediaQuery = MediaQuery.of(context);
        Widget screen = Container(
          width: mediaQuery.size.width,
          height: mediaQuery.size.height,
          alignment: Alignment.center,
          child: appWidget,
        );

        screen = _AnimatedScreenWrapper(
          key: _containerKey,
          openState: openState,
          child: FittedBox(
            fit: BoxFit.contain,
            child: screen,
          ),
        );

        return screen;
      },
    );
  }

  Widget _withWrappers(DevbarState devbar, Widget child) {
    return ValueStreamBuilder<List<AppWrapper>>(
      stream: devbar.ui.wrappers,
      builder: (context, wrappers) {
        var result = child;
        for (var wrapper in wrappers) {
          result = wrapper(child: result);
        }
        return result;
      },
    );
  }
}

class _AnimatedScreenWrapper extends StatelessWidget {
  final Widget child;
  final OpenState? openState;
  final _duration = const Duration(milliseconds: 300);
  final _curve = Curves.easeInOut;

  const _AnimatedScreenWrapper({Key? key, this.openState, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var mediaQuery = MediaQuery.of(context);

    var scale = openState?.scale?.value ?? 1;

    Widget clipped = AnimatedClipRRect(
      duration: _duration,
      curve: _curve,
      borderRadius: BorderRadius.circular(openState == null ? 0 : 10),
      child: AnimatedContainer(
        duration: _duration,
        curve: _curve,
        width: mediaQuery.size.width * scale,
        height: mediaQuery.size.height * scale,
        child: child,
      ),
    );

    clipped = Stack(
      children: [
        AnimatedPadding(
          duration: _duration,
          curve: _curve,
          padding: openState != null
              ? const EdgeInsets.only(top: 35.0, left: 35)
              : EdgeInsets.zero,
          child: clipped,
        ),
        if (openState != null)
          Positioned.fill(
            child: _PreviewTools(),
          ),
      ],
    );

    return AnimatedPadding(
      duration: _duration,
      curve: _curve,
      padding: openState == null
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 15.0, horizontal: 5),
      child: AnimatedAlign(
        duration: _duration,
        curve: _curve,
        alignment: openState?.alignment ?? Alignment.center,
        child: clipped,
      ),
    );
  }
}

class _PreviewTools extends StatelessWidget {
  const _PreviewTools({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var api = DevbarState.of(context);

    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _ToolButton(
              icon: api.ui.nextScaleUp ? Icons.zoom_in : Icons.zoom_out,
              onTap: () {
                api.ui.toggleScale();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final void Function()? onTap;
  final IconData icon;

  const _ToolButton({Key? key, this.onTap, required this.icon})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 35,
        height: 35,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white.withOpacity(0.9)),
        child: Icon(
          icon,
          color: Colors.black,
          size: 30,
        ),
      ),
    );
  }
}
