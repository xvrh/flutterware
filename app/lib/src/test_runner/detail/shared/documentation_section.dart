import 'package:flutter_studio/internal.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/ui/side_bar.dart';
import '../../../utils/assets.dart';

class DocumentationSection extends StatelessWidget {
  final ProjectInfo project;
  final ScenarioRun run;
  final String documentationKey;

  const DocumentationSection(
    this.project,
    this.run, {
    Key? key,
    required this.documentationKey,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarHeader(title: Text('Documentation')),
        ListTile(
          dense: true,
          leading: SizedBox(
            width: 20,
            child: Image.asset(
              assets.images.confluence.path,
            ),
          ),
          minLeadingWidth: 20,
          title: Text(documentationKey),
          onTap: () {
            var confluenceInfo = project.confluence;
            if (confluenceInfo != null) {
              var confluenceUrl = Uri.https(
                  '${confluenceInfo.site}.atlassian.net', 'wiki/search', {
                'text': '${confluenceInfo.docPrefix} ${[
                  ...run.scenario.name,
                  documentationKey
                ].join(' > ')}',
              });
              launchUrl(confluenceUrl);
            }
          },
        )
      ],
    );
  }
}
