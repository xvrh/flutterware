import '../embedder/guest_vm_service.dart';

/// The framework's own debug switches, named for a command line.
///
/// These are **not** axes, though they sit beside them on an address and
/// change the pixels the same way. An axis is declared by a `PreviewShell` and
/// pushed to it; these are `ext.flutter.*` extensions on the guest *process*,
/// registered by the framework whether a demo asks for anything or not. Same
/// address, different push — which is why they are their own thing rather than
/// another entry in `setAxes`.
///
/// Deliberately a curated set. The framework registers about thirty
/// extensions and most of them are a profiler's, a debugger's, or a way to
/// make the engine exit; these are the ones that change what a *picture* of an
/// entry looks like.
class DebugFlag {
  const DebugFlag({
    required this.name,
    required this.extension,
    required this.kind,
    required this.description,
    this.options = const [],
  });

  /// What a caller types — `paint`, not `debugPaint`.
  final String name;

  /// The service extension behind it.
  final String extension;

  final DebugFlagKind kind;

  /// For [DebugFlagKind.choice], the values the framework accepts.
  final List<String> options;

  final String description;

  /// The argument key the extension reads its value from.
  ///
  /// Three conventions, all the framework's: a boolean extension reads
  /// `enabled`, a string one reads `value`, and a numeric one reads a key
  /// named after itself.
  String get argument => switch (kind) {
    DebugFlagKind.boolean => 'enabled',
    DebugFlagKind.choice => 'value',
    DebugFlagKind.number => extension.split('.').last,
  };
}

enum DebugFlagKind { boolean, choice, number }

/// Every flag a caller may set, in the order they are worth trying.
const debugFlags = <DebugFlag>[
  DebugFlag(
    name: 'paint',
    extension: 'ext.flutter.debugPaint',
    kind: DebugFlagKind.boolean,
    description:
        'Draw the layout guides — box edges, padding, alignment arrows. The '
        'single most useful one for a screenshot of something that is the '
        'wrong size.',
  ),
  DebugFlag(
    name: 'baselines',
    extension: 'ext.flutter.debugPaintBaselinesEnabled',
    kind: DebugFlagKind.boolean,
    description: 'Draw text baselines, for type that sits wrong against type',
  ),
  DebugFlag(
    name: 'repaintRainbow',
    extension: 'ext.flutter.repaintRainbow',
    kind: DebugFlagKind.boolean,
    description:
        'Tint each layer as it repaints. Worth little in one frame and a lot '
        'across several.',
  ),
  DebugFlag(
    name: 'banner',
    extension: 'ext.flutter.debugAllowBanner',
    kind: DebugFlagKind.boolean,
    description:
        'The DEBUG ribbon a MaterialApp draws. Allowed by default, so '
        '`banner=false` is how a screenshot loses it — unless the app already '
        'passed `debugShowCheckedModeBanner: false`, in which case there was '
        'never one to lose.',
  ),
  DebugFlag(
    name: 'brightness',
    extension: 'ext.flutter.brightnessOverride',
    kind: DebugFlagKind.choice,
    options: ['light', 'dark'],
    description:
        'The platform brightness the demo sees — it moves '
        '`MediaQuery.platformBrightness`. Whether that changes the picture is '
        'the app\u2019s business: a `MaterialApp` given `darkTheme` and '
        '`themeMode: system` follows it, one given only `theme` renders the '
        'same either way. Not a substitute for a shell axis that switches '
        'themes outright.',
  ),
  DebugFlag(
    name: 'platform',
    extension: 'ext.flutter.platformOverride',
    kind: DebugFlagKind.choice,
    options: ['android', 'iOS', 'fuchsia', 'linux', 'macOS', 'windows'],
    description:
        'What `defaultTargetPlatform` reports — so a widget that switches '
        'between Material and Cupertino switches here',
  ),
  DebugFlag(
    name: 'timeDilation',
    extension: 'ext.flutter.timeDilation',
    kind: DebugFlagKind.number,
    description:
        'Slow animations by this factor. `5` makes a transition sit still '
        'long enough to be photographed.',
  ),
];

/// Sets [values] on the guest, and leaves everything unnamed alone.
///
/// **Not whole-state, unlike knobs and axes**, and the difference is not an
/// inconsistency. A knob belongs to the entry and an axis to the shell, so
/// "everything not named goes back to its default" is meaningful for both. A
/// debug flag belongs to the *process*: the panel's own guest may have had
/// `paint` turned on by somebody looking at it, and a screenshot request that
/// silently reset it would be reaching past its own business.
///
/// Values arrive as text from every direction and are checked against what the
/// framework accepts, so a name it does not know is an error listing the ones
/// it does rather than a flag that quietly did nothing.
Future<void> applyDebugFlags(
  GuestVmService service,
  Map<String, String> values,
) async {
  for (var entry in values.entries) {
    var flag = debugFlagNamed(entry.key);
    if (flag == null) {
      throw ArgumentError.value(
        entry.key,
        'debug',
        'no such debug flag. Known: '
            '${debugFlags.map((f) => f.name).join(', ')}',
      );
    }
    var wanted = coerceDebugFlag(flag, entry.value);
    var response = await service.requireExtension(
      flag.extension,
      args: {flag.argument: wanted},
    );
    // The framework answers with the value it now holds, so a flag that did
    // not take is worth knowing about here rather than in a picture that looks
    // wrong for a reason nobody can see. Compared loosely: a numeric extension
    // answers `5.0` to `5`.
    var got = '${response?[flag.argument]}';
    if (got != wanted && double.tryParse(got) != double.tryParse(wanted)) {
      throw StateError(
        'the guest would not set ${flag.name}: asked for $wanted, it reports '
        '$got',
      );
    }
  }
}

DebugFlag? debugFlagNamed(String name) {
  for (var flag in debugFlags) {
    if (flag.name == name) return flag;
  }
  return null;
}

/// The text a flag's extension expects, from the text a caller wrote.
String coerceDebugFlag(DebugFlag flag, String value) {
  switch (flag.kind) {
    case DebugFlagKind.boolean:
      if (value == 'true' || value == 'false') return value;
      throw ArgumentError.value(value, flag.name, 'expected true or false');
    case DebugFlagKind.choice:
      // Case-insensitively, because `ios` is what anyone types and `iOS` is
      // what the framework answers to.
      for (var option in flag.options) {
        if (option.toLowerCase() == value.toLowerCase()) return option;
      }
      throw ArgumentError.value(
        value,
        flag.name,
        'no such option. Accepted: ${flag.options.join(', ')}',
      );
    case DebugFlagKind.number:
      if (double.tryParse(value) == null) {
        throw ArgumentError.value(value, flag.name, 'expected a number');
      }
      return value;
  }
}
