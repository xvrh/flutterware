import 'package:pub_scores/pub_scores.dart';
import 'package:url_launcher/url_launcher.dart';
import 'model/service.dart';

Future<void> openPub(Dependency dependency) {
  return launchUrl(Uri.https('pub.dev', 'packages/${dependency.name}'));
}

Future<void> openGithub(GitHubInfo github) {
  return launchUrl(Uri.https('github.com', github.slug));
}
