/// The matrix, as something to look at: one column per profile, the same
/// screen photographed under each.
///
/// A dialog rather than a tab, and deliberate rather than live. Every cell is
/// a relaunch, so this is minutes of somebody's time — a view that ran on open
/// would spend it without being asked. The cost is on the tin above the
/// button, next to the profiles it will run.
///
/// **Calls [RunCore.permissionMatrix] directly rather than going through
/// `Session.invoke`,** for the reason `web_export_dialog.dart` gives: the
/// behaviour is the core's either way, and `Job` has no progress event to put
/// "launching, 2 of 4" in — which is the only thing there is to show for the
/// first two minutes.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../plugins/native/run_core.dart';
import '../plugins/native/run_results.dart';
import '../ui/design/design.dart';
import '../ui/theme.dart';
import 'entrypoints.dart';
import 'permission_write.dart';

/// [flavor] and [knobs] are **required and nullable rather than defaulted**:
/// every cell is a build, and a build this dialog guessed at is a build that
/// differs from the one the page's own Start button makes. A future caller
/// should have to say what it is launching rather than inherit a default that
/// silently drops a field.
Future<void> showPermissionMatrixDialog(
  BuildContext context, {
  required RunCore core,
  required String package,
  required EntrypointRef entry,
  required String device,
  required String deviceLabel,
  required String? flavor,
  required Map<String, String> knobs,
}) => showDialog<void>(
  context: context,
  // A matrix outlives a careless click outside it, and it is holding the
  // device while it runs.
  barrierDismissible: false,
  builder: (context) => _MatrixDialog(
    core: core,
    package: package,
    entry: entry,
    device: device,
    deviceLabel: deviceLabel,
    flavor: flavor,
    knobs: knobs,
  ),
);

class _MatrixDialog extends StatefulWidget {
  const _MatrixDialog({
    required this.core,
    required this.package,
    required this.entry,
    required this.device,
    required this.deviceLabel,
    required this.flavor,
    required this.knobs,
  });

  final RunCore core;
  final String package;
  final EntrypointRef entry;
  final String device;
  final String deviceLabel;

  /// The build the caller's own launch button would make. Carried rather than
  /// re-derived — see [showPermissionMatrixDialog].
  final String? flavor;
  final Map<String, String> knobs;

  @override
  State<_MatrixDialog> createState() => _MatrixDialogState();
}

class _MatrixDialogState extends State<_MatrixDialog> {
  /// All of them, in enum order. Somebody who wants two unchecks two — which
  /// is a cheaper decision than picking from an empty list, and the honest
  /// default for a control whose label is "compare profiles".
  final _chosen = {...PermissionProfile.values};

  final _route = TextEditingController();

  final _log = <String>[];
  var _running = false;
  RunPermissionMatrixResult? _result;
  String? _error;

  @override
  void dispose() {
    _route.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    var profiles = [
      for (var profile in PermissionProfile.values)
        if (_chosen.contains(profile)) profile,
    ];
    if (profiles.isEmpty) return;
    setState(() {
      _running = true;
      _result = null;
      _error = null;
      _log.clear();
    });
    try {
      var result = await widget.core.permissionMatrix(
        device: widget.device,
        package: widget.package,
        entry: widget.entry,
        profiles: profiles,
        route: _route.text.trim().isEmpty ? null : _route.text.trim(),
        flavor: widget.flavor,
        knobs: widget.knobs,
        onProgress: _append,
      );
      if (mounted) setState(() => _result = result);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// The flavor and knobs every cell is launched with, or null when there are
  /// none to mention.
  String? get _build {
    var parts = [
      if (widget.flavor case var flavor?) '--flavor $flavor',
      for (var knob in widget.knobs.entries) '${knob.key}=${knob.value}',
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() {
      _log.add(line);
      if (_log.length > 200) _log.removeRange(0, _log.length - 200);
    });
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var result = _result;
    // Wide, because the grid is the point — but never wider than the window,
    // which on a laptop with the panel open is not much.
    var width = (MediaQuery.of(context).size.width - 120).clamp(480.0, 1080.0);
    return AlertDialog(
      title: const Text('Compare permission profiles'),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Runs ${widget.entry.name} on ${widget.deviceLabel} once per '
                'profile and photographs the same screen from each.',
                style: context.type.caption.copyWith(color: colors.mut),
              ),
              // What is being built, when it is not just the entry point.
              // These came off the page's own fields and every cell compiles
              // them in; a matrix that quietly built something else than the
              // Start button beside it is the bug this line makes visible.
              if (_build case var build?) ...[
                const Gap(FwSpacing.xs),
                Text(
                  build,
                  style: context.type.caption.copyWith(
                    color: colors.mut3,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const Gap(FwSpacing.xs),
              // The cost, before the button and not after it. Permission state
              // is read at process start and a revoke kills the app anyway, so
              // there is no cheaper form of this.
              Text(
                'Each profile is a full relaunch — expect '
                '${_chosen.length} × a launch, and the device to itself for '
                'the duration.',
                style: context.type.caption.copyWith(color: colors.amber),
              ),
              const Gap(FwSpacing.lg),
              Wrap(
                spacing: FwSpacing.md,
                children: [
                  for (var profile in PermissionProfile.values)
                    _ProfileCheck(
                      label: profile.label,
                      value: _chosen.contains(profile),
                      onChanged: _running
                          ? null
                          : (on) => setState(() {
                              if (on) {
                                _chosen.add(profile);
                              } else {
                                _chosen.remove(profile);
                              }
                            }),
                    ),
                ],
              ),
              const Gap(FwSpacing.md),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text('Route', style: context.type.bodySmall),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _route,
                      enabled: !_running,
                      style: context.type.bodySmall.copyWith(
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText:
                            'optional — where to drive each launch before the '
                            'picture',
                      ),
                    ),
                  ),
                ],
              ),
              if (_log.isNotEmpty && result == null) ...[
                const Gap(FwSpacing.lg),
                _Progress(lines: _log),
              ],
              if (_error case var error?) ...[
                const Gap(FwSpacing.lg),
                SelectableText(
                  error,
                  style: context.type.bodySmall.copyWith(color: colors.red),
                ),
              ],
              if (result != null) ...[
                const Gap(FwSpacing.lg),
                if (result.cells.isEmpty)
                  Text(
                    result.note ?? 'Nothing ran.',
                    style: context.type.bodySmall.copyWith(color: colors.amber),
                  )
                else
                  _Grid(result: result),
                if (result.cells.isNotEmpty && result.note != null) ...[
                  const Gap(FwSpacing.md),
                  SelectableText(
                    result.note!,
                    style: context.type.caption.copyWith(color: colors.mut),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: Text(result == null ? 'Cancel' : 'Close'),
        ),
        FilledButton(
          onPressed: _running || _chosen.isEmpty ? null : _run,
          child: Text(
            _running
                ? 'Running…'
                : result == null
                ? 'Run ${_chosen.length} launches'
                : 'Run again',
          ),
        ),
      ],
    );
  }
}

class _ProfileCheck extends StatelessWidget {
  const _ProfileCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: value,
            onChanged: onChanged == null
                ? null
                : (on) => onChanged!(on ?? false),
          ),
        ),
        const Gap(FwSpacing.xs),
        Text(label, style: context.type.bodySmall),
      ],
    ),
  );
}

/// What the run is doing, while it does it.
///
/// The last line large and the rest behind it: a matrix spends most of its
/// time inside one `flutter run`, and "Installing and launching…" repeated is
/// less useful than which cell it belongs to.
class _Progress extends StatelessWidget {
  const _Progress({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FwSpacing.md),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lines.last, style: context.type.bodySmall),
          if (lines.length > 1) ...[
            const Gap(FwSpacing.xs),
            Text(
              lines.reversed.skip(1).take(4).join('\n'),
              style: context.type.micro.copyWith(
                fontFamily: 'monospace',
                color: colors.mut3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The grid: one column per cell, sized so they all fit when they can.
///
/// A fixed column width put the fourth cell behind a horizontal scrollbar
/// nobody could see — and in a view whose whole point is four things side by
/// side, the one out of shot is the one being looked for. Columns shrink to
/// fit first; below [_minCell] they stop and the row scrolls, because a
/// screenshot narrower than that is not worth comparing either.
class _Grid extends StatelessWidget {
  const _Grid({required this.result});

  static const _minCell = 150.0;
  static const _maxCell = 260.0;

  /// Left for the dialog's own scrollbar, which is drawn over the content and
  /// otherwise sits on the last column's states.
  static const _gutter = 10.0;

  final RunPermissionMatrixResult result;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var count = result.cells.length;
      var free = constraints.maxWidth - _gutter - FwSpacing.md * (count - 1);
      var width = (free / count).clamp(_minCell, _maxCell);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var (index, cell) in result.cells.indexed) ...[
                if (index > 0) const Gap(FwSpacing.md),
                SizedBox(
                  width: width,
                  child: _Cell(cell: cell, first: index == 0),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.first});

  final RunPermissionMatrixCell cell;

  /// The one everything else is compared against. Said on the cell rather than
  /// inferred from position, because the order is the caller's and a grid read
  /// left to right is not obviously a comparison.
  final bool first;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                cell.label,
                style: context.type.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (cell.ms case var ms?)
              Text(
                '${(ms / 1000).toStringAsFixed(0)}s',
                style: context.type.micro.copyWith(color: colors.mut3),
              ),
          ],
        ),
        const Gap(FwSpacing.xs),
        _Shot(path: cell.screenshot, failed: !cell.ok),
        const Gap(FwSpacing.xs),
        if (cell.error case var error?) ...[
          Text(error, style: context.type.caption.copyWith(color: colors.red)),
          const Gap(FwSpacing.xs),
        ],
        for (var capability in cell.held.keys)
          _StateLine(
            capability: capability,
            held: cell.held[capability],
            observed: cell.observed[capability],
          ),
        if (first && cell.ok) ...[
          const Gap(FwSpacing.xs),
          Text(
            'compared against',
            style: context.type.micro.copyWith(color: colors.mut3),
          ),
        ],
        if (cell.added.isNotEmpty) ...[
          const Gap(FwSpacing.xs),
          for (var text in cell.added.take(6))
            Text(
              '+ $text',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.type.micro.copyWith(color: colors.amber),
            ),
          if (cell.added.length > 6)
            Text(
              '+ ${cell.added.length - 6} more',
              style: context.type.micro.copyWith(color: colors.mut3),
            ),
        ],
        if (cell.note case var note?) ...[
          const Gap(FwSpacing.xs),
          Text(note, style: context.type.micro.copyWith(color: colors.mut3)),
        ],
      ],
    );
  }
}

/// One capability under one profile — and the app's own answer beside it when
/// it disagrees.
///
/// The disagreement is the finding: the app believing something the OS does
/// not is a bug nothing outside the process can see. Both being `unknown` is
/// not one — see `_disagree` in the run panel for why that distinction earns
/// its own line of code.
class _StateLine extends StatelessWidget {
  const _StateLine({required this.capability, this.held, this.observed});

  final String capability;
  final String? held;
  final String? observed;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var disagrees =
        held != null &&
        observed != null &&
        held != 'unknown' &&
        observed != 'unknown' &&
        held != observed;
    var color = switch (held) {
      'granted' => colors.grn,
      'denied' => colors.amber,
      'deniedForever' => colors.red,
      'undetermined' => colors.mut2,
      _ => colors.mut3,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  capability,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.micro.copyWith(color: colors.mut2),
                ),
              ),
              Text(switch (held) {
                'deniedForever' => 'denied forever',
                'undetermined' => 'will prompt',
                var other => other ?? '—',
              }, style: context.type.micro.copyWith(color: color)),
            ],
          ),
          // Its own line, not a suffix. Three of these beside a state name
          // overflowed a 180px column by 4.7px — and a disagreement squeezed
          // to the edge of a cell is the one thing here that should be
          // impossible to miss.
          if (disagrees)
            Text(
              'app says $observed',
              textAlign: TextAlign.right,
              style: context.type.micro.copyWith(
                color: colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// A cell's picture, or the space where one would have been.
///
/// A failed launch keeps its slot rather than collapsing the column: the grid
/// is a comparison, and a missing column shifts everything after it.
class _Shot extends StatelessWidget {
  const _Shot({required this.path, required this.failed});

  final String? path;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var file = path == null ? null : File(path!);
    return Container(
      height: 300,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.line),
      ),
      child: file != null && file.existsSync()
          ? Image.file(file, fit: BoxFit.contain)
          : Center(
              child: Text(
                failed ? 'did not come up' : 'no picture',
                style: context.type.micro.copyWith(color: colors.mut3),
              ),
            ),
    );
  }
}
