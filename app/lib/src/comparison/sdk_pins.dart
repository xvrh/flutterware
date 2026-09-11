import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Which Flutter a checkout says it wants, as the file a version manager
/// keeps it in says it.
///
/// **Read to say something, never to choose anything.** Both sides of a
/// comparison are rendered with the SDK the invocation named — flutterware
/// does not discover SDKs, and nothing here changes that. What a pin *can* do
/// is tell a reader that the two commits wanted different ones, which turns
/// every pixel of an SDK bump from "the branch changed all of this" into a
/// sentence explaining why. Without it every consumer comparing across a bump
/// wrote the same guard of their own.
class SdkPin {
  const SdkPin({required this.version, required this.file});

  /// What the file names — a version, a channel, whatever it holds.
  final String version;

  /// Which file said it, relative to the checkout.
  final String file;

  /// The pin governing [packagePath] in [checkout]: the nearest pin file from
  /// the package up to the checkout's top level, or null where none is.
  ///
  /// fvm's `.fvmrc` and its older `.fvm/fvm_config.json`, and `.tool-versions`
  /// for asdf and mise. Anything else pins nothing as far as this can tell,
  /// which costs a missing sentence and nothing more.
  static SdkPin? of(String checkout, {String packagePath = '.'}) {
    var root = p.normalize(checkout);
    var directory = p.normalize(p.join(root, packagePath));
    while (true) {
      for (var reader in _readers) {
        var path = p.join(directory, reader.file);
        String contents;
        try {
          contents = File(path).readAsStringSync();
        } on FileSystemException {
          continue;
        }
        if (reader.read(contents) case var version?) {
          return SdkPin(
            version: version,
            file: p.relative(path, from: root),
          );
        }
      }
      if (p.equals(directory, root) || !p.isWithin(root, directory)) {
        return null;
      }
      directory = p.dirname(directory);
    }
  }

  static final _readers = <({String file, String? Function(String) read})>[
    (file: '.fvmrc', read: (text) => _jsonField(text, 'flutter')),
    (
      file: p.join('.fvm', 'fvm_config.json'),
      read: (text) => _jsonField(text, 'flutterSdkVersion'),
    ),
    (file: '.tool-versions', read: _toolVersions),
  ];

  static String? _jsonField(String text, String field) {
    try {
      var json = jsonDecode(text);
      var value = json is Map ? json[field] : null;
      return value is String && value.isNotEmpty ? value : null;
    } on FormatException {
      return null;
    }
  }

  static String? _toolVersions(String text) {
    for (var line in const LineSplitter().convert(text)) {
      var words = line.trim().split(RegExp(r'\s+'));
      if (words.length >= 2 && words.first == 'flutter') return words[1];
    }
    return null;
  }

  /// A sentence for the verdict when [base] and [head] pin different Flutter
  /// versions, or null when they do not — or when either says nothing, since
  /// a missing pin is not a different one.
  ///
  /// [running] is the version both sides were rendered with, when the SDK
  /// records it.
  static String? caveat({
    required SdkPin? base,
    required SdkPin? head,
    String? running,
  }) {
    if (base == null || head == null || base.version == head.version) {
      return null;
    }
    // Plain words, no markdown: the same sentence is printed by the CLI and
    // drawn by the page as well as quoted in the comment.
    var files = base.file == head.file
        ? head.file
        : '${base.file} and ${head.file}';
    var ranOn = running == null
        ? 'the SDK this comparison was started with'
        : 'Flutter $running';
    return 'The base pins Flutter ${base.version} and this branch '
        '${head.version} ($files), but both sides were rendered with '
        "$ranOn: pixel differences may be the SDK's rather than the "
        "branch's.";
  }
}
