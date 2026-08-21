import 'pubspec_lock.dart';

/// Where a package came from, with the detail that makes the answer useful.
///
/// `pub deps --json` says *which kind* of source resolved a package — `hosted`,
/// `git`, `path`, `sdk` — and stops there. The URL, the git ref and the relative
/// path are only in the lockfile's `description:` block. Neither alone can tell
/// you that `pub_scores` is `github.com/xvrh/pub-scores.git @ master`, which is
/// the thing a human is actually asking when they wonder where a package came
/// from. So this is built from the lock where there is a lock entry, and falls
/// back to the bare source name where there is not.
sealed class PackageOrigin {
  const PackageOrigin();

  /// Short chip text — what kind of thing this is.
  String get label;

  /// The identifying detail, or null when the [label] already says everything.
  /// A URL, a slug, a relative path.
  String? get detail;

  /// Built from a lock entry, which is the only place the details live.
  factory PackageOrigin.fromLock(LockDependency lock) {
    var description = lock.description;
    String? string(String key) {
      var value = description is Map ? description[key] : null;
      return value is String ? value : null;
    }

    switch (lock.source) {
      case 'hosted':
        return HostedOrigin(
          server: string('url') ?? _pubDev,
          name: string('name') ?? lock.name,
        );
      case 'git':
        return GitOrigin(
          url: string('url') ?? '',
          ref: string('ref'),
          resolvedRef: string('resolved-ref'),
          // Pub writes `.` for a package at the repository root, which is
          // noise on a chip.
          subPath: switch (string('path')) {
            null || '.' => null,
            var p => p,
          },
        );
      case 'path':
        return PathOrigin(
          path: string('path') ?? '',
          relative: description is Map && description['relative'] == true,
        );
      case 'sdk':
        // The whole description is a scalar here — `description: flutter` —
        // not a map, which is why nothing above would have found it.
        return SdkOrigin(description is String ? description : 'flutter');
      default:
        return UnknownOrigin(lock.source);
    }
  }

  /// For a package with no lock entry — a workspace member, which pub does not
  /// list in the lockfile because it is not something the lockfile resolved.
  static PackageOrigin fromSourceName(String source) => switch (source) {
    'root' => const WorkspaceOrigin(),
    'sdk' => const SdkOrigin('flutter'),
    'hosted' => const HostedOrigin(server: _pubDev, name: ''),
    _ => UnknownOrigin(source),
  };
}

const _pubDev = 'https://pub.dev';

/// A package from a pub server. [server] is worth showing only when it is not
/// pub.dev — a private registry is exactly the kind of thing you want to notice.
class HostedOrigin extends PackageOrigin {
  const HostedOrigin({required this.server, required this.name});

  final String server;

  /// The name on the server, which can differ from the package's local name.
  final String name;

  bool get isPubDev =>
      server == _pubDev || server == 'https://pub.dartlang.org';

  @override
  String get label => isPubDev ? 'pub.dev' : 'hosted';

  @override
  String? get detail => isPubDev ? null : server;
}

class GitOrigin extends PackageOrigin {
  const GitOrigin({
    required this.url,
    this.ref,
    this.resolvedRef,
    this.subPath,
  });

  final String url;

  /// The branch or tag asked for. Null when the dependency named none, in which
  /// case pub tracked the default branch.
  final String? ref;

  /// The commit actually resolved. The exact answer to "which code is this",
  /// since [ref] can move under you.
  final String? resolvedRef;

  /// Where in the repository the package sits, or null when it is the root.
  final String? subPath;

  /// `xvrh/pub-scores` out of `https://github.com/xvrh/pub-scores.git`, for a
  /// chip that has to fit in a table cell.
  String get slug {
    var trimmed = url.endsWith('.git') ? url.substring(0, url.length - 4) : url;
    var uri = Uri.tryParse(trimmed);
    if (uri == null || uri.pathSegments.isEmpty) return trimmed;
    return uri.pathSegments.join('/');
  }

  String? get shortRef => resolvedRef == null
      ? ref
      : '${ref ?? 'HEAD'}@${resolvedRef!.substring(0, 7)}';

  @override
  String get label => 'git';

  @override
  String? get detail => subPath == null ? slug : '$slug/$subPath';
}

class PathOrigin extends PackageOrigin {
  const PathOrigin({required this.path, required this.relative});

  final String path;

  /// Whether [path] is relative to the depending package. An absolute path
  /// dependency is machine-specific and worth flagging.
  final bool relative;

  @override
  String get label => 'path';

  @override
  String? get detail => path;
}

/// Shipped with the SDK — `flutter`, `flutter_test`, `sky_engine`. These resolve
/// with version `0.0.0`, so anywhere a version would be printed must ask about
/// this first.
class SdkOrigin extends PackageOrigin {
  const SdkOrigin(this.sdk);

  final String sdk;

  @override
  String get label => sdk == 'flutter' ? 'Flutter SDK' : '$sdk SDK';

  @override
  String? get detail => null;
}

/// A member of the enclosing pub workspace — your own code, not a dependency
/// that was fetched from anywhere.
class WorkspaceOrigin extends PackageOrigin {
  const WorkspaceOrigin();

  @override
  String get label => 'workspace';

  @override
  String? get detail => null;
}

/// A source neither pub deps nor the lockfile explained. Kept rather than
/// thrown so one unrecognised entry cannot take down the whole listing.
class UnknownOrigin extends PackageOrigin {
  const UnknownOrigin(this.source);

  final String source;

  @override
  String get label => source;

  @override
  String? get detail => null;
}
