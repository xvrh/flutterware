import 'package:flutter_studio/internals/test_runner.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../utils/assets.dart';

class AnalyticEventDialog extends StatelessWidget {
  final ProjectInfo project;
  final AnalyticEvent event;

  const AnalyticEventDialog(this.project, this.event, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    var firebaseInfo = project.firebase;
    return AlertDialog(
      title: Row(
        children: [
          Image.asset(
            assets.images.googleAnalytics.path,
            height: 30,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Analytic event')),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Event'),
              subtitle: Text(event.event),
            ),
            ListTile(
              title: Text('Parameters'),
              subtitle: Text(event.args.toString()),
            ),
          ],
        ),
      ),
      actions: [
        if (firebaseInfo != null)
          OutlinedButton(
            onPressed: () {
              //TODO(xha)
            },
            child: Text('Open Firebase'),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('OK'),
        ),
      ],
    );
  }
}
