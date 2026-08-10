import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../splash/model/fingerprint.dart';
import '../../splash/model/generated.dart';
import '../../splash/model/scan.dart';
import '../../splash/model/surface.dart';
import '../../splash/model/validation.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'splash_address.dart';
import 'splash_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const splashPluginId = 'flutterware.splash';

/// What each declared package's `flutter_native_splash` config will actually
/// produce, per surface and per theme.
///
/// The subject is deliberately **the resolved surface, not the config file**.
/// What you wrote and what Android 12 shows are several cascade steps apart,
/// and the gap between them is the whole reason this exists — so the unit of
/// everything here is a cell of the matrix, addressable as
/// `?surface=android12&theme=dark`.
///
/// Holds to the two rules every core holds to: the constructor allocates
/// nothing, and [report] only formats what somebody already caused to load.
/// Loading is parsing YAML and reading a dozen image headers.
class SplashCore extends PluginCore {
  SplashCore(
    super.host, {
    this.pollInterval = const Duration(milliseconds: 750),
  });

  /// How often a retained package's files are re-checked against the scan on
  /// screen. [Duration.zero] disables polling, which is what a test that drives
  /// [checkForChanges] by hand wants.
  final Duration pollInterval;

  /// Declared packages, filtered to those the workspace knows about, so a typo
  /// cannot make the plugin scan a directory that is not there.
  late final List<String> packages = [
    for (var path in host.packagePaths)
      if (host.workspace.exists(path)) path,
  ];

  final _scans = <String, SplashScan>{};
  final _failures = <String, String>{};
  final _scanning = <String>{};
  final _pending = <String, Future<void>>{};

  /// The state each scan was made against, so a poll can tell whether it still
  /// holds. See `model/fingerprint.dart` for why this is polled rather than
  /// watched.
  final _fingerprints = <String, String>{};

  /// When each scan last ran, so the panel can print it.
  ///
  /// Stamped here rather than inside [scanSplash], which stays pure — a model
  /// that reads the clock is a model whose tests need one.
  final _scannedAt = <String, DateTime>{};

  /// The scan for [path], or null when nothing has looked at it yet.
  SplashScan? scanFor(String path) => _scans[path];

  String? failureFor(String path) => _failures[path];

  bool isScanning(String path) => _scanning.contains(path);

  /// When [path] was last read off disk, or null when it never has been.
  DateTime? scannedAt(String path) => _scannedAt[path];

  /// The package's absolute root — what turns a package-relative artifact path
  /// into a file a renderer can open.
  String packageRootFor(String path) =>
      host.workspace.packageFor(path).absolutePath;

  /// Where a cell *is*.
  ///
  /// Built here rather than left to a reader to reassemble, which is how two
  /// surfaces come to disagree about what a thing is called. The surface and
  /// theme are axes, not segments — the same splash seen differently.
  Address addressFor(
    String packagePath, {
    String? flavor,
    SplashSurface? surface,
    SplashTheme? theme,
    String? device,
  }) => Address(
    worktree: host.worktree.name,
    plugin: host.id,
    segments: splashSegments(packagePath, flavor),
    axes: splashAxes(surface: surface, theme: theme, device: device),
  );

  /// Scans [path], unless it already has been. Idempotent.
  void track(String path) => unawaited(_load(path));

  /// Drops the cached scan so the next [track] re-reads. What the panel calls
  /// when the config file changes underneath it.
  void invalidate(String path) {
    _scans.remove(path);
    _failures.remove(path);
    // Without this, the next [_load] hands back the scan this just threw away.
    _pending.remove(path);
    notifyChanged();
  }

  @override
  Future<void> computeAll() async {
    await Future.wait([for (var path in packages) _load(path)]);
  }

  /// Scans [path] unless a scan is already cached or in flight.
  ///
  /// **The de-duplication cannot be `_pending.putIfAbsent(path, () =>
  /// _scan(path))`**, which is what it was. `_scan` has no `await` before its
  /// `finally`, so an `async` body runs start to finish synchronously — the
  /// clean-up inside it therefore ran *during* `putIfAbsent`'s callback, before
  /// the entry it was trying to remove had been inserted. The entry then stayed
  /// forever, and every later load after an [invalidate] returned that completed
  /// future instead of reading the disk.
  ///
  /// It was invisible while `invalidate` was only ever called by `generate`,
  /// whose result nothing asserted. Registering the entry first and clearing it
  /// through `whenComplete` fixes it whether or not `_scan` yields.
  ///
  /// The clean-up must be a **block**, not `() => _pending.remove(path)`.
  /// `Map.remove` returns the value it removed — here, the very future
  /// `whenComplete` is completing — and `whenComplete` waits on any future its
  /// callback returns. An arrow body therefore makes the future wait for
  /// itself, and every load hangs.
  Future<void> _load(String path) {
    if (_scans.containsKey(path) || _failures.containsKey(path)) {
      return Future.value();
    }
    return _pending[path] ??= _scan(path).whenComplete(() {
      _pending.remove(path);
    });
  }

  Future<void> _scan(String path) async {
    _scanning.add(path);
    notifyChanged();
    var root = host.workspace.packageFor(path).absolutePath;
    try {
      _scans[path] = scanSplash(packageRoot: root, packagePath: path);
    } catch (e) {
      _failures[path] = '$e';
    } finally {
      // Fingerprinted on the failure path too, so a broken config that is fixed
      // recovers on the next poll instead of staying broken until something
      // else invalidates it.
      _fingerprints[path] = splashFingerprint(
        packageRoot: root,
        scan: _scans[path],
      );
      _scannedAt[path] = DateTime.now();
      _scanning.remove(path);
      notifyChanged();
    }
  }

  // ---- Polling -----------------------------------------------------------

  Timer? _poll;
  var _retained = 0;
  var _checking = false;

  /// Begins polling, and returns the release for it.
  ///
  /// Reference-counted rather than a bare start/stop pair: two panels on one
  /// core is not a shape the shell produces today, but a stop that the *other*
  /// one still needed would be a preview that silently goes cold, which is the
  /// exact failure this whole mechanism exists to prevent.
  ///
  /// Retained by a panel appearing, released by it going away. Not by [track] —
  /// `fw` and MCP track through [computeAll] and exit, and a timer they never
  /// release would hold the process open.
  void Function() retain() {
    _retained++;
    if (_poll == null && pollInterval > Duration.zero && !isDisposed) {
      _poll = Timer.periodic(pollInterval, (_) => unawaited(checkForChanges()));
    }
    var released = false;
    return () {
      // Idempotent: a State disposed twice must not decrement twice and take
      // somebody else's retain with it.
      if (released) return;
      released = true;
      if (--_retained > 0) return;
      _poll?.cancel();
      _poll = null;
    };
  }

  /// Re-reads any tracked package whose files have moved since its scan.
  ///
  /// Public because a test driving this by hand is far steadier than one waiting
  /// on a timer, and because the reload path wants the same work.
  Future<void> checkForChanges() async {
    if (_checking || isDisposed) return;
    _checking = true;
    try {
      // Snapshotted: the loop invalidates, which mutates what it is iterating.
      for (var path in {..._scans.keys, ..._failures.keys}) {
        if (_scanning.contains(path)) continue;
        var root = host.workspace.packageFor(path).absolutePath;
        var current = splashFingerprint(packageRoot: root, scan: _scans[path]);
        if (current == _fingerprints[path]) continue;
        invalidate(path);
        await _load(path);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _poll = null;
    super.dispose();
  }

  // ---- Report ------------------------------------------------------------

  @override
  PluginReport get report => PluginReport(
    id: host.id,
    label: host.label,
    status: _status,
    badge: _badge,
    children: [
      for (var path in packages)
        PluginChild(
          id: path,
          label: path == '.' ? 'root' : path,
          status: _childStatus(path),
        ),
    ],
    actions: _actions,
    view: _view,
  );

  /// The plugin's own row, which stays **quiet**.
  ///
  /// Two things had to go. "Not computed" was true and useless: it is the state
  /// every plugin is in until you click it, so it drew the eye on every sidebar
  /// paint to say nothing had happened yet. And a problem count here repeated
  /// what the package row underneath already said — one package means the same
  /// number twice, on two adjacent lines.
  ///
  /// So this speaks only for things that are the *plugin's*, not a package's: no
  /// packages declared, or a config file the generator would refuse. Counts live
  /// on the package rows, and [_badge] still carries the tone, so nothing is
  /// lost — the sidebar signals without narrating.
  Status get _status {
    if (packages.isEmpty) return const Status.warn('No packages configured');

    // A file that looks like a config and is not one outranks everything else:
    // the generator refuses to run at all, so counting problems in the configs
    // that *did* parse would describe a run that never happens.
    var scanned = [for (var path in packages) _scans[path]].nonNulls.toList();
    var broken = scanned.expand((s) => s.configErrors).toList();
    if (broken.isNotEmpty) {
      return Status.error(
        broken.length == 1 ? broken.first : '${broken.length} unusable configs',
      );
    }

    return Status.none;
  }

  /// The worst thing any package has to say, as a mark rather than a sentence.
  ///
  /// This is what survives [_status] going quiet: a tab glyph still turns amber
  /// when something wants looking at, and costs no words to do it.
  StatusBadge get _badge {
    var worst = Tone.neutral;
    for (var path in packages) {
      if (_failures.containsKey(path)) return const StatusBadge.dot(Tone.error);
      var scan = _scans[path];
      if (scan == null) continue;
      if (scan.configErrors.isNotEmpty) {
        return const StatusBadge.dot(Tone.error);
      }
      for (var config in scan.configs) {
        for (var problem in config.problems) {
          if (problem.blocksGeneration || problem.tone == Tone.error) {
            return const StatusBadge.dot(Tone.error);
          }
          if (problem.tone == Tone.warn) worst = Tone.warn;
        }
      }
    }
    return worst == Tone.warn
        ? const StatusBadge.dot(Tone.warn)
        : StatusBadge.none;
  }

  Status _childStatus(String path) {
    var failure = _failures[path];
    if (failure != null) return Status.error(failure);
    var scan = _scans[path];
    if (scan == null) {
      // Silent until it has been looked at, for the same reason the plugin row
      // is: "not computed" is the resting state, not news.
      return _scanning.contains(path)
          ? const Status.info('Reading…')
          : Status.none;
    }
    if (scan.configErrors.isNotEmpty) {
      return Status.error(scan.configErrors.first);
    }
    if (!scan.isConfigured) return const Status.neutral('No splash configured');

    var problems = [for (var config in scan.configs) ...config.problems];
    var blocking = problems.where((p) => p.blocksGeneration).length;
    if (blocking > 0) return Status.error('$blocking blocking');
    var warnings = problems.where((p) => p.tone == Tone.warn).length;
    if (warnings > 0) {
      return Status.warn('$warnings warning${warnings == 1 ? '' : 's'}');
    }
    return Status.good(scan.main!.config.path);
  }

  PluginView get _view {
    var nodes = <ViewNode>[];
    for (var path in packages) {
      var scan = _scans[path];
      if (scan == null) continue;
      nodes.add(
        ViewSection(path == '.' ? 'root' : path, [
          for (var error in scan.configErrors)
            ViewText(error, tone: Tone.error),
          if (!scan.isConfigured && scan.configErrors.isEmpty)
            const ViewText(
              'No flutter_native_splash config — no flutter_native_splash.yaml, '
              'and no flutter_native_splash: key in the pubspec.',
            )
          else
            for (var config in scan.configs) ..._configNodes(path, config),
        ]),
      );
    }
    return PluginView(nodes);
  }

  List<ViewNode> _configNodes(String packagePath, SplashConfigScan scan) {
    var title = scan.config.flavor == null
        ? scan.config.path
        : '${scan.config.path} (flavor ${scan.config.flavor})';

    return [
      ViewSection(title, [
        ViewTable(
          const ['Surface', 'Theme', 'Background', 'Image', 'Placement'],
          [
            for (var surface in SplashSurface.values)
              for (var theme in SplashTheme.values)
                _matrixRow(scan, surface, theme),
          ],
        ),
        if (scan.problems.isNotEmpty)
          ViewSection('Problems', [
            ViewItems([
              for (var problem in scan.problems)
                ViewItem(
                  problem.key ?? problem.surface?.label ?? 'config',
                  detail: problem.message,
                  tone: problem.tone,
                  address: problem.surface == null
                      ? null
                      : addressFor(
                          packagePath,
                          flavor: scan.config.flavor,
                          surface: problem.surface,
                          theme: problem.theme,
                          // A fit problem that cannot take you to the screen it
                          // is about is just a sentence.
                          device: problem.device,
                        ),
                ),
            ]),
          ]),
        ViewField(
          'Generated',
          scan.isGenerated
              ? '${scan.artifacts.length} files${scan.stale ? ' (stale)' : ''}'
              : 'never — run `dart run flutter_native_splash:create`',
          tone: scan.stale ? Tone.warn : Tone.neutral,
        ),
      ]),
    ];
  }

  List<String> _matrixRow(
    SplashConfigScan scan,
    SplashSurface surface,
    SplashTheme theme,
  ) {
    var resolution = scan.resolutionFor(surface, theme);
    if (!resolution.enabled) {
      return [surface.label, theme.label, 'disabled', '', ''];
    }
    var composition = scan.compositionFor(surface, theme);
    return [
      surface.label,
      theme.label + (resolution.fallsBackToLight ? ' (light)' : ''),
      resolution.backgroundImage.isPresent
          ? resolution.backgroundImage.value!
          : resolution.color.value == null
          ? '—'
          : '#${resolution.color.value}',
      composition.image?.path ?? '—',
      composition.image == null ? '' : resolution.placementSummary,
    ];
  }

  // ---- Actions -----------------------------------------------------------

  ActionParameter get _packageParameter => ActionParameter(
    'package',
    'Package',
    kind: ActionParameterKind.choice,
    required: false,
    description: 'Which declared package; the first when omitted',
    options: [
      for (var path in packages)
        ActionOption(path, label: path == '.' ? 'root' : path),
    ],
  );

  static const _flavorParameter = ActionParameter(
    'flavor',
    'Flavor',
    required: false,
    description:
        'Which flutter_native_splash-<flavor>.yaml; the default config when '
        'omitted',
  );

  List<PluginAction> get _actions => [
    PluginAction(
      'describe',
      'Describe',
      returns: SplashDescribeResult,
      description:
          'One surface and theme resolved in full — every value, the config '
          'key each one came from, and where the image lands, in words',
      parameters: [
        _packageParameter,
        ActionParameter(
          'surface',
          'Surface',
          kind: ActionParameterKind.choice,
          defaultValue: SplashSurface.android.name,
          required: false,
          description:
              'Android 12+ is its own surface: it reads different keys and '
              'ignores most of the legacy ones',
          options: [
            for (var surface in SplashSurface.values)
              ActionOption(surface.name, label: surface.label),
          ],
        ),
        ActionParameter(
          'theme',
          'Theme',
          kind: ActionParameterKind.choice,
          defaultValue: SplashTheme.light.name,
          required: false,
          options: [
            for (var theme in SplashTheme.values)
              ActionOption(theme.name, label: theme.label),
          ],
        ),
        _flavorParameter,
      ],
    ),
    PluginAction(
      'reload',
      'Reload',
      returns: SplashReloadResult,
      description:
          'Re-reads the config and everything it references, now. The panel '
          'notices most edits on its own; this is what covers the filesystems '
          'where it cannot, and it answers "did my edit land in the file this '
          'project actually reads?"',
      parameters: [_packageParameter],
    ),
    PluginAction(
      'artifacts',
      'Artifacts',
      returns: SplashArtifactsResult,
      description:
          'The real generated files as they are on disk — ground truth, once '
          'generate has run',
      parameters: [_packageParameter],
    ),
    PluginAction(
      'generate',
      // The command, not a verb. "Generate" says nothing about what it will do
      // to your project, and this one rewrites files under android/, ios/ and
      // web/ — the label is the first and often only place anybody reads that.
      'Run flutter_native_splash:create',
      returns: SplashGenerateResult,
      confirm: true,
      description:
          'Runs `dart run flutter_native_splash:create` in the package, using '
          'the version the project pins. This is what turns the config into '
          'real files; until it runs, everything the panel shows is a '
          'prediction. Rewrites files under android/, ios/ and web/.',
      parameters: [_packageParameter, _flavorParameter],
    ),
  ];

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async {
    var path = _packageArgument(arguments);

    // Before the failure check, not after: reload is precisely what you call to
    // clear a failure, and refusing to run it because the last scan threw would
    // leave a project whose config was fixed with no way back.
    if (actionId == 'reload') return await _reload(path);

    await _load(path);
    var failure = _failures[path];
    if (failure != null) throw StateError(failure);

    return switch (actionId) {
      'describe' => _describe(path, arguments),
      'artifacts' => _artifacts(path),
      'generate' => await _generate(path, arguments),
      // The base refusal rather than a second copy of it, so this one also
      // names what is declared.
      _ => await super.invoke(actionId, arguments: arguments),
    };
  }

  String _packageArgument(Map<String, Object?> arguments) {
    var given = arguments['package'];
    if (given is String && given.isNotEmpty) {
      if (!packages.contains(given)) {
        throw ArgumentError.value(
          given,
          'package',
          'not declared for this plugin; try one of ${packages.join(', ')}',
        );
      }
      return given;
    }
    if (packages.isEmpty) {
      throw StateError('No packages are configured for $id.');
    }
    return packages.first;
  }

  SplashConfigScan _configArgument(
    String path,
    Map<String, Object?> arguments,
  ) {
    var scan = _scans[path]!;
    var flavor = arguments['flavor'];
    var wanted = flavor is String && flavor.isNotEmpty ? flavor : null;
    var config = scan.forFlavor(wanted);
    if (config == null) {
      throw StateError(
        wanted == null
            ? 'No flutter_native_splash config in "$path".'
            : 'No flutter_native_splash-$wanted.yaml in "$path". '
                  'Found: ${scan.flavors.isEmpty ? 'none' : scan.flavors.join(', ')}',
      );
    }
    return config;
  }

  SplashDescribeResult _describe(String path, Map<String, Object?> arguments) {
    var config = _configArgument(path, arguments);
    var surface =
        SplashSurface.byName('${arguments['surface'] ?? ''}') ??
        SplashSurface.android;
    var theme =
        SplashTheme.byName('${arguments['theme'] ?? ''}') ?? SplashTheme.light;

    var resolution = config.resolutionFor(surface, theme);
    // The generated files where they exist, exactly as the panel does — an
    // agent asking "what does the splash look like" and a person looking at the
    // tile must not be answered from different halves of the plugin.
    var picture = config.pictureFor(surface, theme);

    return SplashDescribeResult(
      package: path,
      address:
          '${addressFor(path, flavor: config.config.flavor, surface: surface, theme: theme)}',
      surface: surface.name,
      theme: theme.name,
      configPath: config.config.path,
      configKind: config.config.kind.name,
      flavor: config.config.flavor,
      enabled: resolution.enabled,
      placement: picture.composition.summary,
      generated: picture.isGenerated,
      predictedBecause: picture.reason,
      fallsBackToLight: resolution.fallsBackToLight,
      properties: [
        for (var (name, resolved) in [
          ('color', resolution.color),
          ('backgroundImage', resolution.backgroundImage),
          ('image', resolution.image),
          ('branding', resolution.branding),
          ('iconBackgroundColor', resolution.iconBackgroundColor),
        ])
          if (resolved.isPresent)
            SplashProperty(
              name: name,
              value: resolved.value!,
              from: resolved.key,
            ),
      ],
      problems: [
        for (var problem in config.problemsFor(surface, theme))
          _problemEntry(problem),
      ],
    );
  }

  Future<SplashReloadResult> _reload(String path) async {
    await _load(path);
    var before = _fingerprints[path];

    invalidate(path);
    await _load(path);

    return SplashReloadResult(
      package: path,
      configPath: _scans[path]?.main?.config.path,
      scannedAt: (_scannedAt[path] ?? DateTime.now()).toIso8601String(),
      changed: before != _fingerprints[path],
    );
  }

  SplashArtifactsResult _artifacts(String path) {
    var scan = _scans[path]!;
    var config = scan.main;
    var artifacts = config?.artifacts ?? const <SplashArtifact>[];
    var packageRoot = host.workspace.packageFor(path).absolutePath;

    return SplashArtifactsResult(
      package: path,
      generated: artifacts.isNotEmpty,
      stale: config?.stale ?? false,
      artifacts: [
        for (var artifact in artifacts) _artifactEntry(artifact, packageRoot),
      ],
    );
  }

  /// Runs the real generator.
  ///
  /// Spawned rather than linked, deliberately: the project pins its own version
  /// of `flutter_native_splash`, and a version this GUI happened to be built
  /// against would produce output the project's own CI would not.
  Future<SplashGenerateResult> _generate(
    String path,
    Map<String, Object?> arguments,
  ) async {
    var config = _configArgument(path, arguments);
    var root = host.workspace.packageFor(path).absolutePath;
    var dart = p.join(host.workspace.flutterSdk.root, 'bin', 'dart');

    var result = await Process.run(dart, [
      'run',
      'flutter_native_splash:create',
      if (config.config.flavor != null) '--flavor=${config.config.flavor}',
    ], workingDirectory: root);

    // The scan is now wrong about what is on disk in every case — a failed run
    // still writes some of the files before it exits.
    invalidate(path);
    await _load(path);

    var refreshed = _scans[path]?.forFlavor(config.config.flavor);
    var packageRoot = root;

    return SplashGenerateResult(
      package: path,
      flavor: config.config.flavor,
      ok: result.exitCode == 0,
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}'.trim(),
      artifacts: [
        for (var artifact in refreshed?.artifacts ?? const <SplashArtifact>[])
          _artifactEntry(artifact, packageRoot),
      ],
    );
  }

  /// One generated file, for the wire.
  ///
  /// The single place that mapping happens. It was written out twice — once in
  /// `artifacts` and once in `generate` — which is two lists that agree only
  /// until somebody adds a field to one of them.
  SplashArtifactEntry _artifactEntry(
    SplashArtifact artifact,
    String packageRoot,
  ) => SplashArtifactEntry(
    // Worktree-relative rather than package-relative: an agent's tools are
    // scoped to the repo, not to one package inside it.
    path: p.relative(
      p.join(packageRoot, artifact.path),
      from: host.worktree.path,
    ),
    surface: artifact.surface.name,
    theme: artifact.theme.name,
    role: artifact.role.name,
    density: artifact.density,
    pixelWidth: artifact.pixelWidth,
    pixelHeight: artifact.pixelHeight,
    logicalWidth: artifact.logicalWidth,
    modified: artifact.modified.toIso8601String(),
  );

  static SplashProblemEntry _problemEntry(SplashProblem problem) =>
      SplashProblemEntry(
        tone: problem.tone.name,
        message: problem.message,
        key: problem.key,
        surface: problem.surface?.name,
        theme: problem.theme?.name,
        device: problem.device,
        blocksGeneration: problem.blocksGeneration,
      );
}

PluginCore splashCoreFactory(PluginHost host) => SplashCore(host);
