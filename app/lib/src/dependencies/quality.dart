import 'package:logging/logging.dart';
/*import 'package:pub_api_client/pub_api_client.dart';
import 'package:github/github.dart';

final _logger = Logger('dependency_quality');

class QualityClient {
  final _cache = <String, QualityReport>{};
  final _pubClient = PubClient();
  final _githubClient = GitHub();

  Future<QualityReport> fetch(String packageName) async =>
      _cache[packageName] ??= await _fetch(packageName);

  Future<QualityReport> _fetch(String packageName) async {
    var packageInfo = await _pubClient.packageInfo(packageName);
    var packageScore = await _pubClient.packageScore(packageName);

    var repositoryUri = packageInfo.latest.pubspec.repository ??
        Uri.tryParse(packageInfo.latest.pubspec.homepage ?? '');
    Repository? repository;
    if (repositoryUri != null && repositoryUri.host == 'github.com') {
      var segments = repositoryUri.pathSegments;
      if (segments.length >= 2) {
        try {
          repository = await _githubClient.repositories
              .getRepository(RepositorySlug(segments[0], segments[1]));
        } catch (e, s) {
          // Discard Github errors
          _logger.warning('Failed to load repository info [$repositoryUri]', e, s);
        }
      }
    }

    return QualityReport(packageInfo, packageScore, repository);
  }

  void close() {
    _pubClient.close();
    _githubClient.client.close();
  }
}

class QualityReport {
  final PubPackage _package;
  final PackageScore _score;
  final Repository? _repository;

  QualityReport(this._package, this._score, this._repository);

  int? get pubLikes => _score.likeCount;

  double? get pubPopularity => _score.popularityScore;

  int? get githubStars => _repository?.stargazersCount;
}
*/