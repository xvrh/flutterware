import 'package:package_config/package_config.dart';
import '../project.dart';
import '../utils/async_value.dart';
import '../utils/cloc/cloc.dart';
import 'pubspec_lock.dart';

class DependenciesService {
  final Project project;
  late final dependencies = AsyncValue<Dependencies>(loader: _load);

  DependenciesService(this.project);

  Future<Dependencies> _load() async {
    var pubspecLock = await PubspecLock.load(project.absolutePath);
    var packageConfig = (await findPackageConfig(project.directory))!;

    var results = <Dependency>[];
    for (var dependency in pubspecLock.packages) {
      var package = packageConfig[dependency.name];
      if (package != null) {
        results.add(Dependency(package, dependency));
      }
    }
    return Dependencies(results);
  }

  void dispose() {
    dependencies.dispose();
  }
}

class Dependencies implements Disposable {
  final List<Dependency> dependencies;

  Dependencies(this.dependencies);

  List<Dependency>? _directs;
  List<Dependency> get directs => _directs ??= dependencies
      .where((e) =>
          e.lockDependency.type != DependencyType.transitive &&
          e.lockDependency.source == 'hosted')
      .toList();

  List<Dependency>? _transitives;
  List<Dependency> get transitives => _transitives ??= dependencies
      .where((e) =>
          e.lockDependency.type == DependencyType.transitive &&
          e.lockDependency.source == 'hosted')
      .toList();

  @override
  void dispose() {
    for (var dependency in dependencies) {
      dependency.dispose();
    }
  }
}

class Dependency implements Disposable {
  final Package package;
  final LockDependency lockDependency;
  late final cloc = AsyncValue<ClocReport>(loader: _loadCloc, lazy: true);
  late final github = AsyncValue<GithubReport>(loader: _loadGithub, lazy: true);
  late final pub = AsyncValue<PubReport>(loader: _loadPubReport, lazy: true);

  Dependency(this.package, this.lockDependency);

  String get name => lockDependency.name;

  Future<ClocReport> _loadCloc() async {
    throw UnimplementedError();
  }

  Future<GithubReport> _loadGithub() async {
    throw UnimplementedError();
  }

  Future<PubReport> _loadPubReport() async {
    throw UnimplementedError();
  }

  @override
  void dispose() {
    cloc.dispose();
  }
}

class GithubReport {}

class PubReport {
  // PubClient https://pub.dartlang.org/api/packages/puppeteer
}
