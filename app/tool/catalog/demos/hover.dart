import 'package:flutter/material.dart';

import 'package:flutterware/ui_catalog.dart';

import 'shell.dart';

/// Says out loud whether the guest is receiving hover, because nothing else
/// does. Hover has no lasting effect a probe can read — an ink highlight is a
/// colour, not a widget — so a demo that turns it into text is the only way the
/// headless check can tell forwarding from silence.
@Demo(name: 'Hover', wrapper: wrapInApp)
Widget hoverProbe() => const _HoverProbe();

class _HoverProbe extends StatefulWidget {
  const _HoverProbe();

  @override
  State<_HoverProbe> createState() => _HoverProbeState();
}

class _HoverProbeState extends State<_HoverProbe> {
  var _inside = false;
  Offset? _at;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _inside = true),
      onHover: (e) => setState(() => _at = e.localPosition),
      onExit: (_) => setState(() {
        _inside = false;
        _at = null;
      }),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Text(_inside ? 'POINTER IN' : 'POINTER OUT'),
            if (_at case var at?)
              Text('at ${at.dx.round()},${at.dy.round()}')
            else
              const Text('no hover yet'),
          ],
        ),
      ),
    );
  }
}
