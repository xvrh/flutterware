import 'dart:io';

import 'package:yaml/yaml.dart';

/// What a package's own pubspec declares, read straight off the file.
///
/// Both the workspace test and the session test need "what should this member
/// resolve to?", and both used to answer it with a number written into the
/// test. That made the count the assertion: adding one dev dependency to the
/// sample project failed two tests that had nothing to do with dependencies,
/// and the fix was to edit a literal — which is the moment an assertion stops
/// checking anything and starts recording whatever the code last did.
///
/// Deriving it from the pubspec puts the question back the right way round. The
/// claim under test is that a workspace member classifies against **its own**
/// declarations rather than the whole workspace resolution, so the pubspec is
/// the authority, and comparing name sets checks that far more sharply than
/// comparing cardinalities ever did.
class DeclaredDependencies {
  DeclaredDependencies({required this.dependencies, required this.devs});

  /// Reads the `dependencies:` and `dev_dependencies:` keys of [pubspecPath].
  factory DeclaredDependencies.of(String pubspecPath) {
    var yaml = loadYaml(File(pubspecPath).readAsStringSync());
    Set<String> names(String key) {
      var section = yaml is Map ? yaml[key] : null;
      // A bare `collection:` with no constraint is a null value, not a missing
      // key, so the keys are what matter and the values are never read.
      return section is Map
          ? {for (var name in section.keys) '$name'}
          : <String>{};
    }

    var dependencies = names('dependencies');
    if (dependencies.isEmpty) {
      // Otherwise a renamed key or a restructured pubspec makes every
      // comparison against this an empty set matching an empty set, and the
      // tests keep passing while checking nothing at all.
      throw StateError(
        'No `dependencies:` found in $pubspecPath — this is meant to be a '
        'package that declares some, so something has moved.',
      );
    }

    return DeclaredDependencies(
      dependencies: dependencies,
      devs: names('dev_dependencies'),
    );
  }

  final Set<String> dependencies;
  final Set<String> devs;
}
