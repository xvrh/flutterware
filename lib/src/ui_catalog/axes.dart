import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'axis.dart';
import 'knob.dart';

/// The guest's side of the top bar: the switches a shell's signature declares,
/// and the two extensions the host reads and writes them through.
///
/// Deliberately the mirror image of [CatalogParameters]. A knob exists because
/// a demo's build asked for it, so only the guest can say what there is. An
/// axis exists because a *signature* declares it, so the host already knows the
/// set from discovery and what it reads back here is the part a signature
/// cannot carry — what the options are called.
///
/// The selection is the host's. It has to outlive the entry you are looking at
/// and the guest itself, so it is pushed down rather than owned here; what is
/// held below is a cache of the last push, which survives a hot reload because
/// this object does.
class CatalogAxes {
  CatalogAxes._();

  static final instance = CatalogAxes._();

  /// Bumped when a selection changes, so the shell has something to rebuild on.
  final revision = ValueNotifier<int>(0);

  /// What the current shell declared, in the order the generated call makes
  /// them — which is the order they were written in the signature.
  final _declared = <String, KnobDescriptor>{};

  /// Axis name to the chosen option's name, or a bool for a flag.
  ///
  /// Not cleared when the shell changes. The host is authoritative and pushes
  /// the right set before a switch lands, and [pick] falls back for anything it
  /// does not recognise — so a leftover selection is harmless, where dropping
  /// one the host had already sent would not be.
  final _selected = <String, Object?>{};

  String? _shellId;

  /// Starts a shell's declarations. Emitted by the generated host immediately
  /// before the [pick] and [flag] calls for that shell's axes.
  void beginShell(String? shellId) {
    _shellId = shellId;
    _declared.clear();
  }

  /// The value chosen for an enum axis, or [fallback].
  ///
  /// [values] is the enum's own `values`, handed in by the generated call —
  /// which is how the guest can report what there is to choose from when a
  /// syntactic scan of the signature saw only a type name.
  T pick<T extends Enum>(String name, List<T> values, T fallback) {
    var chosen = _selected[name];
    var value = fallback;
    if (chosen is String) {
      for (var candidate in values) {
        if (candidate.name == chosen) {
          value = candidate;
          break;
        }
      }
    }
    _declared[name] = KnobDescriptor(
      name: name,
      kind: KnobKind.picker,
      options: [for (var candidate in values) candidate.name],
      value: value.name,
      defaultValue: fallback.name,
    );
    return value;
  }

  /// The value chosen for a `bool` axis, or [fallback].
  ///
  /// Separate from [pick] because `bool` is not an `Enum` and has no `values`,
  /// but it is still a closed set — which is the only thing an axis needs to be.
  bool flag(String name, bool fallback) {
    var chosen = _selected[name];
    var value = chosen is bool ? chosen : fallback;
    _declared[name] = KnobDescriptor(
      name: name,
      kind: KnobKind.boolean,
      value: value,
      defaultValue: fallback,
    );
    return value;
  }

  /// What the current shell offers, and what each is currently set to.
  AxisReport describe() =>
      AxisReport(shellId: _shellId, axes: _declared.values.toList());

  /// Records selections and asks for a rebuild.
  ///
  /// A null value puts an axis back to the default its signature declares,
  /// which is the same thing a null means to a knob — and is how a top bar
  /// offers "reset" without having to know what the default was.
  ///
  /// Values are taken for axes this build has not declared as well: the host
  /// pushes a shell's selections *before* the reload that switches to it, so at
  /// the moment they arrive the shell they belong to has not built yet.
  void apply(Map<String, Object?> selections) {
    if (selections.isEmpty) return;
    for (var MapEntry(key: name, value: selection) in selections.entries) {
      if (selection == null) {
        _selected.remove(name);
      } else {
        _selected[name] = selection;
      }
    }
    revision.value++;
  }

  /// Registers the extensions. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.axes', (_, _) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(describe().toJson()),
      );
    });
    developer.registerExtension('ext.flutterware.setAxes', (_, args) async {
      // A service extension's arguments are strings, so the payload is JSON in
      // one of them rather than a map of typed values.
      var payload = jsonDecode(args['payload'] ?? '{}') as Map<String, dynamic>;
      apply(payload);
      // Answered only once the shell has rebuilt on it, so a host that asks
      // what there is to show right afterwards is told about the build it
      // caused rather than the one it replaced. Bounded because a panel waits
      // on this: a guest that has stopped drawing should make it late, not
      // stuck.
      if (payload.isNotEmpty) {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode(describe().toJson()),
      );
    });
  }
}

/// Scopes one shell's axes and rebuilds it when a selection changes.
///
/// [builder] is where the generated host calls the shell, so the
/// [CatalogAxes.pick] and [CatalogAxes.flag] calls that declare the axes run
/// inside it — after [CatalogAxes.beginShell], which is what makes the report
/// exactly this shell's axes and not the previous one's.
class CatalogAxesScope extends StatelessWidget {
  const CatalogAxesScope({
    super.key,
    required this.shellId,
    required this.builder,
  });

  /// The shell whose axes are declared below, or null for an entry whose
  /// wrapper is not a shell — which has none.
  final String? shellId;

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CatalogAxes.instance.revision,
      builder: (context, _, _) {
        CatalogAxes.instance.beginShell(shellId);
        return builder(context);
      },
    );
  }
}
