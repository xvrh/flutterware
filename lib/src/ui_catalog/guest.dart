import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

import 'axes.dart';
import 'knob.dart';
import 'parameters.dart';
import 'ui_catalog.dart';

/// The catalog's side of a guest: the knobs a demo declares while it builds,
/// and the two service extensions a panel reads and writes them through.
///
/// The panel runs in another process and the guest has no platform channels —
/// there is nothing on the other end of one, the host is a few hundred lines
/// of C. What it does have is a VM service, already connected because that is
/// how a reload is pushed in. So the knobs travel as service extensions, which
/// is the one bidirectional channel a plain embedder guest has.
///
/// Values do **not** travel as a reload. Setting one rebuilds the demo in
/// place, which is the difference between turning a knob and recompiling: the
/// demo keeps its state, and the answer is on screen in a frame rather than in
/// a hundred milliseconds.
class CatalogParameters {
  CatalogParameters._();

  static final instance = CatalogParameters._();

  /// Bumped when a *value* changes, so the widget providing these to the demo
  /// has something to rebuild on.
  final revision = ValueNotifier<int>(0);

  /// Bumped when a knob is *declared*, which happens while the demo builds —
  /// so this one must never mark anything dirty. Nothing on screen depends on
  /// it either: the demo already has the default it just asked for. It exists
  /// so a panel can tell that the set it is showing is out of date.
  int get declared => _declared;
  var _declared = 0;

  late final EditableParameters editable = EditableParameters(
    onRefresh: _bump,
    onAdded: () => _declared++,
  );

  /// What the entry that declared the current knobs was, so switching entries
  /// starts from nothing rather than from the last demo's controls.
  String? _entryId;

  void _bump() => revision.value++;

  /// Opens a declaration pass and closes it once the frame has been built.
  ///
  /// The frame is the right boundary because everything that reads a knob is a
  /// dependent of the provider [CatalogGuest] puts up, so one build of that
  /// widget rebuilds every reader there is. Whatever has not asked for a knob
  /// by the end of it is not asking any more — the demo was edited, or it took
  /// a different path through its own build.
  void _beginPass() {
    editable.beginPass();
    if (_sweeping) return;
    _sweeping = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sweeping = false;
      // Retiring changes the set as much as declaring does, so a panel holding
      // the old one has the same reason to ask again.
      if (editable.endPass() > 0) _declared++;
    });
  }

  var _sweeping = false;

  /// Forgets everything the previous entry declared.
  ///
  /// Knobs are discovered by *running* the demo, so the set is only ever as
  /// right as the last build. Carrying one entry's controls into the next
  /// would leave a panel offering knobs nothing reads.
  void resetFor(String entryId) {
    if (_entryId == entryId) return;
    _entryId = entryId;
    editable.dispose();
    editable.parameters.clear();
    _declared++;
    // No bump: this runs from the widget's own init or update, and the demo
    // below is about to build anyway.
  }

  /// Registers the extensions. Call once, before `runApp`.
  void registerExtensions() {
    developer.registerExtension('ext.flutterware.parameters', (_, _) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode(describe().toJson()),
      );
    });
    developer.registerExtension('ext.flutterware.setParameter', (
      _,
      args,
    ) async {
      // A service extension's arguments are strings, so the payload is JSON in
      // one of them rather than a map of typed values.
      var payload = jsonDecode(args['payload'] ?? '{}') as Map<String, dynamic>;
      var applied = apply(
        payload['name'] as String,
        payload.containsKey('value') ? payload['value'] : null,
      );
      // Answered only once the demo has rebuilt on it. Turning a knob can
      // reveal or retire another, so a reply that came back before the frame
      // would leave the panel asking what to show and being told about the
      // build it had just replaced — intermittently, depending on whether the
      // frame beat the next request, which is worse than being wrong.
      //
      // Bounded because this is an RPC a panel waits on: a guest that has
      // stopped drawing should make the panel late, not stuck.
      if (applied) {
        await WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'applied': applied}),
      );
    });
  }

  /// Every knob the last build declared, in declaration order.
  KnobReport describe() => KnobReport(
    entryId: _entryId,
    declared: _declared,
    revision: revision.value,
    knobs: [
      for (var entry in editable.parameters.entries)
        ?_describe(entry.key, entry.value),
    ],
  );

  static KnobDescriptor? _describe(String name, Parameter<Object?> p) =>
      switch (p) {
        StringParameter() => KnobDescriptor(
          name: name,
          kind: KnobKind.string,
          value: p.requiredValue,
          defaultValue: p.defaultValue,
        ),
        BoolParameter() => KnobDescriptor(
          name: name,
          kind: KnobKind.boolean,
          value: p.requiredValue,
          defaultValue: p.defaultValue,
        ),
        NumParameter() => KnobDescriptor(
          name: name,
          kind: p.isInt ? KnobKind.integer : KnobKind.number,
          value: p.requiredValue,
          defaultValue: p.defaultValue,
          min: p.min,
          max: p.max,
        ),
        PickerParameter() => KnobDescriptor(
          name: name,
          kind: KnobKind.picker,
          options: p.options.keys.toList(),
          value: _labelOf(p, p.requiredValue),
          defaultValue: _labelOf(p, p.defaultValue),
        ),
        // Dates and buttons are left out rather than described wrong.
        _ => null,
      };

  static String? _labelOf(PickerParameter<Object?> p, Object? value) {
    for (var entry in p.options.entries) {
      if (entry.value == value) return entry.key;
    }
    return null;
  }

  /// Sets [name] to [value], or back to its default when [value] is null.
  ///
  /// Returns false for a knob the current build did not declare, which is what
  /// a panel showing a stale set looks like from in here.
  bool apply(String name, Object? value) {
    var parameter = editable.parameters[name];
    switch (parameter) {
      case StringParameter():
        parameter.value = value as String?;
      case BoolParameter():
        parameter.value = value as bool?;
      case NumParameter<int>():
        parameter.value = (value as num?)?.round();
      case NumParameter():
        parameter.value = (value as num?)?.toDouble();
      case PickerParameter():
        parameter.value = value == null ? null : parameter.options[value];
      case _:
        return false;
    }
    return true;
  }
}

/// Provides the catalog's state to the entry below it, and rebuilds it when a
/// knob moves.
///
/// The [UICatalogState] a demo reads through `context.uiCatalog` is otherwise
/// the empty one, which answers every call with the default — which is exactly
/// what should happen when the same widget is built inside the real app.
class CatalogGuest extends StatefulWidget {
  const CatalogGuest({super.key, required this.entryId, required this.child});

  final String entryId;
  final Widget child;

  @override
  State<CatalogGuest> createState() => _CatalogGuestState();
}

class _CatalogGuestState extends State<CatalogGuest> {
  CatalogParameters get _parameters => CatalogParameters.instance;

  /// The axes are reset from here as well as the knobs, and it has to be from
  /// here: the shell is *below* this widget, so an entry whose wrapper is not a
  /// shell declares nothing at all, and without this the previous shell's axes
  /// would stay on the bar with no build ever coming to replace them.
  void _reset() {
    _parameters.resetFor(widget.entryId);
    CatalogAxes.instance.resetFor(widget.entryId);
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(CatalogGuest old) {
    super.didUpdateWidget(old);
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _parameters.revision,
      builder: (context, revision, _) {
        // Everything below is about to re-declare what it reads, which is the
        // only chance there is to notice a knob nobody reads any more.
        _parameters._beginPass();
        return UICatalogStateProvider(
          // A new state per revision on purpose: the provider notifies its
          // dependents by identity, and the demo *is* a dependent — reading a
          // knob is what subscribed it.
          state: _GuestCatalogState(_parameters.editable, revision),
          child: widget.child,
        );
      },
    );
  }
}

class _GuestCatalogState implements UICatalogState {
  _GuestCatalogState(this.parameters, this.revision);

  @override
  final Parameters parameters;

  final int revision;
}
