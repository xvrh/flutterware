import 'package:flutter/material.dart';
import 'package:flutter_studio_app/src/dependencies/detail.dart';
import 'package:flutter_studio_app/src/dependencies/service.dart';
import 'package:flutter_studio_app/src/utils/router_outlet.dart';
import 'package:pub_scores/pub_scores.dart';
import '../app/project_view.dart';
import '../app/ui/breadcrumb.dart';
import '../project.dart';
import '../utils/async_value.dart';
import '../utils/ui/error_panel.dart';
import '../utils/ui/loading.dart';
import 'package:collection/collection.dart';


//TODO(xha): enhancement:
// - Search field for filter
// - Single table
// - "Transitive" badge (with tooltip showing the root package responsible)
// - Checkbox for "Show transitive dependencies" (with help icon)
// -
class DependenciesScreen extends StatefulWidget {
  final Project project;

  const DependenciesScreen(this.project, {super.key});

  @override
  State<DependenciesScreen> createState() => _DependenciesScreenState();
}

class _DependenciesScreenState extends State<DependenciesScreen> {
  final _scrollBucket = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    return PageStorage(
      bucket: _scrollBucket,
      child: RouterOutlet({
        '': (_) => _DependencyListScreen(this),
        ':packageName': (args) =>
            DependencyDetailScreen(widget.project, args['packageName']),
      }),
    );
  }
}

class _DependencyListScreen extends StatefulWidget {
  final _DependenciesScreenState parent;

  const _DependencyListScreen(this.parent, {super.key});

  @override
  State<_DependencyListScreen> createState() => _DependencyListScreenState();

  static const _rowHeight = 48.0;
  static const _headingHeight = 55.0;
}

class _DependencyListScreenState extends State<_DependencyListScreen> {
  static final _sorts = {
    0: _selectPackageName,
    2: _selectPubScore,
    3: _selectGithubScore,
  };
  int _sortIndex = 0;
  bool _sortAscending = true;

  Project get project => widget.parent.widget.project;

  @override
  Widget build(BuildContext context) {
    ProjectView.of(context).setBreadcrumb([
      BreadcrumbItem(Text('Dependencies')),
    ]);
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dependencies',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                PopupMenuButton(
                  itemBuilder: (context) => [
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
            const SizedBox(height: 30),
            if (data != null)
              ..._dependencies(context, data)
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

  Iterable<Widget> _dependencies(
      BuildContext context, Dependencies dependencies) sync* {
    var theme = Theme.of(context);
    var headerStyle = theme.textTheme.titleMedium;

    yield Text(
      'Direct dependencies (${dependencies.directs.length})',
      style: headerStyle,
    );
    yield _table(dependencies.directs);
    yield const SizedBox(height: 30);
    yield Text(
      'Transitive dependencies (${dependencies.transitives.length})',
      style: headerStyle,
    );
    yield _table(dependencies.transitives);
  }

  Widget _table(List<Dependency> dependencies) {
    return SizedBox(
      height: _DependencyListScreen._rowHeight * dependencies.length +
          _DependencyListScreen._headingHeight,
      child: CustomScrollView(
        scrollDirection: Axis.horizontal,
        key: PageStorageKey('dependencies_horizontal'),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            fillOverscroll: true,
            child: _data(dependencies),
          )
        ],
      ),
    );
  }

  Widget _data(List<Dependency> dependencies) {
    return ValueListenableBuilder<Snapshot<PubScores>>(
        valueListenable: project.dependencies.pubScores,
        builder: (context, pubScores, child) {
          var sort = _sorts[_sortIndex]!;
          var comparator = (Comparable a, Comparable b) => a.compareTo(b);
          if (!_sortAscending) {
            comparator = comparator.inverse;
          }

          var sortedDependencies = dependencies.sortedByCompare<Comparable>(
              (p) => sort(p, pubScores), comparator);

          return DataTable(
            dataRowHeight: _DependencyListScreen._rowHeight,
            headingRowHeight: _DependencyListScreen._headingHeight,
            showCheckboxColumn: false,
            sortColumnIndex: _sortIndex,
            sortAscending: _sortAscending,
            columns: [
              DataColumn(label: Text('Package'), onSort: _onSort),
              DataColumn(label: Text('Version')),
              DataColumn(label: Text('Pub'), onSort: _onSort),
              DataColumn(label: Text('GitHub'), onSort: _onSort),
              DataColumn(label: Text('Imports')),
            ],
            rows: [
              for (var dependency in sortedDependencies)
                DataRow(
                  onSelectChanged: (selected) {
                    context.router.go(dependency.name);
                  },
                  cells: [
                    DataCell(Text(dependency.name)),
                    DataCell(
                      Tooltip(
                        message: "Upgrade available: BREAKING 3.0.0",
                        child: Row(
                          children: [
                            Text(dependency.lockDependency.version),
                            Icon(Icons.upgrade, size: 15),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      _PubCell(dependency, pubScores.data),
                    ),
                    DataCell(
                      _GithubCell(dependency, pubScores.data),
                    ),
                    DataCell(
                      Text('2'),
                    ),
                  ],
                ),
            ],
          );
        });
  }

  static Comparable _selectPackageName(
          Dependency d, Snapshot<PubScores> scores) =>
      d.name;
  static Comparable _selectPubScore(Dependency d, Snapshot<PubScores> scores) =>
      scores.data?[d.name]?.pub.popularityScore ?? 0;
  static Comparable _selectGithubScore(Dependency d, Snapshot<PubScores> scores) =>
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

  const _PubCell(this.dependency, this.pubScores, {super.key});

  @override
  Widget build(BuildContext context) {
    var popularityString = '';
    var pub = pubScores?[dependency.name]?.pub;
    var popularity = pub?.popularityScore;
    var likeCount = pub?.likeCount;
    var points = pub?.grantedPoints;
    if (popularity != null) {
      popularityString = '${(popularity * 100).toStringAsFixed(0)}%';
    }
    var message = [
      if (popularityString.isNotEmpty) '$popularityString popularity',
      if (likeCount != null) '$likeCount like${likeCount > 1 ? 's' : ''}',
      if (points != null) '$points point${points > 1 ? 's' : ''}',
    ];

    return Tooltip(
      message: message.join(' / '),
      child: Text(popularityString),
    );
  }
}

class _GithubCell extends StatelessWidget {
  final Dependency dependency;
  final PubScores? pubScores;

  const _GithubCell(this.dependency, this.pubScores, {super.key});

  @override
  Widget build(BuildContext context) {
    var github = pubScores?[dependency.name]?.github;
    if (github == null) {
      return const SizedBox();
    }

    var starCount = github.starCount;
    var forkCount = github.forkCount;
    return Tooltip(
      message: '${[
        '$starCount star${starCount > 1 ? 's' : ''}',
        '$forkCount fork${forkCount > 1 ? 's' : ''}',
      ].join(', ')}\n${github.slug}',
      child: Row(
        children: [
          Text('$starCount'),
          Icon(Icons.star_outline, size: 15),
        ],
      ),
    );
  }
}
