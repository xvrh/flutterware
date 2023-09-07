import 'package:flutter/material.dart';
import 'package:flutterware/src/devbar/plugins/log_analytics/plugin.dart';
import '../../devbar.dart';
import '../../../utils/value_stream.dart';
import '../../utils/json_viewer.dart';
import '../../utils/timeago/timeago.dart';

class AnalyticsList extends StatelessWidget {
  final LogAnalyticsPlugin service;
  const AnalyticsList(this.service, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueStreamBuilder<List<AnalyticEvent>>(
      stream: service.events,
      builder: (context, logs) => ListView.separated(
        separatorBuilder: (context, index) => Container(
          height: 1,
          color: Colors.white.withOpacity(0.2),
        ),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return EventTile(logs[logs.length - 1 - index]);
        },
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  final AnalyticEvent event;

  const EventTile(this.event, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var devbar = DevbarState.of(context);

    return ListTile(
      dense: true,
      leading: Icon(Icons.info),
      title: Text(event.name),
      subtitle:
          event.parameters != null ? Text(event.parameters.toString()) : null,
      trailing: Text(timeAgo(event.time)),
      onTap: () {
        devbar.ui.showOverlayDialog(
          builder: (context) => _DetailDialog(event),
        );
      },
    );
  }
}

class _DetailDialog extends StatelessWidget {
  final AnalyticEvent event;

  const _DetailDialog(this.event, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(event.name),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Parameters'),
              subtitle: JsonViewer(event.parameters),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('OK'),
        ),
      ],
    );
  }
}
