import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> args) {
  var pubspec = File('pubspec.yaml');
  var content = loadYaml(pubspec.readAsStringSync()) as YamlMap;

  var pubspecVersion = content['version'] as String;
  var tagVersion = '';
  if (args.isNotEmpty) {
    tagVersion = args[0].split('/').last;
  }
  if (tagVersion.startsWith('v')) {
    tagVersion = tagVersion.substring(1);
  }

  if (pubspecVersion != tagVersion) {
    stderr.writeln(
      '::error::pubspec says $pubspecVersion, the tag says $tagVersion. '
      'A published version is permanent — fix the tag or the pubspec before '
      'publishing.',
    );
    exit(1);
  }
}
