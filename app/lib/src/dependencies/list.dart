import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../address/address_scope.dart';
import '../plugins/native/dependencies_address.dart';
import 'package:pub_scores/pub_scores.dart';
import '../ui/theme.dart';
import '../utils.dart';
import '../utils/async_value.dart';
import '../utils/value_stream_builder.dart';
import 'detail.dart';
import 'model/package_imports.dart';
import 'model/service.dart';
import 'upgrades.dart';
import 'utils.dart';

class DependenciesScreen extends StatefulWidget {
  final DependenciesService dependencies;

  /// The package this panel is showing — the first plugin-level segment, and
  /// the head of every segment list written from here.
  final String package;

  const DependenciesScreen(
    this.dependencies, {
    required this.package,
    super.key,
  });

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
    return PageStorage(bucket: _scrollBucket, child: _screen(context));
  }

  /// Reading the segments subscribes to the segments, so an axis or a knob
  /// moving does not rebuild this.
  Widget _screen(BuildContext context) {
    var place = dependencyPlace(AddressScope.segments(context));
    if (place == null) return _DependencyListScreen(this);
    if (place.upgrade) return DependenciesUpgradeScreen();
    if (place.dependency case var dependency?) {
      return DependencyDetailScreen(widget.dependencies, dependency);
    }
    return _DependencyListScreen(this);
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

  DependenciesService get dependencies => widget.parent.widget.dependencies;

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
    return ValueStreamBuilder<Snapshot<Dependencies>>(
      stream: dependencies.dependencies.snapshots,
      builder: (context, snapshot, child) {
        var data = snapshot.data;
        var error = snapshot.error;

        return ListView(
          key: PageStorageKey('dependencies_vertical'),
          primary: false,
          padding: const EdgeInsets.symmetric(
            horizontal: FwSpacing.xxl,
            vertical: FwSpacing.lg,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Dependencies', style: context.type.pageTitle),
                ),
                PopupMenuButton(
                  elevation: 2,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      child: Text('Reload'),
                      onTap: () {
                        dependencies.dependencies.refresh();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const Gap(FwSpacing.lg),
            if (data != null)
              _card(data)
            else if (error != null)
              ErrorPanel(
                message: 'Failed to load dependencies',
                onRetry: dependencies.dependencies.refresh,
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
      child: Column(children: [_header(), _table(dependencies)]),
    );
  }

  Widget _header() {
    var colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.tableHeader,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
      child: Row(
        children: [
          Container(
            width: 300,
            padding: const EdgeInsets.all(FwSpacing.md),
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
                borderRadius: BorderRadius.circular(context.radii.radiusLarge),
                color: colors.panel,
                border: Border.all(color: colors.line),
              ),
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list, size: 15, color: colors.mut),
                  const Gap(FwSpacing.xs),
                  Text('Show all', style: context.type.caption),
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
      filteredDependencies = dependencies.dependencies.where(
        (e) => e.name.toLowerCase().contains(query),
      );
    }

    return SizedBox(
      height:
          _DependencyListScreen._rowHeight * filteredDependencies.length +
          _DependencyListScreen._headingHeight,
      child: CustomScrollView(
        scrollDirection: Axis.horizontal,
        key: PageStorageKey('dependencies_horizontal'),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            fillOverscroll: true,
            child: _data(dependencies, filteredDependencies),
          ),
        ],
      ),
    );
  }

  Widget _data(Dependencies all, Iterable<Dependency> list) {
    return ValueStreamBuilder<Snapshot<PubScores>>(
      stream: dependencies.pubScores.snapshots,
      builder: (context, pubScores, child) {
        var sort = _sorts[_sortIndex]!;
        var comparator = (Comparable a, Comparable b) => a.compareTo(b);
        if (!_sortAscending) {
          comparator = comparator.inverse;
        }

        var sortedDependencies = list.sortedByCompare<Comparable>(
          (p) => sort(p, pubScores),
          comparator,
        );

        return DataTable(
          dataRowMinHeight: _DependencyListScreen._rowHeight,
          headingRowHeight: _DependencyListScreen._headingHeight,
          showCheckboxColumn: false,
          sortColumnIndex: _sortIndex,
          sortAscending: _sortAscending,
          columns: [
            DataColumn(label: Text('PACKAGE'), onSort: _onSort),
            DataColumn(label: Text('TYPE')),
            DataColumn(label: Text('VERSION')),
            DataColumn(label: Text('PUB'), onSort: _onSort),
            DataColumn(label: Text('GITHUB'), onSort: _onSort),
          ],
          rows: [
            for (var dependency in sortedDependencies)
              DataRow(
                onSelectChanged: (selected) {
                  AddressScope.write(context).setSegments(
                    dependencySegments(
                      widget.parent.widget.package,
                      dependency: dependency.name,
                    ),
                  );
                },
                cells: [
                  DataCell(
                    Text(dependency.name, style: context.type.bodyStrong),
                  ),
                  DataCell(
                    dependency.isTransitive
                        ? _DependencyTransitiveBadge(dependency)
                        : _DependencyDirectBadge(dependencies, dependency),
                  ),
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
    Dependency d,
    Snapshot<PubScores> scores,
  ) => d.name;

  static Comparable _selectPubScore(Dependency d, Snapshot<PubScores> scores) =>
      scores.data?[d.name]?.pub.popularity ?? 0;

  static Comparable _selectGithubScore(
    Dependency d,
    Snapshot<PubScores> scores,
  ) => scores.data?[d.name]?.github?.starCount ?? 0;

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
        child: Text(popularityString, style: context.type.bodyMuted),
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
        message:
            '${['$starCount star${starCount > 1 ? 's' : ''}', '$forkCount fork${forkCount > 1 ? 's' : ''}'].join(', ')}\n${github.slug}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$starCount', style: context.type.bodyMuted),
            const Gap(FwSpacing.xxs),
            Icon(Icons.star_outline, size: 15, color: context.colors.mut),
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
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.panel2,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: Tooltip(
        message: dependency.dependencyPaths
            .take(3)
            .map((l) => l.join(' > '))
            .join('\n'),
        child: Text('Transitive', style: context.type.micro),
      ),
    );
  }
}

class _DependencyDirectBadge extends StatelessWidget {
  final DependenciesService dependencies;
  final Dependency dependency;

  const _DependencyDirectBadge(this.dependencies, this.dependency);

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FwSpacing.md,
        vertical: FwSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.statusFill(colors.grn),
        border: Border.all(color: colors.statusBorder(colors.grn)),
        borderRadius: BorderRadius.circular(context.radii.radiusSmall),
      ),
      child: ValueStreamBuilder<Snapshot<PackageImports>>(
        stream: dependencies.packageImports.snapshots,
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
              style: context.type.micro.copyWith(color: colors.grn),
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
      style: context.type.bodyMuted,
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
