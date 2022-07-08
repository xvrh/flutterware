import 'package:flutter/material.dart';
import 'package:flutterware_app/src/dependencies/detail.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:flutterware_app/src/utils/ui/message_dialog.dart';
import 'package:pubviz/open.dart' as pubviz;
import 'package:flutterware_app/src/dependencies/upgrades.dart';
import 'package:pub_scores/pub_scores.dart';
import '../app/ui/breadcrumb.dart';
import '../project.dart';
import '../utils.dart';
import '../utils/async_value.dart';
import 'package:collection/collection.dart';

import 'model/package_imports.dart';
import 'utils.dart';

class DependenciesScreen extends StatefulWidget {
  final Project project;

  const DependenciesScreen(this.project, {super.key});

  @override
  State<DependenciesScreen> createState() => _DependenciesScreenState();
}

class _DependenciesScreenState extends State<DependenciesScreen> {
  final _scrollBucket = PageStorageBucket();
  final _searchController = TextEditingController();
  bool _withTransitive = false;
  int _sortIndex = 0;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    return PageStorage(
      bucket: _scrollBucket,
      child: RouterOutlet({
        '': (_) => _DependencyListScreen(this),
        'upgrade': (_) => DependenciesUpgradeScreen(),
        'packages/:packageName': (args) =>
            DependencyDetailScreen(widget.project, args['packageName']),
      }),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _DependencyListScreen extends StatefulWidget {
  final _DependenciesScreenState parent;

  const _DependencyListScreen(this.parent);

  @override
  State<_DependencyListScreen> createState() => _DependencyListScreenState();

  static const _rowHeight = 48.0;
  static const _headingHeight = 55.0;
}

class _DependencyListScreenState extends State<_DependencyListScreen> {
  final _sorts = {
    0: _selectPackageName,
    3: _selectPubScore,
    4: _selectGithubScore,
  };

  Project get project => widget.parent.widget.project;

  TextEditingController get _searchController =>
      widget.parent._searchController;

  bool get _withTransitive => widget.parent._withTransitive;
  set _withTransitive(bool v) => widget.parent._withTransitive = v;

  int get _sortIndex => widget.parent._sortIndex;
  set _sortIndex(int v) => widget.parent._sortIndex = v;

  bool get _sortAscending => widget.parent._sortAscending;
  set _sortAscending(bool v) => widget.parent._sortAscending = v;

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ValueListenableBuilder<Snapshot<Dependencies>>(
      valueListenable: project.dependencies.dependencies,
      builder: (context, snapshot, child) {
        var data = snapshot.data;
        var error = snapshot.error;

        return ListView(
          key: PageStorageKey('dependencies_vertical'),
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: [
            Breadcrumb(children: [
              BreadcrumbEntry.overview,
            ]),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dependencies',
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                PopupMenuButton(
                  elevation: 2,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: Text('Visualize in browser'),
                      onTap: () async {
                        try {
                          await withLoader((_) async {
                            await pubviz.openBrowser(project.absolutePath,
                                sdkDirectory: project.flutterSdkPath.binDir);
                          }, message: 'Opening Pubviz in browser...');
                        } catch (e) {
                          await showMessageDialog(context,
                              message: 'Failed to collect dependencies. '
                                  'Run "flutter pub get" in the project.');
                        }
                      },
                    ),
                    PopupMenuItem(
                      child: Text('Reload'),
                      onTap: () {
                        project.dependencies.dependencies.refresh();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (data != null)
              _card(data)
            else if (error != null)
              ErrorPanel(
                message: 'Failed to load dependencies',
                onRetry: project.dependencies.dependencies.refresh,
              )
            else
              LoadingPanel(),
          ],
        );
      },
    );
  }

  Widget _card(Dependencies dependencies) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(),
          _table(dependencies),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: AppColors.tableHeader,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 300,
            padding: const EdgeInsets.all(8.0),
            child: _searchField(),
          ),
          Expanded(child: SizedBox()),
          InkWell(
            onTap: () {
              setState(() {
                _withTransitive = !_withTransitive;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black12,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list, size: 15),
                  Text('Show all', style: TextStyle(fontSize: 12)),
                  Checkbox(
                    value: _withTransitive,
                    onChanged: (v) {
                      setState(() {
                        _withTransitive = v!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextFormField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name',
        prefixIcon: Icon(Icons.search),
        suffixIconConstraints: BoxConstraints(minHeight: 30),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                constraints: BoxConstraints(minHeight: 30, minWidth: 48),
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _searchController.text = '';
                  });
                },
                icon: Icon(Icons.clear),
              )
            : null,
      ),
      onFieldSubmitted: (_) {
        setState(() {
          // Refresh the table
        });
      },
      onChanged: (v) {
        setState(() {
          // Refresh the table
        });
      },
    );
  }

  Widget _table(Dependencies dependencies) {
    var filteredDependencies = dependencies.dependencies;
    if (!_withTransitive) {
      filteredDependencies = filteredDependencies.where((d) => d.isDirect);
    }
    if (_searchController.text.isNotEmpty) {
      var query = _searchController.text.toLowerCase();
      filteredDependencies = dependencies.dependencies
          .where((e) => e.name.toLowerCase().contains(query));
    }

    return SizedBox(
      height: _DependencyListScreen._rowHeight * filteredDependencies.length +
          _DependencyListScreen._headingHeight,
      child: CustomScrollView(
        scrollDirection: Axis.horizontal,
        key: PageStorageKey('dependencies_horizontal'),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            fillOverscroll: true,
            child: _data(dependencies, filteredDependencies),
          )
        ],
      ),
    );
  }

  Widget _data(Dependencies all, Iterable<Dependency> list) {
    return ValueListenableBuilder<Snapshot<PubScores>>(
      valueListenable: project.dependencies.pubScores,
      builder: (context, pubScores, child) {
        var sort = _sorts[_sortIndex]!;
        var comparator = (Comparable a, Comparable b) => a.compareTo(b);
        if (!_sortAscending) {
          comparator = comparator.inverse;
        }

        var sortedDependencies = list.sortedByCompare<Comparable>(
            (p) => sort(p, pubScores), comparator);

        return DataTable(
          dataRowHeight: _DependencyListScreen._rowHeight,
          headingRowHeight: _DependencyListScreen._headingHeight,
          showCheckboxColumn: false,
          sortColumnIndex: _sortIndex,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(label: Text('Package'), onSort: _onSort),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Version')),
            DataColumn(label: Text('Pub'), onSort: _onSort),
            DataColumn(label: Text('GitHub'), onSort: _onSort),
          ],
          rows: [
            for (var dependency in sortedDependencies)
              DataRow(
                onSelectChanged: (selected) {
                  context.router.go('packages/${dependency.name}');
                },
                cells: [
                  DataCell(Text(dependency.name)),
                  DataCell(dependency.isTransitive
                      ? _DependencyTransitiveBadge(dependency)
                      : _DependencyDirectBadge(project, dependency)),
                  DataCell(_VersionCell(dependency)),
                  DataCell(_PubCell(dependency, pubScores.data)),
                  DataCell(_GithubCell(dependency, pubScores.data)),
                ],
              ),
          ],
        );
      },
    );
  }

  static Comparable _selectPackageName(
          Dependency d, Snapshot<PubScores> scores) =>
      d.name;

  static Comparable _selectPubScore(Dependency d, Snapshot<PubScores> scores) =>
      scores.data?[d.name]?.pub.popularity ?? 0;

  static Comparable _selectGithubScore(
          Dependency d, Snapshot<PubScores> scores) =>
      scores.data?[d.name]?.github?.starCount ?? 0;

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortIndex = columnIndex;
      _sortAscending = ascending;
    });
  }
}

class _PubCell extends StatelessWidget {
  final Dependency dependency;
  final PubScores? pubScores;

  const _PubCell(this.dependency, this.pubScores);

  @override
  Widget build(BuildContext context) {
    var popularityString = '';
    var pub = pubScores?[dependency.name]?.pub;
    var popularity = pub?.popularity;
    var likeCount = pub?.likeCount;
    var points = pub?.grantedPoints;
    if (popularity != null) {
      popularityString = '$popularity%';
    }
    var message = [
      if (popularityString.isNotEmpty) '$popularityString popularity',
      if (likeCount != null) '$likeCount like${likeCount > 1 ? 's' : ''}',
      if (points != null) '$points point${points > 1 ? 's' : ''}',
    ];

    return InkWell(
      onTap: () => openPub(dependency),
      child: Tooltip(
        message: message.join(' / '),
        child: Text(
          popularityString,
          style: const TextStyle(color: AppColors.blackSecondary),
        ),
      ),
    );
  }
}

class _GithubCell extends StatelessWidget {
  final Dependency dependency;
  final PubScores? pubScores;

  const _GithubCell(this.dependency, this.pubScores);

  @override
  Widget build(BuildContext context) {
    var github = pubScores?[dependency.name]?.github;
    if (github == null) {
      return const SizedBox();
    }

    var starCount = github.starCount;
    var forkCount = github.forkCount;
    return InkWell(
      onTap: () => openGithub(github),
      child: Tooltip(
        message: '${[
          '$starCount star${starCount > 1 ? 's' : ''}',
          '$forkCount fork${forkCount > 1 ? 's' : ''}',
        ].join(', ')}\n${github.slug}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$starCount',
              style: const TextStyle(color: AppColors.blackSecondary),
            ),
            Icon(Icons.star_outline, size: 15, color: AppColors.blackSecondary),
          ],
        ),
      ),
    );
  }
}

class _DependencyTransitiveBadge extends StatelessWidget {
  final Dependency dependency;

  const _DependencyTransitiveBadge(this.dependency);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Tooltip(
        message: dependency.dependencyPaths
            .take(3)
            .map((l) => l.join(' > '))
            .join('\n'),
        child: Text(
          'Transitive',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _DependencyDirectBadge extends StatelessWidget {
  final Project project;
  final Dependency dependency;

  const _DependencyDirectBadge(this.project, this.dependency);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Color(0xfff2f8eb),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ValueListenableBuilder<Snapshot<PackageImports>>(
        valueListenable: project.dependencies.packageImports,
        builder: (context, snapshot, child) {
          var packageImports = snapshot.data;
          var tooltip = '';
          if (packageImports != null) {
            var imports = packageImports[dependency.name];
            tooltip =
                '${imports.length} import${imports.length > 1 ? 's' : ''}';
          }
          return Tooltip(
            message: tooltip,
            child: Text(
              'Direct',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xff618a3d),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VersionCell extends StatelessWidget {
  final Dependency dependency;

  const _VersionCell(this.dependency);

  @override
  Widget build(BuildContext context) {
    return Text(
      dependency.pubspec.version?.toString() ?? '',
      style: const TextStyle(
        color: AppColors.blackSecondary,
      ),
    );

    //TODO(xha): run a dart pub outdated in the background and when ready, display
    // an icon explaining what is available
    //return Row(
    //  children: [
    //    Tooltip(
    //      message: "Upgrade available: BREAKING 3.0.0",
    //      child: Row(
    //        children: [
    //          Text(dependency.lockDependency.version),
    //          Icon(Icons.upgrade, size: 15),
    //        ],
    //      ),
    //    ),
    //  ],
    //);
  }
}
