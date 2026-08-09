import 'dart:async';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:path/path.dart' as p;

import '../../splash/model/fingerprint.dart';
import '../../splash/model/generated.dart';
import '../../splash/model/config.dart';
import '../../splash/model/scan.dart';
import '../../splash/model/studio.dart';
import '../../splash/model/studio_render.dart';
import '../../splash/model/surface.dart';
import '../../splash/model/validation.dart';
import '../../splash/model/writer.dart';
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
                  // The remedy on the same row as the complaint. Without it a
                  // reader has to know `fix` exists and then go and ask it what
                  // it can do — two steps to discover a button that is already
                  // sitting there.
                  detail: problem.fix == null
                      ? problem.message
                      : '${problem.message} '
                            '[fix: ${problem.fix!.id} — ${problem.fix!.label}]',
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

  /// Every fix any scanned config has to offer, deduplicated.
  ///
  /// Empty until something has loaded, which is the honest answer: the fixes are
  /// derived from a real config, and inventing a fixed list of them would offer
  /// repairs for problems this project does not have.
  List<SplashFix> get _offeredFixes {
    var byId = <String, SplashFix>{};
    for (var scan in _scans.values) {
      for (var config in scan.configs) {
        for (var fix in config.fixes) {
          byId.putIfAbsent(fix.id, () => fix);
        }
      }
    }
    return byId.values.toList();
  }

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
      'fix',
      'Fix',
      returns: SplashFixResult,
      confirm: true,
      description:
          'Applies one repair to the config file — one or two keys, spliced in '
          'so comments and key order survive. The ids come from the "fix" '
          'field on a problem, which `describe` returns.',
      parameters: [
        ActionParameter(
          'fix',
          'Fix',
          kind: ActionParameterKind.choice,
          description: 'Which repair, from a problem\'s "fix" field',
          // Spelled out rather than pointed at the report, because the set is
          // small and because a caller that can see the labels can choose
          // without a second call.
          options: [
            for (var fix in _offeredFixes)
              ActionOption(fix.id, label: fix.label),
          ],
        ),
        _packageParameter,
        _flavorParameter,
      ],
    ),
    PluginAction(
      'set',
      'Set a key',
      returns: SplashSetResult,
      confirm: true,
      description:
          'Writes one config key, spliced into the file so comments and key '
          'order survive. The key must be one the generator accepts — writing '
          'an unknown one is exactly what stops `create` from running.',
      parameters: [
        const ActionParameter(
          'key',
          'Key',
          description:
              'Dotted for the section — `color_dark`, '
              '`android_12.image`',
        ),
        const ActionParameter(
          'value',
          'Value',
          required: false,
          description: 'Omit to remove the key',
        ),
        _packageParameter,
        _flavorParameter,
      ],
    ),
    PluginAction(
      'prepare',
      'Prepare an image',
      returns: SplashPrepareResult,
      confirm: true,
      description:
          'Turns a source image into the file one target actually wants — the '
          'right canvas, the right scale, the config key pointed at it. The '
          'numbers are the value here: an Android 12 icon is 1152 square with '
          'only the inner 768 circle showing, and a splash image is drawn at a '
          'quarter of its pixel size. Neither is anywhere the person exporting '
          'the PNG would see it.',
      parameters: [
        const ActionParameter(
          'source',
          'Source image',
          description:
              'Package-relative or absolute. A file outside the package is '
              'copied in beside the output.',
        ),
        ActionParameter(
          'target',
          'Target',
          kind: ActionParameterKind.choice,
          defaultValue: SplashStudioTarget.android12Icon.name,
          required: false,
          options: [
            for (var target in SplashStudioTarget.values)
              ActionOption(target.name, label: target.label),
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
        const ActionParameter(
          'width',
          'On-screen width',
          kind: ActionParameterKind.integer,
          required: false,
          description:
              'For the splash image only, in logical pixels — the question the '
              'config has no field for, because the answer is baked into the '
              'pixel size of the file. Defaults to '
              '${splashDefaultImageWidthDp ~/ 1}.',
        ),
        const ActionParameter(
          'scale',
          'Scale',
          required: false,
          description:
              'Multiplier on the source, if the default fit is not what you '
              'want. A second pass after seeing a corner overhang is what this '
              'is for.',
        ),
        const ActionParameter(
          'offsetX',
          'Offset X',
          required: false,
          description: 'Canvas pixels right of centre',
        ),
        const ActionParameter(
          'offsetY',
          'Offset Y',
          required: false,
          description: 'Canvas pixels below centre',
        ),
        _packageParameter,
        _flavorParameter,
      ],
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
      'fix' => await _fix(path, arguments),
      'set' => await _set(path, arguments),
      'prepare' => await _prepare(path, arguments),
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
    var composition = config.compositionFor(surface, theme);

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
      placement: composition.summary,
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

  /// Applies one repair and re-reads.
  ///
  /// The write itself is [SplashWriter]'s; what this adds is the two things that
  /// make it safe to offer as a button. The fix is looked up **in the config it
  /// will be written to**, so an id from another flavor cannot be applied to
  /// this one; and the scan is invalidated afterwards, because a panel still
  /// showing the problem it just fixed is worse than no button at all.
  Future<SplashFixResult> _fix(
    String path,
    Map<String, Object?> arguments,
  ) async {
    var config = _configArgument(path, arguments);
    var id = '${arguments['fix'] ?? ''}';
    var fix = config.fixFor(id);
    if (fix == null) {
      var offered = config.fixes.map((f) => f.id).toList();
      throw ArgumentError.value(
        id,
        'fix',
        offered.isEmpty
            ? 'nothing in "${config.config.path}" has a fix on offer'
            : 'not a fix for "${config.config.path}"; try one of '
                  '${offered.join(', ')}',
      );
    }

    var root = host.workspace.packageFor(path).absolutePath;
    await SplashWriter(
      packageRoot: root,
      config: config.config,
    ).apply(fix.writes);

    invalidate(path);
    await _load(path);
    var refreshed = _scans[path]?.forFlavor(config.config.flavor);

    return SplashFixResult(
      package: path,
      flavor: config.config.flavor,
      fix: fix.id,
      label: fix.label,
      configPath: config.config.path,
      writes: [
        for (var write in fix.writes)
          SplashWriteEntry(key: write.key, value: write.value),
      ],
      remainingProblems: refreshed?.problems.length ?? 0,
    );
  }

  /// Writes one key.
  ///
  /// The key is checked against the generator's own vocabulary **before** the
  /// write rather than reported as a problem after it. An unknown key does not
  /// merely look wrong: `create` prints it and exits, so a typo here would take
  /// a working project and stop it building, and the plugin would have done it.
  Future<SplashSetResult> _set(
    String path,
    Map<String, Object?> arguments,
  ) async {
    var config = _configArgument(path, arguments);
    var key = '${arguments['key'] ?? ''}'.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'no key given');
    }
    var known = key.startsWith('android_12.')
        ? splashAndroid12Keys.contains(key.substring('android_12.'.length))
        : splashKnownKeys.contains(key);
    if (!known) {
      throw ArgumentError.value(
        key,
        'key',
        'not a flutter_native_splash parameter; `create` would exit rather '
            'than write anything',
      );
    }

    var raw = arguments['value'];
    var value = raw == null || '$raw'.isEmpty ? null : raw;

    var root = host.workspace.packageFor(path).absolutePath;
    await SplashWriter(
      packageRoot: root,
      config: config.config,
    ).apply([SplashWrite(key, value)]);

    invalidate(path);
    await _load(path);
    var refreshed = _scans[path]?.forFlavor(config.config.flavor);

    return SplashSetResult(
      package: path,
      flavor: config.config.flavor,
      key: key,
      value: value,
      configPath: config.config.path,
      remainingProblems: refreshed?.problems.length ?? 0,
    );
  }

  /// Where the studio's output goes.
  ///
  /// Three steps, in this order, because the first two are the project's own
  /// answer and the third is ours:
  ///
  /// 1. **Beside the file the key already points at.** A project that has an
  ///    asset convention has already told us what it is; putting a second splash
  ///    image somewhere else would be inventing a second convention next to it.
  /// 2. `output` on the plugin's declaration in `tool/flutterware.dart`, for a
  ///    project that wants to say so explicitly.
  /// 3. `assets/splash/`, which is a guess and is the only guess here.
  String outputDirectoryFor(String packagePath, {String? existing}) {
    if (existing != null && existing.contains('/')) {
      return p.dirname(existing);
    }
    var declared = host.config['output'];
    if (declared is String && declared.trim().isNotEmpty) {
      return declared.trim();
    }
    return p.join('assets', 'splash');
  }

  /// Makes one image and points its key at it.
  Future<SplashPrepareResult> _prepare(
    String path,
    Map<String, Object?> arguments,
  ) async {
    var configScan = _configArgument(path, arguments);
    var config = configScan.config;
    var root = host.workspace.packageFor(path).absolutePath;

    var target =
        SplashStudioTarget.byName('${arguments['target'] ?? ''}') ??
        SplashStudioTarget.android12Icon;
    var theme =
        SplashTheme.byName('${arguments['theme'] ?? ''}') ?? SplashTheme.light;
    var key = target.keyFor(theme);

    var given = '${arguments['source'] ?? ''}'.trim();
    if (given.isEmpty) {
      throw ArgumentError.value(given, 'source', 'no source image given');
    }
    var sourceFile = File(p.isAbsolute(given) ? given : p.join(root, given));
    if (!sourceFile.existsSync()) {
      throw ArgumentError.value(given, 'source', 'no such file');
    }
    var sourceBytes = await sourceFile.readAsBytes();
    var facts = measureSplashSource(sourceBytes);
    if (facts == null) {
      throw ArgumentError.value(given, 'source', 'could not be decoded');
    }

    // The icon canvas is 960 with an icon background and 1152 without, so the
    // config decides the answer and the caller must not have to.
    var canvas = splashStudioCanvas(
      target: target,
      sourceWidth: facts.width,
      sourceHeight: facts.height,
      hasIconBackground: config.android12IconBackgroundColor(theme).isPresent,
      logicalWidth: _number(arguments['width']),
    );

    var fit = splashFitCrop(
      canvas: canvas,
      sourceWidth: facts.width,
      sourceHeight: facts.height,
    );
    var crop = SplashCrop(
      scale: _number(arguments['scale']) ?? fit.scale,
      offsetX: _number(arguments['offsetX']) ?? 0,
      offsetY: _number(arguments['offsetY']) ?? 0,
    );

    var directory = outputDirectoryFor(
      path,
      existing: _conventionFor(configScan, key),
    );
    Directory(p.join(root, directory)).createSync(recursive: true);

    var output = p.join(directory, _outputName(target, theme, config.flavor));
    var png = await renderSplashPngInIsolate(
      sourceBytes: sourceBytes,
      canvas: canvas,
      crop: crop,
    );
    await File(p.join(root, output)).writeAsBytes(png);

    // Copied only when it came from outside. A source already in the project is
    // findable; a second copy of it is clutter, and the plan's "keep the source
    // beside the derived files" is about the drag-and-drop case, where the
    // original is on somebody's desktop and gone by next week.
    String? copied;
    if (!p.isWithin(root, sourceFile.path)) {
      copied = p.join(directory, p.basename(sourceFile.path));
      await sourceFile.copy(p.join(root, copied));
    }

    await SplashWriter(
      packageRoot: root,
      config: config,
    ).apply([SplashWrite(key, output)]);

    invalidate(path);
    await _load(path);
    var refreshed = _scans[path]?.forFlavor(config.flavor);

    return SplashPrepareResult(
      package: path,
      flavor: config.flavor,
      target: target.name,
      theme: theme.name,
      key: key,
      output: output,
      width: canvas.width,
      height: canvas.height,
      explanation: canvas.explanation,
      sourceCopiedTo: copied,
      cornerOverhang: splashCornerOverhang(
        canvas: canvas,
        crop: crop,
        sourceWidth: facts.width,
        sourceHeight: facts.height,
      ),
      remainingProblems: refreshed?.problems.length ?? 0,
    );
  }

  /// The path this project already puts splash assets at, if it has one.
  ///
  /// The exact key first — re-running the studio should overwrite where it wrote
  /// last time. Failing that, **any** image the config already points at, since
  /// a project with an `assets/branding/logo.png` has told us where its splash
  /// art lives even though this particular key is empty.
  ///
  /// The launcher icon is excluded by name. The scan keeps it alongside the
  /// referenced images so `composeSplash` can reach it through one lookup, and
  /// it lives under `android/app/src/main/res/mipmap-…` — following it would put
  /// generated splash assets inside the Android resource tree.
  static String? _conventionFor(SplashConfigScan scan, String key) {
    var exact = key.startsWith('android_12.')
        ? scan.config.android12Section[key.substring('android_12.'.length)]
        : scan.config.raw[key];
    var value = SplashConfig.stringify(exact);
    if (value != null) return value;

    for (var path in scan.images.keys) {
      if (path == scan.launcherIcon?.path) continue;
      if (path.contains('/')) return path;
    }
    return null;
  }

  /// A stable name per target, theme and flavor.
  ///
  /// Stable so re-running the studio overwrites what it made last time rather
  /// than growing `logo-2.png` beside it — the config key points at one file and
  /// the previous one would be orphaned.
  static String _outputName(
    SplashStudioTarget target,
    SplashTheme theme,
    String? flavor,
  ) {
    var base = switch (target) {
      SplashStudioTarget.android12Icon => 'android12_icon',
      SplashStudioTarget.android12Branding => 'android12_branding',
      SplashStudioTarget.image => 'splash',
      SplashStudioTarget.backgroundImage => 'background',
    };
    var name = [base, ?flavor, if (theme == SplashTheme.dark) 'dark'].join('_');
    return '$name.png';
  }

  static double? _number(Object? value) => switch (value) {
    num v => v.toDouble(),
    String v when v.trim().isNotEmpty => double.tryParse(v.trim()),
    _ => null,
  };

  /// Drops the cached scan and reads again, whatever the fingerprint says.
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
        fix: problem.fix?.id,
        fixLabel: problem.fix?.label,
        blocksGeneration: problem.blocksGeneration,
      );
}

PluginCore splashCoreFactory(PluginHost host) => SplashCore(host);
