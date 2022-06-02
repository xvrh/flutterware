import 'dart:io';
import 'dart:isolate';

void main() async {
  final packageUri = await Isolate.resolvePackageUri(
      Uri.parse('package:args/your/asset/path/some_file.whatever'));
  print('''Flutter Studio
Commands:
- app: start the graphic user interface
- screenshots: run the test and generate the screenshots  
${Platform.resolvedExecutable}
${Platform.script}
$packageUri
''');
}
