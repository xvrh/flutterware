import '../utils/router_outlet.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import '../ui.dart';
import 'ui/breadcrumb.dart';
import 'ui/menu_tree.dart';

class Header extends StatefulWidget {
  final ProjectInfo project;

  const Header(
    this.project, {
    Key? key,
  }) : super(key: key);

  @override
  State<Header> createState() => HeaderState();
}

class HeaderState extends State<Header> {
  ScenarioRun? _run;
  Screen? _screen;

  @override
  Widget build(BuildContext context) {
    var run = _run;
    var screen = _screen;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        border: Border(
          bottom: BorderSide(color: AppColors.separator, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Breadcrumb(
          children: [
            if (run != null) ..._runBreadcrumb(run),
            if (screen != null) BreadcrumbItem(Text(screen.name)),
          ],
        ),
      ),
    );
  }

  Iterable<Widget> _runBreadcrumb(ScenarioRun run) sync* {
    for (var i = 0; i < run.scenario.name.length; i++) {
      var part = run.scenario.name[i];
      var isLast = i == run.scenario.name.length - 1;
      if (isLast) {
        var clickable = _screen != null;
        yield BreadcrumbItem(
          Text(part),
          onTap: clickable
              ? () => context.go(
                  'scenario/${Uri.encodeComponent(TreePath(run.scenario.name.toList()).encoded)}')
              : null,
        );
      } else {
        //TODO(xha): allow to open submenu with siblings
        yield BreadcrumbItem(
          Text(part),
          onTap: null,
        );
      }
    }
  }

  void setRun(ScenarioRun? run) {
    setState(() {
      _run = run;
    });
  }

  void setScreen(Screen? screen) {
    setState(() {
      _screen = screen;
    });
  }
}
