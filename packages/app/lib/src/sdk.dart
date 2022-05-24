import 'dart:io';
import 'package:path/path.dart' as p;

class FlutterSdk {
  final String root;

  FlutterSdk(this.root);

  factory FlutterSdk.fromJson(Map<String, dynamic> json) =>
      FlutterSdk(json['root'] as String);

  Map<String, dynamic> toJson() => {'root': root};

  String get flutter =>
      p.join(root, 'bin', 'flutter${Platform.isWindows ? '.bat' : ''}');

  String get dart =>
      p.join(root, 'bin', 'dart${Platform.isWindows ? '.bat' : ''}');
}
