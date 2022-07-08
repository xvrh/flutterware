import 'package:flutter/material.dart';
import 'package:flutterware_app/src/test_runner/protocol/api.dart';
import '../project.dart';
import '../ui/side_menu.dart';
import '../utils.dart';
import '../utils/expansion_tile.dart';
import 'daemon_toolbar.dart';
import 'listing.dart';
import 'model/service.dart';

class TestMenu extends StatelessWidget {
  final Project project;

  const TestMenu(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    return CollapsibleMenu(
      title: Row(
        children: [
          Expanded(child: Text('Tests')),
          //Builder(builder: (context) {
          //  var isSelected = context.router.isSelected('tests/home');
          //  if (isSelected != _isSelected) {
          //    _isSelected = isSelected;
          //    if (isSelected) {
          //      var parentMenu = CustomExpansionTile.of(context);
          //      if (parentMenu != null) {
          //        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          //          parentMenu.expand();
          //        });
          //      }
          //    }
          //  }
          //  return IconButton(
          //    padding: EdgeInsets.zero,
          //    constraints: BoxConstraints(),
          //    onPressed: () {
          //      var expansionPanel = CustomExpansionTile.of(context);
          //      expansionPanel.expand();
          //      print('Panel $expansionPanel');
          //      context.router.go('tests/home');
          //    },
          //    icon: Icon(
          //      Icons.info_outline,
          //      size: 18,
          //    ),
          //    splashRadius: Material.defaultSplashRadius / 2,
          //  );
          //}),
        ],
      ),
      children: [
        MenuLine(
          onTap: () {
            context.go('tests/home');
          },
          isSelected: context.router.isSelected('tests/home'),
          child: Text('Introduction'),
        ),
        Container(
          decoration: BoxDecoration(
            color: Color(0xfff1f3f4),
            //borderRadius: BorderRadius.circular(20),
            borderRadius: BorderRadius.circular(15),
            //border: Border.symmetric(
            //    horizontal: BorderSide(color: Color(0xffdadce0))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          margin: const EdgeInsets.symmetric(horizontal: 50, vertical: 10),
          child: Row(
            children: [
              //Text(
              //  'Daemon',
              //  style: const TextStyle(
              //    fontSize: 12,
              //    fontWeight: FontWeight.w500,
              //    color: Colors.black54,
              //  ),
              //),
              Expanded(child: DaemonToolbar(project)),
            ],
          ),
        ),
        _listing(),
      ],
    );
  }

  Widget _listing() {
    return StreamBuilder<List<TestRunnerApi>>(
      stream: project.tests.clients,
      initialData: project.tests.clients.value,
      builder: (context, snapshot) {
        var clients = snapshot.requireData;
        if (clients.isEmpty) {
          return ValueListenableBuilder<DaemonState>(
            valueListenable: project.tests.state,
            builder: (context, state, child) {
              if (state is! DaemonState$Stopped) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1),
                    ),
                  ),
                );
              } else {
                return const SizedBox();
              }
            },
          );
        } else {
          var client = clients.last;
          return TestListingView(client);
        }
      },
    );
  }
}
