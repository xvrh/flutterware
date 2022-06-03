import '../../../utils/router_outlet.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import '../../../utils/assets.dart';
import 'analytic_event.dart';

class LinkRow extends StatelessWidget {
  final ProjectInfo project;
  final Screen screen;
  final ScreenLink link;

  const LinkRow(this.project, this.screen, this.link, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var analyticEvent = link.analytic;

    var pathName = screen.pathName;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              context.router.go('../../detail/${link.to}');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 8,
              ).copyWith(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      screen.name,
                    ),
                  ),
                  if (pathName != null)
                    Text(
                      pathName,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (analyticEvent != null)
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) =>
                      AnalyticEventDialog(project, analyticEvent),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0).copyWith(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        analyticEvent.event,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Image.asset(
                        assets.images.googleAnalytics.path,
                        height: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
