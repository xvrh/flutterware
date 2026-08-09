import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../plugins/native/splash_core.dart';
import '../../ui/theme.dart';
import '../model/color.dart';
import '../model/edit_target.dart';
import '../model/surface.dart';
import '../model/validation.dart';

/// Editing the value the caption is pointing at.
///
/// The tile already says `#101418 · from color_dark`. This turns that line into
/// something you can act on without leaving the picture — which is the whole
/// argument for editing in the plugin at all. Nobody needs a form over fifty
/// YAML keys; what they need is to change the one value they are looking at and
/// see the eight tiles redraw.
///
/// Goes through `set` rather than around it, for the same reason the fix button
/// does: the action checks the key against the generator's own vocabulary,
/// splices the write, and rescans. A dialog that wrote the file itself would be
/// a second implementation of all three.
Future<void> showSplashValueDialog(
  BuildContext context, {
  required SplashCore core,
  required String package,
  required String? flavor,
  required SplashSurface surface,
  required String label,
  required String key,
  required String value,
  required bool isColor,
}) => showDialog<void>(
  context: context,
  builder: (context) => _EditValueDialog(
    core: core,
    package: package,
    flavor: flavor,
    surface: surface,
    label: label,
    fromKey: key,
    initial: value,
    isColor: isColor,
  ),
);

class _EditValueDialog extends StatefulWidget {
  const _EditValueDialog({
    required this.core,
    required this.package,
    required this.flavor,
    required this.surface,
    required this.label,
    required this.fromKey,
    required this.initial,
    required this.isColor,
  });

  final SplashCore core;
  final String package;
  final String? flavor;
  final SplashSurface surface;

  /// 'background', 'image' — what the caption called it.
  final String label;

  /// The key that won the cascade, which is also the default target.
  final String fromKey;

  final String initial;
  final bool isColor;

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final _value = TextEditingController(text: widget.initial);
  late String _target = widget.fromKey;
  late final List<SplashEditTarget> _targets = splashEditTargets(
    key: widget.fromKey,
    surface: widget.surface,
  );

  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _value
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  String get _text => _value.text.trim();

  /// The colour the field currently spells, or null when it spells none. Also
  /// the validity test — the generator wants six hex digits and throws on
  /// anything else, so a field that does not parse here is a config that would
  /// not build.
  int? get _parsed => widget.isColor ? parseSplashColor(_text) : null;

  bool get _valid => _text.isNotEmpty && (!widget.isColor || _parsed != null);

  Future<void> _browse() async {
    var root = widget.core.packageRootFor(widget.package);
    var picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'images',
          extensions: splashConvertibleFormats.toList(),
        ),
      ],
      initialDirectory: root,
    );
    if (picked == null || !mounted) return;

    // The config is read relative to the package, so a file outside it would
    // have to be written as `../..`. That resolves, but it is a path that breaks
    // the moment the package moves — and refusing is more useful than writing
    // one and letting `create` be the thing that complains.
    if (!p.isWithin(root, picked.path)) {
      setState(() {
        _error =
            'That file is outside the package. Copy it under '
            '${p.basename(root)}/ first — the config path is read relative to '
            'the package root.';
      });
      return;
    }
    setState(() {
      _error = null;
      _value.text = p.relative(picked.path, from: root);
    });
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.core.invoke(
        'set',
        arguments: {
          'package': widget.package,
          'key': _target,
          // Normalised on the way in: the generator accepts `#FFFFFF` but
          // stores nothing, so what lands in the file is the spelling the rest
          // of the config uses.
          'value': widget.isColor ? _normalisedColor : _text,
          if (widget.flavor != null) 'flavor': widget.flavor,
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  String get _normalisedColor =>
      _text.replaceAll('#', '').replaceAll(' ', '').toUpperCase();

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var type = context.type;

    return AlertDialog(
      title: Text('Set the ${widget.label}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.isColor) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _parsed == null ? null : Color(_parsed!),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.line),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: _value,
                    autofocus: widget.isColor,
                    enabled: !_saving,
                    readOnly: !widget.isColor,
                    style: type.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: widget.isColor ? 'Colour' : 'Path',
                      hintText: widget.isColor
                          ? '1E1E1E'
                          : 'assets/splash/logo.png',
                      border: const OutlineInputBorder(),
                      errorText:
                          widget.isColor && _text.isNotEmpty && _parsed == null
                          ? 'Six hex digits — the generator throws on '
                                'anything else'
                          : null,
                    ),
                    onSubmitted: (_) => unawaited(_save()),
                  ),
                ),
                if (!widget.isColor) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _saving ? null : () => unawaited(_browse()),
                    child: const Text('Choose…'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Write it to',
              style: type.caption.copyWith(color: colors.mut),
            ),
            const SizedBox(height: 4),
            // The key that won is first and selected. Changing a value you can
            // see should change it where it lives; narrowing it to one platform
            // is a decision, and decisions get a second row rather than a
            // silent default.
            for (var target in _targets)
              RadioListTile<String>(
                value: target.key,
                // ignore: deprecated_member_use
                groupValue: _target,
                // ignore: deprecated_member_use
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _target = value!),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(target.key, style: type.bodySmall),
                subtitle: Text(
                  target.label,
                  style: type.micro.copyWith(color: colors.mut2),
                ),
              ),
            if (_error case var error?) ...[
              const SizedBox(height: 12),
              SelectableText(
                error,
                style: type.bodySmall.copyWith(color: colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid && !_saving ? () => unawaited(_save()) : null,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
