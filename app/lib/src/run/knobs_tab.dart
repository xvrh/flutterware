import 'package:flutter/material.dart';

import '../plugins/native/run_results.dart';
import '../ui/design/spacing.dart';
import '../ui/design/tokens.dart';
import 'handle.dart';
import 'knob_field.dart';

/// The knobs of the run being shown, editable, with **Restart to apply**.
///
/// **This is what makes the measurement reachable.** The launch form lives on
/// the New run page, and the only route back to it is Stop — which is a
/// relaunch, which is the rebuild this design exists to remove. Editing here
/// costs a wrapper rewrite and a hot restart: 262ms on desktop, 3.07s on an
/// Android emulator.
///
/// Two things it deliberately does not do:
///
/// - **It does not restart on its own.** Losing the cart because somebody typed
///   in a field is a surprise a cockpit should not spring, so the button is the
///   consent.
/// - **It does not apply live.** A value reaches the app only through `main`,
///   so showing a new one while the process holds the old would look correct
///   and be wrong. Until the restart lands, the edit is *pending* and says so.
class KnobsTab extends StatefulWidget {
  const KnobsTab({
    super.key,
    required this.handle,
    required this.knobs,
    this.unknown,
    required this.onApply,
    this.interfaceOf,
  });

  final RunHandle handle;

  /// What this entry point's `main` takes, read off the signature.
  final List<RunKnobEntry> knobs;

  /// Why the knobs cannot be known, when they cannot — another checkout's run,
  /// a package this worktree does not declare, an entry point that has since
  /// moved. Distinct from an empty list, which is the claim that this entry
  /// point takes none.
  final String? unknown;

  /// Rewrites the wrapper and restarts. Errors surface here rather than as a
  /// snackbar somewhere else.
  final Future<void> Function(Map<String, String> values) onApply;

  /// Passed to [KnobField] — which interface an offered address belongs to.
  final String? Function(String)? interfaceOf;

  @override
  State<KnobsTab> createState() => _KnobsTabState();
}

class _KnobsTabState extends State<KnobsTab> {
  /// The edits not yet applied, over what the run is actually holding.
  late Map<String, String> _edited = {...widget.handle.knobs};

  var _applying = false;
  String? _error;

  Map<String, String> get _running => widget.handle.knobs;

  bool get _dirty =>
      _edited.length != _running.length ||
      _edited.entries.any((e) => _running[e.key] != e.value);

  @override
  void didUpdateWidget(KnobsTab old) {
    super.didUpdateWidget(old);
    // A restart landed, or somebody else moved this run: adopt what is running
    // rather than keeping edits that have already happened.
    if (widget.handle.knobs.toString() != old.handle.knobs.toString()) {
      _edited = {...widget.handle.knobs};
    }
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.onApply(_edited);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.unknown case var reason?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xl),
          child: Text(
            reason,
            textAlign: TextAlign.center,
            style: context.type.caption,
          ),
        ),
      );
    }
    if (widget.knobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FwSpacing.xl),
          child: Text(
            // Said rather than left blank, because "no knobs" and "we did not
            // look" are different answers and only one of them is true here.
            '${widget.handle.entrypointLabel} takes no knobs.\n\n'
            'Give its main() optional named parameters — '
            "void main({String apiHost = 'localhost'}) — and they appear "
            'here, changeable with a hot restart instead of a rebuild.',
            textAlign: TextAlign.center,
            style: context.type.caption,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(FwSpacing.lg),
      children: [
        for (var knob in widget.knobs) ...[
          KnobField(
            knob: knob,
            value: _edited[knob.name],
            interfaceOf: widget.interfaceOf,
            onChanged: (value) => setState(() {
              if (value == null) {
                _edited.remove(knob.name);
              } else {
                _edited[knob.name] = value;
              }
            }),
          ),
          const Gap(FwSpacing.md),
        ],
        const Gap(FwSpacing.sm),
        Row(
          children: [
            FilledButton(
              onPressed: _dirty && !_applying ? _apply : null,
              child: Text(_applying ? 'Restarting…' : 'Restart to apply'),
            ),
            const Gap(FwSpacing.md),
            if (_dirty)
              Flexible(
                child: Text(
                  // The cost, before the click rather than after it.
                  'A restart re-runs main, so the app starts from its first '
                  'screen.',
                  style: context.type.caption.copyWith(
                    color: context.colors.mut3,
                  ),
                ),
              ),
          ],
        ),
        if (_error case var error?) ...[
          const Gap(FwSpacing.md),
          Text(
            error,
            style: context.type.caption.copyWith(color: context.colors.red),
          ),
        ],
      ],
    );
  }
}
