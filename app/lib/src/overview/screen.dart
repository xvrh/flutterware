import 'package:flutter/material.dart';
import 'package:flutterware_app/src/overview/service.dart';
import 'package:flutterware_app/src/utils/router_outlet.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/paths.dart' as paths;
import '../icon/model/service.dart';
import '../project.dart';
import '../ui/colors.dart';
import '../utils/async_value.dart';
import 'package:path/path.dart' as p;

import '../icon/image_provider.dart';

class OverviewScreen extends StatelessWidget {
  final Project project;

  const OverviewScreen(this.project, {super.key});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return ListView(
      primary: false,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      children: [
        Text(
          'FLUTTER APP',
          style: theme.textTheme.bodySmall,
        ),
        _ProjectInfoCard(project),
        const SizedBox(height: 30),
        Text(
          'INFO',
          style: theme.textTheme.bodySmall,
        ),
        _MetricsCard(),
        const SizedBox(height: 30),
        Text(
          'TOOLS',
          style: theme.textTheme.bodySmall,
        ),
        _ToolsCard(),
      ],
    );
  }
}

class _ProjectInfoCard extends StatelessWidget {
  final Project project;

  const _ProjectInfoCard(this.project);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Icon(project),
            const SizedBox(width: 15),
            Expanded(
              child: _data(),
            )
          ],
        ),
      ),
    );
  }

  Widget _data() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<Snapshot<Pubspec>>(
          valueListenable: project.pubspec,
          builder: (context, projectSnapshot, child) {
            var version = projectSnapshot.data?.version;
            String? versionString;
            if (version != null) {
              versionString =
                  '${version.major}.${version.minor}.${version.patch}';
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  projectSnapshot.data?.name ??
                      p.basename(project.directory.path),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 10),
                if (versionString != null)
                  Container(
                    decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      'v$versionString',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: InkWell(
            onTap: () => launchUrl(Uri.file(project.absolutePath)),
            child: Text(
              p.normalize(project.absolutePath),
              style: const TextStyle(
                color: Colors.black45,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.bottomLeft,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 2,
            ),
            child: ValueListenableBuilder<Snapshot<List<FlutterPlatform>>>(
              valueListenable: project.info.platforms,
              builder: (context, snapshot, child) {
                return Text(
                  snapshot.data?.map((p) => p.name.toUpperCase()).join(' | ') ??
                      '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Icon extends StatelessWidget {
  final Project project;

  const _Icon(this.project);

  @override
  Widget build(BuildContext context) {
    return Material(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.black12, width: 1),
      ),
      child: InkWell(
        onTap: () {
          context.router.go('/project/${paths.icon}');
        },
        child: SizedBox(
          width: IconService.previewSize.toDouble(),
          height: IconService.previewSize.toDouble(),
          child: ValueListenableBuilder<Snapshot<SampleIcon>>(
            valueListenable: project.icons.sample,
            builder: (context, snapshot, child) {
              var file = snapshot.data?.file;
              if (file != null) {
                return Image(image: AppIconImageProvider(file));
              }
              return const SizedBox();
            },
          ),
        ),
      ),
    );
  }
}

class _ToolsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Link('Launcher icon update', '/project/${paths.icon}'),
            _Link('Dependencies overview', '/project/${paths.dependencies}'),
            _Link('Hot-reloadable, visual test runner',
                '/project/${paths.tests}'),
            Text('• Widget preview: build UI in isolation (TODO)'),
            Text('• Assets management (TODO)'),
            Text('• Path & drawing (TODO)'),
            Text('• Animation editor (TODO)'),
            Text('• Theme editor (TODO)'),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  final String title;
  final String url;

  const _Link(this.title, this.url);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('• '),
        Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: () {
              context.router.go(url);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.link,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(
              label: Text('Dependencies'),
              value: InkWell(
                onTap: () {},
                child: Text("10 direct, 32 transitives"),
              ),
            ),
            _InfoRow(
              label: Text('Lines of Code'),
              value: Tooltip(
                message:
                    "lib: 90% (4560 LoC, 20 files)\ntest: 5% (1200)\nother: 3%",
                child: Text("12 530 (Dart), 45 645 (Java)"),
              ),
            ),
            _InfoRow(
              label: Text('Assets'),
              value: InkWell(
                onTap: () {},
                child: Text("120 files, 5.32 MB"),
              ),
            ),
          ],
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
    return Row(
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
    );
  }
}
