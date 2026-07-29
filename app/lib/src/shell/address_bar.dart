import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutterware/plugins.dart';

import '../address/address_scope.dart';
import '../ui/design/design.dart';
import 'shell_controller.dart';

/// Height of the strip. Deliberately smaller than the band: this is a readout,
/// and the tabs above it are the thing you aim at.
const addressBarHeight = 24.0;

/// The current address along the bottom of the window.
///
/// It is the instrument before it is a feature. Everything that writes the
/// address — a search hit, a click in a catalog tree, eventually a knob — is
/// invisible until something displays the result, and "did that write land?" is
/// not a question worth answering by reading code. Clicking it goes the other
/// way: paste an address and the app has to become it, which is the only honest
/// test that the address really is the state rather than a caption on it.
///
/// Along the bottom rather than in the band because the band is worth more.
/// Tabs are aimed at; this is glanced at, and a full-width strip also means the
/// address rarely needs shortening at all.
class AddressBar extends StatefulWidget {
  const AddressBar(this.shell, {super.key});

  final ShellController shell;

  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  final _menu = MenuController();
  final _field = TextEditingController();
  final _focus = FocusNode();

  /// What the field held when it was last seeded, so an address that moves
  /// underneath an *untouched* field can refresh it without overwriting
  /// something half-typed.
  var _seeded = '';

  /// Why the last submission went nowhere, or null.
  String? _problem;

  var _hovered = false;

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open(Address address) {
    _seed(address);
    _menu.open();
    // Once the menu has an overlay to focus into.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _field.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _field.text.length,
      );
    });
  }

  void _seed(Address address) {
    _seeded = address.toString();
    _field.text = _seeded;
    _problem = null;
  }

  void _submit() {
    var parsed = Address.tryParse(_field.text.trim());
    if (parsed == null) {
      setState(() => _problem = 'Not a flutterware address.');
      return;
    }

    var result = widget.shell.go(parsed);
    setState(() {
      _problem = switch (result) {
        GoResult.ok || GoResult.unchanged => null,
        GoResult.worktreeUnknown =>
          parsed.worktree == null
              ? 'That address names no worktree.'
              : 'No worktree named "${parsed.worktree}" in this repo.',
      };
    });
    if (_problem == null) _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    // The one place reading the whole address is the right thing to do: it is
    // what this widget displays.
    var address = AddressScope.of(context).full;

    // The field follows the app while it is open and untouched, so watching the
    // address move as you click around does not mean closing it first.
    if (_menu.isOpen &&
        _field.text == _seeded &&
        address.toString() != _seeded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen && _field.text == _seeded) {
          setState(() => _seed(address));
        }
      });
    }

    var colors = context.colors;
    return Container(
      height: addressBarHeight,
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: MenuAnchor(
        controller: _menu,
        alignmentOffset: const Offset(0, -4),
        style: MenuStyle(
          alignment: Alignment.topLeft,
          backgroundColor: WidgetStatePropertyAll(colors.bg),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.radii.radius),
              side: BorderSide(color: colors.line),
            ),
          ),
        ),
        menuChildren: [_Editor(this, address)],
        builder: (context, controller, child) => MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () =>
                controller.isOpen ? controller.close() : _open(address),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FwSpacing.md),
              child: _Readout(
                address: address,
                lit: _hovered || controller.isOpen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The address as parts rather than as a string.
///
/// Only the middle collapses. The worktree says which checkout you are in and
/// the last segment says what you are looking at; the path between them is
/// usually the same one it was a minute ago, so that is what gives way when the
/// window is narrow. A single `Text` with an ellipsis would drop the tail,
/// which is the one part worth keeping.
class _Readout extends StatelessWidget {
  const _Readout({required this.address, required this.lit});

  final Address address;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var mono = context.type.micro.copyWith(
      fontFamily: 'monospace',
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );

    Widget part(String text, Color color) =>
        Text(text, style: mono.copyWith(color: color), softWrap: false);
    Widget separator() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: part('/', colors.mut3),
    );

    // `fw://` then the empty project then the leading slash — drawn as one
    // piece because there is nothing to click or read in the middle of it.
    var head = <Widget>[
      part('fw://${address.project ?? ''}/', lit ? colors.mut2 : colors.mut3),
    ];
    if (address.worktree case var worktree?) {
      head.add(part(worktree, lit ? colors.ink2 : colors.mut));
    }
    if (address.plugin case var plugin?) {
      head
        ..add(separator())
        ..add(part(plugin, lit ? colors.ink2 : colors.mut));
    }

    // Everything but the last segment gives way; the last never does.
    var middle = address.segments.length > 1
        ? address.segments.sublist(0, address.segments.length - 1).join('/')
        : null;
    var last = address.segments.lastOrNull;

    return Row(
      children: [
        ...head,
        if (middle != null) ...[
          separator(),
          Flexible(
            child: Text(
              middle,
              style: mono.copyWith(color: colors.mut3),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (last != null) ...[
          separator(),
          part(last, lit ? context.colors.accent : colors.ink2),
        ],
        for (var axis in address.axes.entries) ...[
          const Gap(FwSpacing.sm),
          _AxisChip(axis.key, axis.value),
        ],
        const Spacer(),
        if (lit) part('click to edit', colors.mut3),
      ],
    );
  }
}

/// One applied axis. A chip rather than `?theme=dark` run together, because
/// what a demo is set to is worth reading at a glance and this is where knobs
/// will land next.
class _AxisChip extends StatelessWidget {
  const _AxisChip(this.name, this.value);

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${name.split('.').last} $value',
        style: context.type.micro.copyWith(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: colors.mut,
        ),
      ),
    );
  }
}

/// The expanded form: the whole address, editable, and what went wrong.
class _Editor extends StatelessWidget {
  const _Editor(this.state, this.address);

  final _AddressBarState state;
  final Address address;

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    return SizedBox(
      width: 560,
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: state._field,
                    focusNode: state._focus,
                    onSubmitted: (_) => state._submit(),
                    style: context.type.bodySmall.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colors.panel,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: FwSpacing.md,
                        vertical: FwSpacing.md,
                      ),
                      border: _border(context, colors.line),
                      enabledBorder: _border(context, colors.line),
                      focusedBorder: _border(context, colors.accent),
                    ),
                  ),
                ),
                const Gap(FwSpacing.sm),
                IconButton(
                  tooltip: 'Copy',
                  icon: Icon(Icons.copy_rounded, size: 14, color: colors.mut),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: address.toString()),
                  ),
                ),
              ],
            ),
            const Gap(FwSpacing.sm),
            Text(
              state._problem ?? 'Press ↵ to go there.',
              style: context.type.caption.copyWith(
                color: state._problem == null ? colors.mut3 : colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(BuildContext context, Color color) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(context.radii.radius),
        borderSide: BorderSide(color: color),
      );
}
