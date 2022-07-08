import 'dart:io';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutterware_app/src/dependencies/model/package_imports.dart';
import 'package:flutterware_app/src/dependencies/model/service.dart';
import 'package:flutterware_app/src/utils/cloc/cloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pub_scores/pub_scores.dart';
import '../app/ui/breadcrumb.dart';
import '../project.dart';
import '../utils.dart';
import '../utils/async_value.dart';
import 'package:auto_size_text/auto_size_text.dart';

import 'utils.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class DependencyDetailScreen extends StatelessWidget {
  final Project project;
  final String packageName;

  const DependencyDetailScreen(this.project, this.packageName, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Snapshot<Dependencies>>(
      valueListenable: project.dependencies.dependencies,
      builder: (context, snapshot, child) {
        if (snapshot.hasError) {
          return ErrorWidget(snapshot.error!);
        } else if (snapshot.isLoading) {
          return LoadingPanel();
        } else {
          var dependency = snapshot.requireData[packageName];
          if (dependency == null) {
            return ErrorWidget('$packageName not found');
          }
          return ValueListenableBuilder<Snapshot<PubScores>>(
            valueListenable: project.dependencies.pubScores,
            builder: (context, pubScores, child) {
              return _DetailScreen(project, dependency, pubScores.data);
            },
          );
        }
      },
    );
  }
}

class _DetailScreen extends StatelessWidget {
  final Project project;
  final Dependency dependency;
  final PubScores? pubScores;

  const _DetailScreen(this.project, this.dependency, this.pubScores);

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    var version = dependency.pubspec.version;

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Breadcrumb(
              onBack: () {
                context.router.go('/project/dependencies');
              },
              children: [
                BreadcrumbEntry.overview,
                BreadcrumbEntry(
                    title: Text('Dependencies'), url: '/project/dependencies')
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: AutoSizeText(
                    dependency.name,
                    style: theme.textTheme.headlineMedium,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 10),
                if (version != null)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      'v$version',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              dependency.pubspec.description ?? '',
              style: const TextStyle(
                color: AppColors.blackSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Info', height: 35),
                Tab(text: 'Readme', height: 35),
                Tab(text: 'Changelog', height: 35),
              ],
            ),
            Container(
              color: AppColors.tabDivider,
              height: 1,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _InfoTab(this),
                  _FilePage(dependency, 'README.md'),
                  _FilePage(dependency, 'CHANGELOG.md'),
                ],
              ),
            ),
            InkWell(
              onTap: () {
                context.router.go('/project/dependencies');
              },
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18),
                  const SizedBox(width: 5),
                  Text('Back to list'),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatefulWidget {
  final _DetailScreen parent;

  const _InfoTab(this.parent);

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  bool _showAllTransitivePath = false;

  @override
  Widget build(BuildContext context) {
    var dependency = widget.parent.dependency;
    var scores = widget.parent.pubScores?.packages[dependency.name];
    var github = scores?.github;
    var pubInfo = scores?.pub;

    var transitivePaths =
        dependency.dependencyPaths.sortedBy((e) => e.join('-'));
    var transitivePathsToShow =
        _showAllTransitivePath ? transitivePaths : transitivePaths.take(4);
    var hiddenPathsLength =
        transitivePaths.length - transitivePathsToShow.length;

    var pubInfos = <String>[];
    if (pubInfo != null) {
      var popularity = pubInfo.popularity;
      var likeCount = pubInfo.likeCount;
      var grantedPoints = pubInfo.grantedPoints;
      if (popularity != null) {
        pubInfos.add('$popularity%');
      }
      pubInfos.add("$likeCount like${likeCount > 0 ? 's' : ''}");

      if (grantedPoints != null) {
        pubInfos.add('$grantedPoints point${grantedPoints > 0 ? 's' : ''}');
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: ListView(
            primary: false,
            children: [
              if (pubInfos.isNotEmpty)
                _InfoRow(
                  label: Text('Pub'),
                  value: InkWell(
                    onTap: () => openPub(dependency),
                    child: Text(pubInfos.join(', ')),
                  ),
                ),
              if (github != null)
                _InfoRow(
                  label: Text('Github'),
                  value: InkWell(
                    onTap: () => openGithub(github),
                    child: Text.rich(
                      TextSpan(
                        text:
                            '${github.starCount} star${github.starCount > 0 ? 's' : ''}, '
                            '${github.forkCount} fork${github.forkCount > 0 ? 's' : ''} (',
                        children: [
                          TextSpan(
                            text: github.slug,
                            style: const TextStyle(color: AppColors.link),
                          ),
                          TextSpan(text: ')'),
                        ],
                      ),
                    ),
                  ),
                ),
              if (dependency.isDirect)
                _InfoRow(
                  label: Text('Imports'),
                  value: ValueListenableBuilder<Snapshot<PackageImports>>(
                    valueListenable:
                        widget.parent.project.dependencies.packageImports,
                    builder: (context, snapshot, child) {
                      var packageImports = snapshot.data;
                      if (packageImports != null) {
                        var imports = packageImports[dependency.name];
                        return InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => _ImportListDialog(
                                widget.parent.project,
                                dependency,
                                imports,
                              ),
                            );
                          },
                          child: Text(
                            '${imports.length} import${imports.length > 1 ? 's' : ''}',
                            style: const TextStyle(color: AppColors.link),
                          ),
                        );
                      } else {
                        return Text('');
                      }
                    },
                  ),
                ),
              _InfoRow(
                label: Text('Dependency paths'),
                value: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var dependantPath in transitivePathsToShow)
                      Text(dependantPath.join(' → ')),
                    if (hiddenPathsLength > 0)
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showAllTransitivePath = true;
                          });
                        },
                        child: Text(
                          '+ $hiddenPathsLength',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.link,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _InfoRow(
                label: Text('Lines of Code'),
                value: ValueListenableBuilder<Snapshot<ClocReport>>(
                  valueListenable: dependency.cloc,
                  builder: (context, snapshot, child) {
                    var data = snapshot.data;
                    if (data != null) {
                      var numberFormat = NumberFormat.decimalPattern('en_US');

                      return Text(data.languages.entries
                          .sortedBy<num>((e) => e.value.lines)
                          .reversed
                          .map((e) =>
                              '${numberFormat.format(e.value.lines)} (${e.key.name})')
                          .join(', '));
                    } else {
                      return Text('');
                    }
                  },
                ),
              ),
              _InfoRow(
                label: Text('Size'),
                value: ValueListenableBuilder<Snapshot<SizeReport>>(
                  valueListenable: dependency.size,
                  builder: (context, snapshot, child) {
                    var data = snapshot.data;
                    if (data != null) {
                      return Text(
                          '${(data.totalBytes / 1000000).toStringAsFixed(1)} MB, '
                          '${data.fileCount} file${data.fileCount > 1 ? 's' : ''}');
                    } else {
                      return Text('');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final Widget label;
  final Widget value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 15),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.black54, fontSize: 13),
              child: label,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: value,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePage extends StatefulWidget {
  final Dependency dependency;
  final String fileName;

  const _FilePage(this.dependency, this.fileName);

  @override
  State<_FilePage> createState() => _FilePageState();
}

class _FilePageState extends State<_FilePage> {
  final _scrollController = ScrollController();
  late Future<String> _changelog;

  @override
  void initState() {
    super.initState();

    _changelog = _loadChangelog();
  }

  Future<String> _loadChangelog() async {
    //TODO(xha): find several files (.md, .txt etc...).
    var file = File(
        p.join(widget.dependency.package.root.toFilePath(), widget.fileName));
    return file.readAsString();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: FutureBuilder<String>(
          future: _changelog,
          builder: (context, snapshot) {
            return Markdown(
                controller: _scrollController, data: snapshot.data ?? '');
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class _ImportListDialog extends StatelessWidget {
  final Project project;
  final Dependency dependency;
  final List<File> files;

  const _ImportListDialog(this.project, this.dependency, this.files);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Imports of ${dependency.name}'),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxWidth: 500),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (context, index) {
            return Text(
              p.relative(
                files[index].absolute.path,
                from: project.absolutePath,
              ),
            );
          },
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('OK'),
        )
      ],
    );
  }
}
