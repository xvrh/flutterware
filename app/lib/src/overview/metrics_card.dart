import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../dependencies/model/service.dart';
import '../project.dart';
import '../utils.dart';
import '../utils/async_value.dart';
import '../utils/value_stream_builder.dart';
import '../utils/cloc/cloc.dart';
import 'model/code_metrics.dart';

class MetricsCard extends StatelessWidget {
  final Project project;

  MetricsCard(this.project, {super.key});

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
                onTap: () {
                  context.router.go('/project/dependencies');
                },
                child: ValueStreamBuilder<Snapshot<Dependencies>>(
                  stream: project.dependencies.dependencies.snapshots,
                  builder: (context, snapshot, child) {
                    var data = snapshot.data;
                    if (data == null) {
                      return Text('');
                    }

                    return Text(
                      '${data.directs.length} direct${data.directs.length > 1 ? 's' : ''}, '
                      '${data.transitives.length} transitive${data.transitives.length > 1 ? 's' : ''}',
                      style: const TextStyle(color: AppColors.link),
                    );
                  },
                ),
              ),
            ),
            _InfoRow(
              label: Text('Lines of Code'),
              value: ValueStreamBuilder<Snapshot<CodeMetrics>>(
                stream: project.info.codeMetrics,
                builder: (context, snapshot, child) {
                  if (snapshot.error != null) {
                    return ErrorPanel(
                      message: 'Failed to load code metrics: ${snapshot.error}',
                    );
                  }

                  var data = snapshot.data;
                  if (data == null) {
                    return Text('');
                  }

                  var numberFormat = NumberFormat.decimalPattern('en_US');

                  String describe(ClocResult result) =>
                      '${numberFormat.format(result.lines)} LoC, ${result.files} file${result.files > 1 ? 's' : ''}';

                  var description = [
                    for (var folder in {
                      'lib': data.lib,
                      'tests': data.tests,
                      'other': data.other,
                    }.entries)
                      '${folder.key}: ${describe(folder.value)}',
                  ].join('\n');

                  return Tooltip(
                    message: description,
                    child: Text(
                      '${numberFormat.format(data.sum.lines)} (Dart)',
                    ),
                  );
                },
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

  const _InfoRow({required this.label, required this.value});

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
          child: Align(alignment: Alignment.centerLeft, child: value),
        ),
      ],
    );
  }
}
