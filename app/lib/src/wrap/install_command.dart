import 'dart:io';

import 'package:args/command_runner.dart';

import 'installer.dart';

/// Builds the per-project SDK mirror facade. Sub-project 0 assumes a shared
/// SDK already exists; this command wraps it.
class InstallCommand extends Command<int> {
  @override
  final name = 'install';
  @override
  final description = 'Install the SDK mirror facade for a project.';

  InstallCommand() {
    argParser
      ..addOption('sdk', help: 'Path to the existing shared Flutter SDK.')
      ..addOption('project', help: 'Path to the project root.')
      ..addOption('wrap-exe',
          help: 'Path to the compiled wrap executable to bake into shims.');
  }

  @override
  Future<int> run() async {
    final sdk = argResults!['sdk'] as String?;
    final project = argResults!['project'] as String?;
    final wrapExe = argResults!['wrap-exe'] as String?;
    if (sdk == null || project == null || wrapExe == null) {
      stderr.writeln('[wrap] install requires --sdk, --project, --wrap-exe');
      return 64;
    }
    final mirror = installMirror(
      sharedSdk: Directory(sdk),
      projectRoot: Directory(project),
      wrapExe: wrapExe,
    );
    stdout.writeln('Installed SDK mirror at ${mirror.path}');
    return 0;
  }
}
