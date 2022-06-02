import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart';
import '../utils/router_outlet.dart';
import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import 'protocol/api.dart';
import 'protocol/listing.dart';
import 'ui/menu_tree.dart';
import 'ui/side_bar.dart';

class ScenarioListingView extends StatefulWidget {
  final ScenarioApi client;

  const ScenarioListingView(this.client, {Key? key}) : super(key: key);

  @override
  State<ScenarioListingView> createState() => _ScenarioListingViewState();
}

class _ScenarioListingViewState extends State<ScenarioListingView> {
  ListingHost get listing => widget.client.listing;
  late StreamSubscription _reloadSubscription;

  @override
  void initState() {
    super.initState();
    listing.list();

    _reloadSubscription = widget.client.project.onReloaded.listen((event) {
      // Refresh the menu when there is a hot-reload event
      listing.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BuiltMap<BuiltList<String>, ScenarioReference>>(
      stream: listing.allScenarios,
      initialData: listing.allScenarios.value,
      builder: (context, snapshot) {
        var selectedScenario = context.router.allArgs['scenarioId'];
        TreePath? selectedPath;
        if (selectedScenario != null) {
          selectedPath = TreePath.fromEncoded(selectedScenario);
        }

        return SideBar(
          header: Text('Scenarios'),
          child: MenuTree(
            selected: selectedPath,
            entries: _menu(snapshot.requireData),
            onSelected: (path) {
              context.go('scenario/${Uri.encodeComponent(path.encoded)}');
            },
          ),
        );
      },
    );
  }

  List<MenuEntry> _menu(
      BuiltMap<BuiltList<String>, ScenarioReference> scenarios) {
    var entries = <MenuEntry>[];

    for (var scenario in scenarios.entries) {
      var name = scenario.key;
      _addToMenu(name.toList(), entries);
    }

    return entries;
  }

  void _addToMenu(List<String> name, List<MenuEntry> parent) {
    assert(name.isNotEmpty);
    var namePart = name.first;
    var isLast = name.length == 1;

    var existing = parent.firstWhereOrNull((e) => e.text == namePart);
    List<MenuEntry>? children;
    if (existing == null) {
      children = isLast ? null : <MenuEntry>[];
      existing = MenuEntry(namePart, children: children);
      parent.add(existing);
    } else {
      children = existing.children;
    }
    if (!isLast) {
      _addToMenu(name.skip(1).toList(), children!);
    }
  }

  @override
  void dispose() {
    _reloadSubscription.cancel();
    super.dispose();
  }
}

class ScenarioRow extends StatelessWidget {
  final ScenarioApi client;

  final ScenarioReference scenario;

  const ScenarioRow(this.client, this.scenario, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(scenario.name.join('/')),
      onTap: () {
        context.go(
            'scenario/${Uri.encodeComponent(TreePath(scenario.name.toList()).encoded)}');
      },
    );
  }
}
