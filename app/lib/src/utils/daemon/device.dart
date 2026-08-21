/// One device, as the flutter daemon's `device` domain describes it.
///
/// Hand-decoded rather than generated because this is a *wire* type read from
/// a tool we do not version: every field is optional on the way in, and a
/// daemon that adds one, renames one or sends null for one must not make a
/// connected phone disappear from the list. Only [id] is required — without it
/// there is nothing to name the device by.
///
/// The same shape round-trips through the `devices.json` cache, so a cold `fw`
/// reading the cache and a GUI holding a live daemon are looking at one type.
class DaemonDevice {
  const DaemonDevice({
    required this.id,
    this.name,
    this.platform,
    this.emulator = false,
    this.category,
    this.platformType,
    this.ephemeral = true,
    this.emulatorId,
    this.sdk,
    this.isConnected = true,
    this.connectionInterface,
    this.capabilities = const {},
  });

  /// The device id `flutter run -d` takes.
  final String id;

  final String? name;

  /// `ios`, `android-arm64`, `darwin`, `web-javascript`…
  final String? platform;

  final bool emulator;

  /// `mobile`, `desktop`, `web`.
  final String? category;

  /// `ios`, `android`, `macos`, `web`… — the platform without the
  /// architecture, which is what a human recognises.
  final String? platformType;

  /// False for a device that is always there (a desktop, the browser).
  final bool ephemeral;

  final String? emulatorId;

  /// `iOS 18.5`, `Android 12 (API 31)`.
  final String? sdk;

  /// A wireless device can be *known* and not currently reachable. The daemon
  /// keeps reporting it, so the difference has to be carried rather than
  /// inferred from presence in the list.
  final bool isConnected;

  /// `attached` — cabled or built in — or `wireless`.
  ///
  /// Worth carrying rather than dropping: the launch spike measured a hot
  /// reload at 289ms over a cable and 1571ms over wifi on the same phone, and
  /// wireless launches are the ones that stall on an OS permission dialog.
  final String? connectionInterface;

  /// `hotReload`, `hotRestart`, `screenshot`, `flutterExit`, `startPaused`…
  final Map<String, bool> capabilities;

  bool get isWireless => connectionInterface == 'wireless';

  /// Which of the three kinds this is.
  ///
  /// The list treated these as one thing and the difference is exactly what a
  /// row has to say — most visibly, that a *host* cannot be taken from you, so
  /// calling this Mac `free` or `busy` as though somebody else might have it is
  /// simply false.
  ///
  /// Read off `ephemeral` and `emulator`, which are the daemon's own words for
  /// it: measured, `macos` and `chrome` are both `ephemeral=false`, a cabled
  /// iPhone is `ephemeral=true emulator=false`, and a simulator is
  /// `ephemeral=true emulator=true`.
  MachineKind get kind => !ephemeral
      ? MachineKind.host
      : emulator
      ? MachineKind.virtual
      : MachineKind.physical;

  /// What to call it when the daemon sent no name.
  String get displayName => name ?? id;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (platform != null) 'platform': platform,
    'emulator': emulator,
    if (category != null) 'category': category,
    if (platformType != null) 'platformType': platformType,
    'ephemeral': ephemeral,
    if (emulatorId != null) 'emulatorId': emulatorId,
    if (sdk != null) 'sdk': sdk,
    'isConnected': isConnected,
    if (connectionInterface != null) 'connectionInterface': connectionInterface,
    if (capabilities.isNotEmpty) 'capabilities': capabilities,
  };

  /// Null when there is no usable `id`, which is the only field nothing can
  /// stand in for.
  static DaemonDevice? tryRead(Map<String, Object?> json) {
    var id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return DaemonDevice(
      id: id,
      name: json['name'] as String?,
      platform: json['platform'] as String?,
      emulator: json['emulator'] == true,
      category: json['category'] as String?,
      platformType: json['platformType'] as String?,
      // Absent means ephemeral: every phone is, and a daemon that stopped
      // sending the field should not turn them all into desktops.
      ephemeral: json['ephemeral'] != false,
      emulatorId: json['emulatorId'] as String?,
      sdk: json['sdk'] as String?,
      isConnected: json['isConnected'] != false,
      connectionInterface: json['connectionInterface'] as String?,
      capabilities: {
        for (var entry in (json['capabilities'] as Map? ?? const {}).entries)
          if (entry.value is bool) '${entry.key}': entry.value as bool,
      },
    );
  }

  @override
  String toString() => 'DaemonDevice($id, $name)';
}

/// The three kinds of machine, which differ in every way a row cares about.
///
/// Named `MachineKind` and not `DeviceKind` because the package publishes that
/// name for something else entirely — `lib/src/devices.dart`'s form-factor
/// vocabulary, phone/tablet/desktop, which is about the silhouette to draw
/// around a screenshot. This one is about who can take the thing away from you.
///
/// | kind | comes and goes | contended | can be started |
/// |---|---|---|---|
/// | [physical] | unplugged, asleep, roaming | yes, across worktrees *and* repos | no |
/// | [virtual] | you start and stop it | yes, once booted | yes |
/// | [host] | always there | no — a run owns a window, not a slot | n/a |
enum MachineKind {
  /// A phone or tablet on the end of a cable or a wifi link.
  physical,

  /// An emulator or a simulator: absent until booted, contended once it is.
  virtual,

  /// This machine, or a browser on it. Cannot be taken, and stopping the run
  /// closes the window — so the wording is about the run rather than the
  /// slot.
  host,
}

/// One emulator or simulator the daemon could boot, as `emulator.getEmulators`
/// describes it.
///
/// Hand-decoded and fully tolerant, for the same reason [DaemonDevice] is: this
/// is a wire type from a tool we do not version, and a field that changed name
/// must not make a bootable emulator vanish from the list.
class DaemonEmulator {
  const DaemonEmulator({
    required this.id,
    this.name,
    this.category,
    this.platformType,
  });

  /// What `emulator.launch` takes.
  final String id;

  final String? name;

  /// `mobile`, `desktop`, `web`.
  final String? category;

  /// `ios` or `android` — which of the two very different things this is.
  final String? platformType;

  String get displayName => name ?? id;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (category != null) 'category': category,
    if (platformType != null) 'platformType': platformType,
  };

  /// Null without a usable `id`, the only field nothing can stand in for.
  static DaemonEmulator? tryRead(Map<String, Object?> json) {
    var id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return DaemonEmulator(
      id: id,
      name: json['name'] as String?,
      category: json['category'] as String?,
      platformType: json['platformType'] as String?,
    );
  }

  @override
  String toString() => 'DaemonEmulator($id, $name)';
}
