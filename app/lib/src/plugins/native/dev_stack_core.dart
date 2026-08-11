import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterware/plugins.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../utils/run_dir.dart';
import '../plugin_core.dart';
import '../plugin_host.dart';
import 'dev_stack_results.dart';

/// The registered id — also what `tool/flutterware.dart` declares.
const devStackPluginId = 'flutterware.dev_stack';

/// How much of a command's output to keep. Enough to see why something failed,
/// far short of a log viewer — the command's own terminal has the rest.
const _maxOutput = 8000;

/// The dev stack: docker, the database, whatever the app talks to locally.
///
/// See `docs/superpowers/specs/2026-08-10-dev-stack-design.md`.
///
/// **It owns no process.** Everything here runs one of the project's own
/// commands and reads what came back — [DevStack.probe] to find out the state,
/// `start` / `stop` to change it. That is the whole difference from a
/// supervisor, and it is what makes a stack brought up in a terminal
/// indistinguishable from one brought up by the button: there is nothing to be
/// the authority *about*.
///
/// Holds to the [PluginCore.computeAll] budget by reading a cache file and
/// nothing else. Probing is a subprocess, so it happens only when something is
/// watching ([watch]) or when a caller named the action.
class DevStackCore extends PluginCore {
  DevStackCore(super.host) {
    var config = host.config;
    _probe = config['probe'] is Map
        ? Probe.fromJson((config['probe']! as Map).cast<String, Object?>())
        : null;
    _start = _commandFrom(config['start']);
    _stop = _commandFrom(config['stop']);
    _relativeDirectory = config['workingDirectory'] as String?;
    _stopIsDestructive = config['stopIsDestructive'] == true;
    var poll = config['poll'];
    _poll = Duration(milliseconds: poll is int && poll > 0 ? poll : 10000);
    _commands = [
      for (var entry in (config['commands'] as List? ?? const []))
        if (entry is Map) ?StackCommand.fromJson(entry.cast<String, Object?>()),
    ];
  }

  /// Where the cache lives. A seam for tests, which point it at a temp dir
  /// rather than the developer's real run dir.
  @visibleForTesting
  static String Function() runDirProvider = flutterwareRunDir;

  /// Runs a command and hands back (exitCode, combined output).
  ///
  /// **Per instance, not static, and not test-only.** A static seam is one
  /// global that every core in the process shares — fine for a test that builds
  /// one at a time, wrong for anything that does not: the catalog draws five
  /// stacks on one screen, each scripted differently, and they would overwrite
  /// each other. The catalog is why this is not `@visibleForTesting`: a plugin
  /// whose whole subject is a docker project cannot be looked at in a repo that
  /// has none, so a preview scripts this and draws the shipping panel over it.
  Future<ProcessResult> Function(
    List<String> command, {
    String? workingDirectory,
  })
  runProcess = defaultRunProcess;

  Probe? _probe;
  List<String>? _start;
  List<String>? _stop;
  String? _relativeDirectory;
  late final bool _stopIsDestructive;
  late final Duration _poll;
  late final List<StackCommand> _commands;

  StackReading _reading = const StackReading.unknown();
  var _loadedCache = false;
  var _watchers = 0;
  Timer? _timer;

  /// What is in flight, or null. Set while `start` / `stop` runs, which is what
  /// makes [StackState.starting] a state rather than a spinner: the probe
  /// cannot see a compose project that has not finished coming up, and asking
  /// it during a transition would report `down` at the exact moment the user is
  /// watching for `up`.
  String? _busy;

  /// When [_busy] was set.
  ///
  /// Here rather than in the widget because a transition outlives any one
  /// surface: navigating to the panel eight seconds into a bring-up must show
  /// eight seconds, not start counting again. The elapsed number is the only
  /// progress a delegated command can honestly report — nothing here knows what
  /// the project's script is doing, only how long it has been doing it.
  DateTime? _busySince;

  /// True while [refresh] has a probe out.
  ///
  /// Separate from [_busy], which is only for transitions the *user* started.
  /// This exists for the window capture: a panel photographed between mounting
  /// and its first probe returning shows "not checked yet" and is reported as a
  /// success, which is the mid-resolve screenshot `SettleSource` was written
  /// about.
  var _probing = false;

  /// The tail of the last command's output, for the panel.
  String _lastOutput = '';
  String? _lastCommand;

  /// The last reading, cache or probe.
  StackReading get reading => _reading;

  /// The declared commands, in declaration order.
  List<StackCommand> get commands => _commands;

  bool get canControl => _start != null || _stop != null;
  bool get stopIsDestructive => _stopIsDestructive;
  bool get canStart => _start != null;
  bool get canStop => _stop != null;
  String? get busy => _busy;

  /// How long the transition in flight has been running, or null.
  Duration? get busyFor =>
      _busySince == null ? null : DateTime.now().difference(_busySince!);

  /// True while a probe is out. Read by the block, which draws a reading it has
  /// not confirmed differently from one it has.
  bool get isProbing => _probing;

  /// True when the reading on hand is old enough that it should be presented as
  /// history rather than as the state.
  ///
  /// Two poll intervals, which a mounted surface can never reach — it polls
  /// every interval. So in practice this is the **cold open**: a cache written
  /// hours ago, read before the first probe of this session comes back. That
  /// case used to render as "not checked yet", which throws away a fact we are
  /// holding; it should say what we last saw and how long ago.
  bool get isStale {
    var at = _reading.at;
    if (at == null || !_reading.isKnown) return false;
    return DateTime.now().difference(at) > _poll * 2;
  }

  /// What this is still working on, or null. Read by the capture settler.
  String? get busyWith => switch ((_busy, _probing)) {
    (var busy?, _) =>
      busy == 'start' ? 'bringing the stack up' : 'tearing the stack down',
    (_, true) => 'checking the stack',
    _ => null,
  };
  String get lastOutput => _lastOutput;
  String? get lastCommand => _lastCommand;
  Duration get pollInterval => _poll;

  /// The probe as declared, joined — what the panel names when it explains
  /// where the state on screen came from.
  String? get declaredProbeCommand => _probe?.command.join(' ');

  /// The `workingDirectory:` as declared, or null when commands run at the
  /// worktree root. Shown rather than the absolute path where the point is
  /// *whose* CLI is in charge rather than where it lives.
  String? get declaredDirectory => _relativeDirectory;

  /// Absolute, and the one place the declared relative path is resolved.
  String get workingDirectory => _relativeDirectory == null
      ? host.worktree.path
      : p.join(host.worktree.path, _relativeDirectory);

  @override
  Future<void> computeAll() async => _loadCache();

  /// Starts polling, and stops when the last watcher leaves.
  ///
  /// **Reference-counted, unlike the other cores' `track()`.** Those start work
  /// that runs until the worktree closes, which is right for a file watch that
  /// costs nothing to leave running. This spawns a subprocess every
  /// [pollInterval], so leaving it on for a worktree nobody is looking at would
  /// be a `docker compose ps` every ten seconds, forever, per open tab. Two
  /// surfaces watch — the panel and the worktree home — and either may be
  /// mounted without the other, which is what the count is for.
  void watch() {
    _watchers++;
    if (_watchers > 1 || isDisposed) return;
    _loadCache();
    unawaited(refresh());
    _timer = Timer.periodic(_poll, (_) => unawaited(refresh()));
  }

  /// The inverse of [watch]. Idempotent past zero, because a widget disposing
  /// twice must not turn polling off for the surface still showing.
  void unwatch() {
    if (_watchers == 0) return;
    _watchers--;
    if (_watchers > 0) return;
    _timer?.cancel();
    _timer = null;
  }

  bool get isWatching => _watchers > 0;

  /// Runs the probe and adopts what it says. Does nothing while a transition is
  /// in flight — see [_busy].
  Future<StackReading> refresh() async {
    if (isDisposed || _busy != null) return _reading;
    var probe = _probe;
    if (probe == null) {
      return _adopt(
        StackReading(
          state: StackState.unavailable,
          at: DateTime.now(),
          failure:
              'No probe is declared, so nothing can say what state this '
              'stack is in.',
        ),
      );
    }
    _probing = true;
    try {
      var result = await runProcess(
        probe.command,
        workingDirectory: workingDirectory,
      );
      return _adopt(_read(probe, result));
    } on Object catch (e) {
      // A command that could not be spawned at all — a missing binary, a
      // working directory that is not there. That is the probe failing, not
      // the stack being down.
      return _adopt(
        StackReading(
          state: StackState.unavailable,
          at: DateTime.now(),
          failure: '${probe.command.first}: $e',
        ),
      );
    } finally {
      _probing = false;
    }
  }

  /// Turns one probe run into a reading.
  StackReading _read(Probe probe, ProcessResult result) {
    var at = DateTime.now();
    var out = _combined(result);
    if (probe.shape == ProbeShape.json) {
      Object? decoded;
      try {
        // **stdout alone**, which is what [Probe.json] asks the command for.
        // Almost nothing that prints structured output has stderr to itself:
        // `dart` announces `Running build hooks...` there, docker writes
        // deprecation warnings, and a shell wrapper's `set -x` writes every
        // line it runs. Folding those in makes a probe that works for a
        // fortnight and then reports `unavailable` because a tool started
        // mentioning something.
        decoded = jsonDecode('${result.stdout}'.trim());
      } on FormatException catch (e) {
        // **The command's own words, when it left any.** A health check that
        // cannot reach the docker daemon says so on stderr and exits non-zero;
        // it does not print JSON about it. Reporting the parse error there
        // buries the one sentence that explains the problem under a complaint
        // about the format — the same reason the worktree remover prints git's
        // refusal rather than paraphrasing it.
        var said = _firstLine(out);
        return StackReading(
          state: StackState.unavailable,
          at: at,
          failure:
              said ??
              'The probe printed something that is not JSON: ${e.message}',
        );
      }
      if (decoded is! Map) {
        return StackReading(
          state: StackState.unavailable,
          at: at,
          failure: 'The probe printed JSON that is not an object.',
        );
      }
      var json = decoded.cast<String, Object?>();
      var read = StackReading.fromJson(json);
      return StackReading(
        state: read.state,
        at: at,
        detail: read.detail,
        services: read.services,
        // **`detail` is the reason when a probe reports `unavailable` without
        // a `failure`.** Two fields for one sentence is a distinction a script
        // author has no reason to make: they write one line explaining what is
        // wrong and put it where they put every other line. Insisting on the
        // other key here just loses the sentence and renders "the check could
        // not be run" over a probe that said exactly what was wrong.
        failure:
            read.failure ??
            (read.state == StackState.unavailable ? read.detail : null),
      );
    }
    // Exit code: zero is up, anything else is down. It cannot tell `down` from
    // `broken` — see [Probe.exitCode] — so it never reports `unavailable`, and
    // a project that needs that distinction moves to a JSON probe.
    return StackReading(
      state: result.exitCode == 0 ? StackState.up : StackState.down,
      at: at,
      detail: _lastLine(out),
    );
  }

  StackReading _adopt(StackReading reading) {
    if (isDisposed) return reading;
    _reading = reading;
    _writeCache(reading);
    notifyChanged();
    return reading;
  }

  /// Brings the stack up, then re-probes.
  Future<DevStackRunResult> start() => _transition(_start, 'start');

  /// Takes it down, then re-probes.
  Future<DevStackRunResult> stop() => _transition(_stop, 'stop');

  /// `async` so the refusal arrives through the future rather than out of the
  /// call. A method whose type says `Future` and which throws synchronously is
  /// one a caller can only guard by wrapping the call site as well as awaiting
  /// it.
  Future<DevStackRunResult> _transition(
    List<String>? command,
    String what,
  ) async {
    if (command == null) {
      throw StateError(
        'No `$what` is declared for this stack, so flutterware can only watch '
        'it. Add one to tool/flutterware.dart, or run it yourself.',
      );
    }
    return _run(command, busy: what, thenProbe: true);
  }

  /// Runs one of the declared [commands].
  Future<DevStackRunResult> runCommand(String id, {String? argument}) {
    var command = _commands.where((c) => c.id == id).firstOrNull;
    if (command == null) {
      var declared = [for (var c in _commands) c.id];
      throw ArgumentError.value(
        id,
        'command',
        declared.isEmpty
            ? 'this stack declares no commands.'
            : 'no such command. Declared: ${declared.join(', ')}',
      );
    }
    return _run([
      ...command.command,
      if (command.argument != null && argument != null && argument.isNotEmpty)
        argument,
    ], busy: command.label);
  }

  Future<DevStackRunResult> _run(
    List<String> command, {
    required String busy,
    bool thenProbe = false,
  }) async {
    if (_busy != null) {
      throw StateError('The stack is already $_busy. Wait for it to finish.');
    }
    _busy = busy;
    _busySince = DateTime.now();
    _lastCommand = command.join(' ');
    _lastOutput = '';
    notifyChanged();
    ProcessResult result;
    try {
      result = await runProcess(command, workingDirectory: workingDirectory);
    } on Object catch (e) {
      _busy = null;
      _busySince = null;
      _lastOutput = '$e';
      notifyChanged();
      rethrow;
    }
    _lastOutput = _tail(_combined(result));
    _busy = null;
    _busySince = null;
    notifyChanged();
    // Probing *after* the flag clears, so [refresh] is not skipped by its own
    // transition guard.
    var reading = thenProbe ? await refresh() : null;
    return DevStackRunResult(
      command: _lastCommand!,
      exitCode: result.exitCode,
      output: _lastOutput,
      reading: reading,
    );
  }

  // ── cache ────────────────────────────────────────────────────────────────
  //
  // Kept so the sidebar and `fw status` say something true the moment a GUI
  // opens, without either of them spawning anything. A reading with an age is
  // the same bargain `RunCore` strikes with `devices.json`: the fact happened,
  // it gets old, it does not become wrong.
  //
  // `stack-*.json` is not swept by [sweepRunDir] — it matches none of its
  // rules — which is right for the same reason `devices.json` is spared: there
  // is one per worktree, it is tiny, and deleting it would only make a cold
  // read answer "nothing has ever looked" about a stack that had a state a
  // minute ago.

  String get _cachePath => stackCachePath(runDirProvider(), host.worktree.path);

  void _loadCache() {
    if (_loadedCache || _reading.isKnown) return;
    _loadedCache = true;
    try {
      var file = File(_cachePath);
      if (!file.existsSync()) return;
      var json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return;
      _reading = StackReading.fromJson(json.cast<String, Object?>());
      notifyChanged();
    } on Object {
      // A cache that will not parse is a cache that was never written properly.
      // Nothing here is worth reporting: the next probe replaces it.
    }
  }

  void _writeCache(StackReading reading) {
    if (!reading.isKnown) return;
    try {
      File(_cachePath).writeAsStringSync(jsonEncode(reading.toJson()));
    } on Object {
      // Best effort. A read-only home directory costs freshness on the next
      // cold start, not correctness now.
    }
  }

  // ── report ───────────────────────────────────────────────────────────────

  @override
  PluginReport get report {
    var reading = _effectiveReading;
    return PluginReport(
      id: id,
      label: label,
      status: _statusFor(reading),
      badge: _badgeFor(reading),
      actions: _actions,
      teardown: _teardown(reading),
      view: _view(reading),
    );
  }

  /// The reading as a renderer should see it: a transition in flight wins over
  /// whatever the last probe said, because during those seconds the probe is
  /// the stale one.
  StackReading get _effectiveReading => switch (_busy) {
    'start' => StackReading(state: StackState.starting, at: _reading.at),
    'stop' => StackReading(state: StackState.stopping, at: _reading.at),
    _ => _reading,
  };

  /// **A word, not a sentence.** The sidebar clamps a status to 100 logical
  /// pixels, so anything longer than about a dozen characters arrives
  /// ellipsised — and an ellipsis always eats the *end*, which is where the
  /// information was. `up · localhost:8080 · pid 493` rendered as
  /// `up · local…`: eleven characters spent restating the one word that was
  /// never in doubt. The address has a home on the panel, where there is room
  /// for it.
  ///
  /// `up 3/4` is the one exception, and earns it by being shorter than `up`
  /// plus a space and by saying the thing you would otherwise have to open the
  /// panel to learn.
  Status _statusFor(StackReading reading) => switch (reading.state) {
    // Not `checking`: a status is read by `fw` and by a cold sidebar, and
    // neither of those has started a probe. The block says `checking` because
    // the block is the surface that actually goes and looks.
    StackState.unknown => const Status.neutral('not checked'),
    StackState.down => const Status.neutral('down'),
    StackState.starting => const Status.info('bringing up'),
    StackState.up when reading.isPartial => Status.warn(
      'up ${reading.serviceCount!.$1}/${reading.serviceCount!.$2}',
    ),
    StackState.up => const Status.good('up'),
    StackState.stopping => const Status.info('tearing down'),
    StackState.unavailable => const Status.error("can't tell"),
  };

  /// **A badge only when something needs you.**
  ///
  /// A stack that is up is the normal state and gets no dot: a tab lit green
  /// every day is a tab you stop reading, which is the failure the explorer
  /// design names about `needsYou`. Down is not a badge either — a checkout you
  /// are not working in *should* have its stack down. What is left is the probe
  /// failing, which is the only one you cannot infer and cannot ignore.
  StatusBadge _badgeFor(StackReading reading) =>
      reading.state == StackState.unavailable
      ? const StatusBadge.dot(Tone.error)
      : StatusBadge.none;

  List<PluginAction> get _actions => [
    PluginAction(
      'status',
      'Check',
      returns: StackReading,
      description:
          'Runs the declared probe and reports what state the stack is in, '
          'with the time it was read. Every other surface shows a cached '
          'reading and how old it is; this is the one that goes and looks.',
    ),
    if (_start != null)
      PluginAction(
        'start',
        'Bring up',
        returns: DevStackRunResult,
        description:
            'Runs the declared start command and re-probes when it returns. '
            'Idempotent by contract — a stack that is already up should come '
            'back up as a no-op, which is what makes this safe to call when '
            'you only want to be sure.',
      ),
    if (_stop != null)
      PluginAction(
        'stop',
        'Tear down',
        returns: DevStackRunResult,
        danger: _stopIsDestructive,
        confirm: _stopIsDestructive,
        description: _stopIsDestructive
            ? 'Runs the declared stop command, which this project has marked '
                  'as destroying data — volumes go with it and the next '
                  'bring-up starts from empty.'
            : 'Runs the declared stop command and re-probes when it returns.',
      ),
    for (var command in _commands)
      PluginAction(
        command.id,
        command.label,
        returns: DevStackRunResult,
        danger: command.danger,
        confirm: command.danger,
        description:
            command.description ?? 'Runs `${command.command.join(' ')}`.',
        parameters: [
          if (command.argument case var argument?)
            ActionParameter(argument, argument, required: false),
        ],
      ),
  ];

  /// The stack's contribution to closing a worktree.
  ///
  /// Offered only when there is something to do: a stack that is already down,
  /// or one with no `stop` declared, has no step rather than a disabled one.
  /// The detail line is what makes the checkbox decidable — "4 containers"
  /// beats the bare label, and "destroys the database" is the difference
  /// between an informed tick and a regretted one.
  List<TeardownStep> _teardown(StackReading reading) {
    if (_stop == null) return const [];
    var isUp = reading.state == StackState.up || reading.state.isMoving;
    if (!isUp) return const [];
    var detail = [
      if (reading.detail case var d?)
        if (d.isNotEmpty) d,
      if (_stopIsDestructive) 'destroys the database',
    ].join(' · ');
    return [
      TeardownStep(
        'stop',
        'Tear down $label',
        detail: detail.isEmpty ? null : detail,
        checked: true,
        danger: _stopIsDestructive,
        phase: TeardownPhase.infra,
      ),
    ];
  }

  PluginView _view(StackReading reading) => PluginView([
    ViewField('State', reading.state.name),
    if (reading.detail case var detail?)
      if (detail.isNotEmpty) ViewField('Detail', detail),
    if (reading.failure case var failure?) ViewText(failure, tone: Tone.error),
    ViewField('Checked', stackAge(reading.at) ?? 'never'),
    ViewField('Working directory', workingDirectory),
    if (reading.services.isNotEmpty)
      ViewSection('Services', [
        ViewItems([
          for (var service in reading.services)
            ViewItem(
              service.name,
              detail: [
                if (service.port != null) ':${service.port}',
                if (service.state != null) service.state!.name,
              ].join(' · '),
              tone: service.state == StackState.up ? Tone.good : Tone.neutral,
            ),
        ]),
      ]),
  ]);

  @override
  Future<Object?> invoke(
    String actionId, {
    Map<String, Object?> arguments = const {},
  }) async => switch (actionId) {
    'status' => await refresh(),
    'start' => await start(),
    'stop' => await stop(),
    _ =>
      _commands.any((c) => c.id == actionId)
          ? await runCommand(
              actionId,
              argument: _argumentFor(actionId, arguments),
            )
          : await super.invoke(actionId, arguments: arguments),
  };

  String? _argumentFor(String id, Map<String, Object?> arguments) {
    var command = _commands.firstWhere((c) => c.id == id);
    var name = command.argument;
    if (name == null) return null;
    var value = arguments[name];
    return value == null ? null : '$value';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _watchers = 0;
    super.dispose();
  }
}

/// How long ago [at] was, in the shortest form that is still true.
///
/// Shared with the panel: a reading's age is part of what the reading *means*,
/// so the two surfaces must not word it differently.
String? stackAge(DateTime? at) {
  if (at == null) return null;
  var elapsed = DateTime.now().difference(at);
  if (elapsed.inSeconds < 10) return 'just now';
  if (elapsed.inMinutes < 1) return '${elapsed.inSeconds}s ago';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// The real thing, and the value [DevStackCore.runProcess] is restored to.
Future<ProcessResult> defaultRunProcess(
  List<String> command, {
  String? workingDirectory,
}) => Process.run(
  command.first,
  command.skip(1).toList(),
  workingDirectory: workingDirectory,
);

String _combined(ProcessResult result) {
  var out = '${result.stdout}'.trimRight();
  var err = '${result.stderr}'.trimRight();
  if (out.isEmpty) return err;
  if (err.isEmpty) return out;
  return '$out\n$err';
}

/// A health check writes for a terminal, so its output is full of colour codes
/// that would otherwise land verbatim in a sidebar.
final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

String? _lastLine(String text) {
  for (var line in const LineSplitter().convert(text).reversed) {
    var stripped = line.replaceAll(_ansi, '').trim();
    if (stripped.isNotEmpty) return stripped;
  }
  return null;
}

String? _firstLine(String? text) {
  if (text == null) return null;
  for (var line in const LineSplitter().convert(text)) {
    var stripped = line.replaceAll(_ansi, '').trim();
    if (stripped.isNotEmpty) return stripped;
  }
  return null;
}

String _tail(String text) {
  var stripped = text.replaceAll(_ansi, '');
  if (stripped.length <= _maxOutput) return stripped;
  return '…\n${stripped.substring(stripped.length - _maxOutput)}';
}

List<String>? _commandFrom(Object? value) {
  if (value is! List || value.isEmpty) return null;
  return [for (var arg in value) '$arg'];
}

PluginCore devStackCoreFactory(PluginHost host) => DevStackCore(host);
