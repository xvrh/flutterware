import 'dart:async';
import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/internals/test_runner.dart';
import '../app/paths.dart' as paths;
import '../utils/router_outlet.dart';
import 'model/service.dart';
import 'protocol/api.dart';
import 'protocol/listing.dart';
import 'ui/menu_tree.dart';

class TestListingView extends StatefulWidget {
  final TestService service;
  final TestRunnerApi client;

  const TestListingView(this.service, this.client, {Key? key})
      : super(key: key);

  @override
  State<TestListingView> createState() => _TestListingViewState();
}

class _TestListingViewState extends State<TestListingView> {
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
    return StreamBuilder<BuiltMap<BuiltList<String>, TestReference>>(
      stream: listing.allTests,
      initialData: listing.allTests.value,
      builder: (context, snapshot) {
        var selectedTest = context.router.allArgs['testId'];
        TreePath? selectedPath;
        if (selectedTest != null) {
          selectedPath = TreePath.fromEncoded(selectedTest);
        }

        var tests = snapshot.requireData;
        if (tests.isEmpty) {
          return _EmptyList(widget);
        }

        return MenuTree(
          selected: selectedPath,
          entries: _menu(tests),
          onSelected: (path) {
            context
                .go('${paths.tests}/run/${Uri.encodeComponent(path.encoded)}');
          },
          extraDepth: 1,
        );
      },
    );
  }

  List<MenuEntry> _menu(BuiltMap<BuiltList<String>, TestReference> tests) {
    var entries = <MenuEntry>[];

    for (var test in tests.entries) {
      var name = test.key;
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

class _EmptyList extends StatelessWidget {
  final TestListingView parent;

  const _EmptyList(this.parent);

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        await parent.service.addExample();
      },
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12),
        minimumSize: Size(0, 30),
      ),
      icon: Icon(
        Icons.add,
        size: 12,
      ),
      label: Text('Add an example'),
    );
  }
}
