# Scene text layers: gradients, blend, then shaders — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every pass of a text's paint stack can be painted with a linear, radial or sweep gradient — laid across the whole text or across each line — and a blend mode, all editable in the scene inspector; then a custom fragment shader as one more kind of paint.

**Architecture:** The paint VALUE lives in the pure core (`lib/src/scene/core/values.dart`) as a sealed `ScenePaint` family; a new `SceneGradient` base holds what the three gradients share. The Flutter half turns a gradient into a `ui.Shader` in one place (`lib/src/scene/gradient_shader.dart`), and the stack painter (`lib/src/scene/layered_text.dart`) decides per pass whether to paint it directly or as a mask coloured line by line. The file grammar (`app/lib/src/scene/paint_grammar.dart`) spells every value by its class name; the inspector edits a pass through a new `ScenePaintField` (kind picker + stop bar + shape fields) built from pure edit arithmetic (`app/lib/src/scene/gradient_edit.dart`).

**Tech Stack:** Dart 3 / Flutter 3.48.0-0.2.pre (pinned in `.fvmrc`), `dart:ui` gradients, the scene grammar (package `analyzer` AST), the studio design system (`app/lib/src/ui/`).

**Spec:** `docs/superpowers/specs/2026-09-05-scene-master-plan.md` §4.5 (the paint stack) and M10b, plus the **Design decisions** section below, which is this plan's own spec for what §4.5 left open.

## Global Constraints

- Every Flutter/Dart command goes through fvm: `fvm flutter …` / `fvm dart …`. Never the PATH `dart`/`flutter`.
- Format only with `fvm dart tool/prepare_submit.dart` — never bare `dart format`.
- Lints: `var` for locals (`omit_local_variable_types`), single quotes, no `final` parameters, `unawaited(...)` for fire-and-forget, raw strings where they apply. Do not add `const` beyond what the code around it already uses.
- **Nothing written here may name a client, their repository, their people or their product** — code, comments, tests, commit messages, PR text.
- `lib/src/scene/core/` stays pure Dart: no `package:flutter` import there (a test guards the import graph).
- Wire decoding is total: an unreadable payload decodes to null or the default, never throws.
- The file grammar omits every default, `emit ∘ parse` is the identity, and anything off the allowlist is refused **by name, with what to write instead** — never dropped silently.
- **A pass may change paint, never layout** (master plan §4.5). Nothing in this plan adds a metric property to a pass.
- Angles are degrees, clockwise from twelve o'clock — the unit `rotate` uses and the convention `SceneAngleDial` already draws (`atan2(dx, -dy)`).
- GUI: tokens only (`context.colors`, `context.type`, `FwSpacing`, `context.radii`, `FwIconSize`); pickers are `FwPicker`, never `DropdownButton`; every drag detector in the scene editor passes `supportedDevices: editingDevices` (`app/lib/src/scene/ui/pointer.dart`).
- Commit titles name what changed and where, one plain line, no trailing period. Every commit ends with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- One PR at the end of Phase 2, not one per task.

## Design decisions

These answer what §4.5 left open. Each is argued once here; the code comments carry the short form.

1. **A radial is stretched to the box.** `RadialPaint.radius` is in half-box units: at `1` it reaches the edge from the middle on *both* axes, so on a wide headline it is an ellipse. Flutter's `RadialGradient` measures against the shortest side, and on a 600×80 title that is a dot in the middle. Built with a local matrix on `ui.Gradient.radial`.
2. **A sweep is in degrees from twelve o'clock, and circular.** The engine takes radians from three o'clock and misbehaves on negative or wrapped angles, so the renderer hands it `[0, end − start]` and rotates the shader to `start`. Not stretched: an angle in a stretched box is not the angle that was typed.
3. **"Laid across" lives on the pass, not on the paint.** `TextLayer.box` is `SceneLayerBox.text` or `.line`. On the paint it would make `ScenePaint` text-only, and master plan §6 warns that `fill` will adopt the same paint value; a frame has no lines. On the pass it also applies unchanged to a shader later.
4. **Per line is a mask plus one band per line.** One gradient cannot restart per line, so a line-box pass paints its glyphs (stroke and blur included) in opaque black into a layer, then draws each line's gradient over it with `BlendMode.srcIn`. One layout still; the cost is one `saveLayer` per line-box pass, paid only by passes that ask. Bands run to the midpoints between lines and far past the box, so spill from a stroke or blur takes its own line's colours.
5. **A linear gradient is edited as an angle; the model keeps begin/end.** The angle field re-centres the line through the middle of the box and out to its edge (45° is corner to corner). A hand-written off-centre begin/end is shown as its angle and re-centred only when edited.
6. **The grammar is strict, the renderer tolerant.** The file refuses a gradient of fewer than two colours and stops that do not give one position per colour. The renderer, which also receives wire data, paints fewer than two colours as a solid and mismatched stops as the even spread — and computes the even spread itself, because `dart:ui` throws on a gradient with no stops unless it has exactly two colours (a live bug today: a three-colour `LinearPaint` without stops throws mid-paint).
7. **Blend is the designer's sixteen modes, on the pass,** bridged to Flutter's `BlendMode` by name (`normal` → `srcOver`).
8. **Shaders come last and get their own plan** after a spike (Phase 3) — five questions below have to be measured before they can be decided.

## File map

**Create**
- `lib/src/scene/gradient_shader.dart` — `sceneGradientShader(SceneGradient, Rect, {opacity})`: the one place a gradient becomes a `ui.Shader`.
- `app/lib/src/scene/gradient_edit.dart` — pure edit arithmetic: kind conversion, stop add/move/remove/recolour, linear angle.
- `app/lib/src/scene/ui/gradient_field.dart` — `SceneGradientField`, the stop bar.
- `app/lib/src/scene/ui/paint_field.dart` — `ScenePaintField`, one pass's paint: kind picker, colour or stops, shape fields.
- `app/tool/catalog/demos/scene_gradient_field.dart`, `app/tool/catalog/demos/scene_paint_field.dart` — previews, light and dark.
- Tests: `app/test/scene/scene_paint_test.dart` (values and wire), `app/test/scene/scene_gradient_paint_test.dart` (pixels), `app/test/scene/scene_gradient_edit_test.dart`, `app/test/scene/scene_gradient_field_test.dart`, `app/test/scene/scene_layer_list_test.dart`.

**Modify**
- `lib/src/scene/core/values.dart` — `SceneGradient`, `RadialPaint`, `SweepPaint`, `SceneLayerBox`, `SceneBlendMode`; `TextLayer.withPaint`/`copyWith`, `box`, `blend`.
- `lib/src/scene/layered_text.dart` — gradient dispatch, per-line mask path, blend.
- `lib/src/scene/flutter_bridge.dart` — `SceneBlendMode.flutter`.
- `app/lib/src/scene/paint_grammar.dart` — spelling and reading of all of the above.
- `app/lib/src/scene/ui/layer_list.dart` — the paint editor, box and blend pickers, swatch, row notes.
- `app/lib/src/scene/ui/library_view.dart`, `app/lib/src/scene/layer_presets.dart` — rescale through `copyWith`; a `Gloss` preset.
- `app/tool/catalog/demos/scene_layers.dart` — specimens for the new paints.
- `app/test/scene/scene_props_test.dart`, `app/test/scene/scene_layers_test.dart`, `app/test/scene/scene_layered_text_test.dart`, `app/test/scene_bridge_test.dart`.

## How to run things

```bash
cd app && fvm flutter test test/scene/scene_paint_test.dart
```

The scene tests live in `app/` even for the renderer in the root package. The whole scene suite is `cd app && fvm flutter test test/scene test/scene_bridge_test.dart`.

---

# Phase 1 — Gradients, end to end

### Task 1: A pass changes by copy

Three call sites rebuild a `TextLayer` by respelling its constructor (`layer_list.dart`'s `_with*` helpers, `library_view.dart`'s `_scaledLayer`, `layer_presets.dart`'s `_scaled`). Every field added to a pass in this plan would have to be threaded through all three, and a missed one silently drops the field. This task replaces them with `copyWith`/`withPaint` on the value.

**Files:**
- Modify: `lib/src/scene/core/values.dart` (classes `TextLayer`, `FillLayer`, `StrokeLayer`)
- Modify: `app/lib/src/scene/ui/layer_list.dart:305-527`
- Modify: `app/lib/src/scene/ui/library_view.dart:712-730`
- Modify: `app/lib/src/scene/layer_presets.dart:38-55`
- Create: `app/test/scene/scene_paint_test.dart`

**Interfaces:**
- Produces: `TextLayer withPaint(ScenePaint? paint)`; `TextLayer copyWith({double? blur, double? dx, double? dy, double? opacity})`; `StrokeLayer copyWith({double? blur, double? dx, double? dy, double? opacity, double? width, SceneStrokeJoin? join})`. `FillLayer`/`StrokeLayer` override both with their own return type.

- [ ] **Step 1: Write the failing test**

Create `app/test/scene/scene_paint_test.dart`:

```dart
// The paint values on their own: a pass changes by copy and keeps what it
// was not told to change, and every paint survives the wire it crosses to
// the guest on.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';

void main() {
  group('a pass changes by copy', () {
    const stroke = StrokeLayer(
      width: 6,
      join: SceneStrokeJoin.bevel,
      paint: SolidPaint(SceneColor(0xFF120720)),
      blur: 2,
      dx: 1,
      dy: 2,
      opacity: 0.5,
    );

    test('one field changes and the rest are kept', () {
      expect(
        stroke.copyWith(dx: 9, width: 3),
        const StrokeLayer(
          width: 3,
          join: SceneStrokeJoin.bevel,
          paint: SolidPaint(SceneColor(0xFF120720)),
          blur: 2,
          dx: 9,
          dy: 2,
          opacity: 0.5,
        ),
      );
      expect(stroke.copyWith(), stroke);
    });

    test('a paint can be taken away, which copyWith cannot say', () {
      var plain = stroke.withPaint(null);
      expect(plain.paint, isNull);
      expect(plain, isA<StrokeLayer>());
      expect(plain.width, 6);
    });

    test('a fill copies the same way', () {
      const fill = FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400)), dy: 4);
      expect(
        fill.copyWith(opacity: 0.25),
        const FillLayer(
          paint: SolidPaint(SceneColor(0xFFFFC400)),
          dy: 4,
          opacity: 0.25,
        ),
      );
      expect(fill.withPaint(null), const FillLayer(dy: 4));
    });
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: compile error — `The method 'copyWith' isn't defined for the type 'StrokeLayer'`.

- [ ] **Step 3: Add `withPaint` and `copyWith` to the values**

In `lib/src/scene/core/values.dart`, add to `sealed class TextLayer` (after `Map<String, Object?> toWire();`):

```dart
  /// This pass painted with [paint] instead — null included, which is "the
  /// text's own colour" and the one value [copyWith] cannot say, because
  /// there a null means "not given".
  TextLayer withPaint(ScenePaint? paint);

  /// This pass with the fields given changed and the rest kept. Every edit
  /// and every rescale goes through here, so a field added to a pass is
  /// carried by all of them rather than dropped by whichever call site
  /// respelled the constructor and forgot it.
  TextLayer copyWith({double? blur, double? dx, double? dy, double? opacity});
```

Add to `class FillLayer` (after `toWire`):

```dart
  @override
  FillLayer withPaint(ScenePaint? paint) =>
      FillLayer(paint: paint, blur: blur, dx: dx, dy: dy, opacity: opacity);

  @override
  FillLayer copyWith({double? blur, double? dx, double? dy, double? opacity}) =>
      FillLayer(
        paint: paint,
        blur: blur ?? this.blur,
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        opacity: opacity ?? this.opacity,
      );
```

Add to `class StrokeLayer` (after `toWire`):

```dart
  @override
  StrokeLayer withPaint(ScenePaint? paint) => StrokeLayer(
    width: width,
    join: join,
    paint: paint,
    blur: blur,
    dx: dx,
    dy: dy,
    opacity: opacity,
  );

  @override
  StrokeLayer copyWith({
    double? blur,
    double? dx,
    double? dy,
    double? opacity,
    double? width,
    SceneStrokeJoin? join,
  }) => StrokeLayer(
    width: width ?? this.width,
    join: join ?? this.join,
    paint: paint,
    blur: blur ?? this.blur,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    opacity: opacity ?? this.opacity,
  );
```

- [ ] **Step 4: Run the test to see it pass**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Collapse the three respelling sites**

`app/lib/src/scene/ui/layer_list.dart` — in `_detail`:
- `_replace(i, _withPaint(layer, null))` → `_replace(i, layer.withPaint(null))`
- `_withPaint(layer, c == null ? null : SolidPaint(c))` → `layer.withPaint(c == null ? null : SolidPaint(c))`
- `_withOffset(layer, dx: v)` → `layer.copyWith(dx: v)`; `_withOffset(layer, dy: v)` → `layer.copyWith(dy: v)`
- `_withBlur(layer, v)` → `layer.copyWith(blur: v)`; `_withOpacity(layer, v)` → `layer.copyWith(opacity: v)`
- Replace the width block:

```dart
          if (layer case StrokeLayer stroke)
            _number(
              context,
              'Width',
              stroke.width,
              const SceneNumberShape(perPixel: 0.2, decimals: 1, min: 0),
              (v) => _replace(
                i,
                stroke.copyWith(width: v),
                mergeKey: 'layer:$i:width',
              ),
            ),
```

- Delete the comment `// A layer is a value, so every edit is a new one…` and the four functions `_withPaint`, `_withOffset`, `_withBlur`, `_withOpacity` at the end of the file.

`app/lib/src/scene/ui/library_view.dart` — replace `_scaledLayer`:

```dart
  static TextLayer _scaledLayer(TextLayer layer, double scale) {
    var scaled = layer.copyWith(
      dx: layer.dx * scale,
      dy: layer.dy * scale,
      blur: layer.blur * scale,
    );
    return switch (scaled) {
      StrokeLayer s => s.copyWith(width: s.width * scale),
      FillLayer f => f,
    };
  }
```

`app/lib/src/scene/layer_presets.dart` — replace `_scaled`:

```dart
TextLayer _scaled(TextLayer l, double k) {
  var scaled = l.copyWith(
    blur: _round(l.blur * k),
    dx: _round(l.dx * k),
    dy: _round(l.dy * k),
  );
  return switch (scaled) {
    StrokeLayer s => s.copyWith(width: _round(s.width * k)),
    FillLayer f => f,
  };
}
```

- [ ] **Step 6: Run the scene suite**

Run: `cd app && fvm flutter test test/scene`
Expected: all PASS — the preset and library rescale tests are the ones that cover step 5.

- [ ] **Step 7: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene/core/values.dart app/lib/src/scene/ui/layer_list.dart app/lib/src/scene/ui/library_view.dart app/lib/src/scene/layer_presets.dart app/test/scene/scene_paint_test.dart
git commit -m "Scene: text layers change by copyWith instead of respelling the constructor

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: A gradient of any length paints; the file says what the engine refuses

`dart:ui` throws `"colors" must have length 2 if "colorStops" is omitted` — so a `LinearPaint` of three colours and no stops takes the paint down today, although the model documents null stops as an even spread. This task introduces `SceneGradient` (what the three gradients share), computes the even spread before the engine sees it, moves shader construction to its own file, and makes the grammar refuse what the engine cannot draw.

**Files:**
- Modify: `lib/src/scene/core/values.dart` (the `ScenePaint` family)
- Create: `lib/src/scene/gradient_shader.dart`
- Modify: `lib/src/scene/layered_text.dart:187-233`
- Modify: `app/lib/src/scene/paint_grammar.dart:165-216`
- Modify: `app/lib/src/scene/ui/layer_list.dart` (`_chip`, `_detail`)
- Create: `app/test/scene/scene_gradient_paint_test.dart`
- Modify: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_layers_test.dart`

**Interfaces:**
- Produces: `sealed class SceneGradient extends ScenePaint` with `List<SceneColor> colors`, `List<double>? stops`, `List<double> get resolvedStops`, `SceneGradient withStops(List<SceneColor> colors, List<double>? stops)`. `LinearPaint extends SceneGradient`.
- Produces: `ui.Shader sceneGradientShader(SceneGradient g, Rect box, {double opacity = 1})` in `lib/src/scene/gradient_shader.dart` (not exported; imported by `layered_text.dart`).
- Produces (grammar, private): `({List<SceneColor> colors, List<double>? stops})? _readStops(Expression at, Map<String, Expression> named, String kind, Refuse refuse)`.

- [ ] **Step 1: Write the failing pixel tests**

Create `app/test/scene/scene_gradient_paint_test.dart`:

```dart
// A gradient pass, read back as pixels. The test font draws every glyph as
// a filled box, which is what makes this possible: the ink covers the whole
// line, so the colour at a point is the gradient's colour there.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

const _red = SceneColor(0xFFFF0000);
const _green = SceneColor(0xFF00FF00);
const _blue = SceneColor(0xFF0000FF);

/// [layers] over [text] at 20px, painted by the stack painter alone into a
/// [size] picture — no widget tree, so the box is exactly [size]. Ten `M`s
/// are one 200×20 line.
Future<ui.Image> _paint(
  List<TextLayer> layers, {
  String text = 'MMMMMMMMMM',
  Size size = const Size(200, 20),
}) {
  var painter = SceneTextStackPainter(
    span: TextSpan(text: text),
    style: const TextStyle(fontSize: 20, height: 1, color: Color(0xFFFFFFFF)),
    layers: layers,
    textAlign: TextAlign.left,
    maxLines: null,
    overflow: TextOverflow.clip,
    textDirection: TextDirection.ltr,
    scaler: TextScaler.noScaling,
    widthBasis: TextWidthBasis.parent,
    heightBehavior: null,
  );
  var recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  return recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
}

/// The mean colour of the inked pixels in [region] — ink only, so a gap
/// between glyphs in a real font would not dilute it.
Future<({int r, int g, int b})> _mean(ui.Image image, Rect region) async {
  var bytes = (await image.toByteData())!;
  var (r, g, b, n) = (0, 0, 0, 0);
  for (var y = region.top.toInt(); y < region.bottom.toInt(); y++) {
    for (var x = region.left.toInt(); x < region.right.toInt(); x++) {
      var i = (y * image.width + x) * 4;
      if (bytes.getUint8(i + 3) < 128) continue;
      r += bytes.getUint8(i);
      g += bytes.getUint8(i + 1);
      b += bytes.getUint8(i + 2);
      n++;
    }
  }
  expect(n, greaterThan(0), reason: 'no ink in $region');
  return (r: r ~/ n, g: g ~/ n, b: b ~/ n);
}

/// A 10×4 patch centred on ([x], [y]).
Rect _spot(double x, double y) => Rect.fromLTWH(x - 5, y - 2, 10, 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a linear gradient', () {
    const across = LinearPaint(
      colors: [_red, _blue],
      begin: SceneAlignment.centerLeft,
      end: SceneAlignment.centerRight,
    );

    test('runs across the box, begin to end', () async {
      var image = await _paint(const [FillLayer(paint: across)]);
      var left = await _mean(image, _spot(10, 10));
      var right = await _mean(image, _spot(190, 10));
      expect(left.r, greaterThan(left.b));
      expect(right.b, greaterThan(right.r));
    });

    test('with three colours and no stops, spreads them evenly', () async {
      // dart:ui refuses a gradient with no stops unless it has exactly two
      // colours. The model says a null is an even spread, so the renderer is
      // what has to say it to the engine — before this it threw mid-paint.
      var image = await _paint(const [
        FillLayer(
          paint: LinearPaint(
            colors: [_red, _green, _blue],
            begin: SceneAlignment.centerLeft,
            end: SceneAlignment.centerRight,
          ),
        ),
      ]);
      var middle = await _mean(image, _spot(100, 10));
      expect(middle.g, greaterThan(middle.r));
      expect(middle.g, greaterThan(middle.b));
    });

    test('with stops that do not fit its colours, spreads them evenly', () async {
      var image = await _paint(const [
        FillLayer(
          paint: LinearPaint(
            colors: [_red, _green, _blue],
            stops: [0, 1],
            begin: SceneAlignment.centerLeft,
            end: SceneAlignment.centerRight,
          ),
        ),
      ]);
      var middle = await _mean(image, _spot(100, 10));
      expect(middle.g, greaterThan(middle.r));
    });

    test('with fewer than two colours, is a solid', () async {
      var one = await _paint(const [
        FillLayer(paint: LinearPaint(colors: [_red])),
      ]);
      expect((await _mean(one, _spot(100, 10))).r, greaterThan(200));
      // None at all is the text's own colour, white here.
      var none = await _paint(const [FillLayer(paint: LinearPaint(colors: []))]);
      var own = await _mean(none, _spot(100, 10));
      expect([own.r, own.g, own.b], everyElement(greaterThan(200)));
    });
  });
}
```

Add to `app/test/scene/scene_paint_test.dart`, inside `main()`:

```dart
  group('a gradient', () {
    const a = SceneColor(0xFFFF0000);
    const b = SceneColor(0xFF00FF00);
    const c = SceneColor(0xFF0000FF);

    test('spreads its colours evenly when it names no stops', () {
      expect(const LinearPaint(colors: [a, b, c]).resolvedStops, [0, 0.5, 1]);
    });

    test('keeps stops that give one per colour, and ignores any others', () {
      expect(
        const LinearPaint(colors: [a, b], stops: [0.2, 0.9]).resolvedStops,
        [0.2, 0.9],
      );
      expect(
        const LinearPaint(colors: [a, b, c], stops: [0, 1]).resolvedStops,
        [0, 0.5, 1],
      );
    });

    test('changes its stops and keeps its shape', () {
      const g = LinearPaint(
        colors: [a, b],
        begin: SceneAlignment.centerLeft,
        end: SceneAlignment.centerRight,
      );
      expect(
        g.withStops([a, b, c], [0, 0.3, 1]),
        const LinearPaint(
          colors: [a, b, c],
          stops: [0, 0.3, 1],
          begin: SceneAlignment.centerLeft,
          end: SceneAlignment.centerRight,
        ),
      );
    });
  });
```

Add to `app/test/scene/scene_layers_test.dart`, inside `group('a paint stack', …)`:

```dart
    test('refuses a gradient of one colour, and stops that do not fit', () {
      var parsed = parseSceneFile(
        _scene('[FillLayer(paint: LinearPaint(colors: [SceneColor(0xFFFF0000)]))]'),
      );
      expect(parsed.refusals.single.construct, 'paint');
      expect(parsed.refusals.single.message, contains('two colours'));
      parsed = parseSceneFile(
        _scene(
          '[FillLayer(paint: LinearPaint(colors: '
          '[SceneColor(0xFFFF0000), SceneColor(0xFF0000FF)], stops: [0]))]',
        ),
      );
      expect(parsed.refusals.single.construct, 'paint');
      expect(parsed.refusals.single.message, contains('one stop per colour'));
    });
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_gradient_paint_test.dart test/scene/scene_paint_test.dart test/scene/scene_layers_test.dart`
Expected: `scene_paint_test` fails to compile (`resolvedStops`, `withStops` undefined); the pixel file fails with `Invalid argument(s): "colors" must have length 2 if "colorStops" is omitted.` (measured on this SDK while writing the plan); the grammar test fails on `refusals.single` (there are none).

- [ ] **Step 3: Add `SceneGradient` and make `LinearPaint` one**

In `lib/src/scene/core/values.dart`, update the `ScenePaint` doc comment's last sentence to: `Linear, radial and sweep share [SceneGradient]; the wire tags the kind, so a new one is additive.` Then replace the `fromWire` body's `LinearPaint` arm and the whole `class LinearPaint` with:

```dart
    Map m when m['k'] == 'linear' => LinearPaint(
      colors: _wireColors(m),
      stops: _wireStops(m),
      begin: SceneAlignment.fromWire(m['begin'], SceneAlignment.topCenter),
      end: SceneAlignment.fromWire(m['end'], SceneAlignment.bottomCenter),
    ),
```

```dart
List<SceneColor> _wireColors(Map m) => [
  for (var c in (m['colors'] as List? ?? const [])) SceneColor((c as num).toInt()),
];

List<double>? _wireStops(Map m) => switch (m['stops']) {
  List l => [for (var s in l) (s as num).toDouble()],
  _ => null,
};

/// The three gradients, and what they share: colours, where each one sits,
/// and the even spread a missing position means.
sealed class SceneGradient extends ScenePaint {
  const SceneGradient({required this.colors, this.stops});

  final List<SceneColor> colors;

  /// One position per colour, 0..1 along the gradient. Null spreads the
  /// colours evenly — what the file omits, and what the editor writes out
  /// the first time a stop is moved.
  final List<double>? stops;

  /// [stops] when they give one position per colour, otherwise the even
  /// spread. The engine refuses any other shape, so this is what reaches it.
  List<double> get resolvedStops {
    if (stops case var s? when s.length == colors.length) return s;
    var n = colors.length;
    return [for (var i = 0; i < n; i++) n == 1 ? 0.0 : i / (n - 1)];
  }

  /// This gradient with other colours at other positions, its shape kept —
  /// what every stop edit is.
  SceneGradient withStops(List<SceneColor> colors, List<double>? stops);

  Map<String, Object?> get _stopsWire => {
    'colors': [for (var c in colors) c.argb],
    'stops': ?stops,
  };

  bool _sameStops(SceneGradient other) =>
      _sameList(other.colors, colors) && _sameList(other.stops, stops);

  int get _stopsHash =>
      Object.hash(Object.hashAll(colors), Object.hashAll(stops ?? const []));
}

/// A gradient down the box by default, which is what a metal or a sunset
/// face wants.
class LinearPaint extends SceneGradient {
  const LinearPaint({
    required super.colors,
    super.stops,
    this.begin = SceneAlignment.topCenter,
    this.end = SceneAlignment.bottomCenter,
  });

  final SceneAlignment begin;
  final SceneAlignment end;

  @override
  LinearPaint withStops(List<SceneColor> colors, List<double>? stops) =>
      LinearPaint(colors: colors, stops: stops, begin: begin, end: end);

  @override
  Object toWire() => {
    'k': 'linear',
    ..._stopsWire,
    'begin': begin.toWire(),
    'end': end.toWire(),
  };

  @override
  bool operator ==(Object other) =>
      other is LinearPaint &&
      _sameStops(other) &&
      other.begin == begin &&
      other.end == end;

  @override
  int get hashCode => Object.hash(_stopsHash, begin, end);

  @override
  String toString() => 'LinearPaint($colors)';
}
```

- [ ] **Step 4: Build shaders in one place, tolerantly**

Create `lib/src/scene/gradient_shader.dart`:

```dart
// A gradient paint as the engine takes it.
//
// Its own file because two painters will want it — a text pass today, and a
// frame's fill the day `fill` becomes a list of paints (master plan §6) — and
// because every rule the engine has about gradients is kept here rather than
// at each call. dart:ui throws on a gradient with no stops unless it has
// exactly two colours, so the even spread the model promises is spelled out
// before the engine sees it.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'core/values.dart';
import 'flutter_bridge.dart';

/// [g] measured against [box], every colour faded by [opacity].
///
/// Needs two colours at least. A caller with fewer paints a solid instead:
/// a gradient of one colour is that colour, and the engine is not asked.
ui.Shader sceneGradientShader(
  SceneGradient g,
  Rect box, {
  double opacity = 1,
}) {
  var colors = [
    for (var c in g.colors)
      opacity == 1
          ? c.flutter
          : c.flutter.withValues(alpha: c.flutter.a * opacity),
  ];
  var stops = g.resolvedStops;
  return switch (g) {
    LinearPaint(:var begin, :var end) => ui.Gradient.linear(
      Alignment(begin.x, begin.y).withinRect(box),
      Alignment(end.x, end.y).withinRect(box),
      colors,
      stops,
    ),
  };
}
```

In `lib/src/scene/layered_text.dart`, add `import 'gradient_shader.dart';`, delete `_shader`, and replace the `switch (layer.paint)` in `_paintFor` with:

```dart
    switch (layer.paint) {
      case SolidPaint(:var color):
        paint.color = _faded(color.flutter, layer.opacity);
      case SceneGradient(:var colors) when colors.length < 2:
        // One colour is that colour, and none is the text's: the engine
        // refuses both as gradients.
        paint.color = _faded(
          colors.firstOrNull?.flutter ?? own ?? const Color(0xFF000000),
          layer.opacity,
        );
      case SceneGradient g:
        paint.shader = sceneGradientShader(
          g,
          Offset.zero & size,
          opacity: layer.opacity,
        );
      case null:
        // No paint of its own: the text's colour, which is what lets one
        // stack serve several colours.
        paint.color = _faded(own ?? const Color(0xFF000000), layer.opacity);
    }
```

and add at the end of the file:

```dart
Color _faded(Color c, double opacity) =>
    opacity == 1 ? c : c.withValues(alpha: c.a * opacity);
```

- [ ] **Step 5: Make the grammar refuse what the engine cannot draw**

In `app/lib/src/scene/paint_grammar.dart`, replace the `case ('LinearPaint', var args):` arm of `_readPaint` with:

```dart
    case ('LinearPaint', var args):
      var named = _named(args, 'a gradient', refuse);
      if (named == null) return null;
      var read = _readStops(e, named, 'LinearPaint', refuse);
      if (read == null) return null;
      var begin = _readAlignment(named.remove('begin'), refuse);
      var end = _readAlignment(named.remove('end'), refuse);
      if (!_rest(named, 'LinearPaint', refuse)) return null;
      return LinearPaint(
        colors: read.colors,
        stops: read.stops,
        begin: begin ?? SceneAlignment.topCenter,
        end: end ?? SceneAlignment.bottomCenter,
      );
```

and add after `_readPaint`:

```dart
/// A gradient's colours and where they sit, taken out of [named].
///
/// Shared by the gradients, and where the engine's rules are refused in
/// words instead of thrown mid-paint: two colours at least — one colour is a
/// SolidPaint — and, when positions are given, one per colour.
({List<SceneColor> colors, List<double>? stops})? _readStops(
  Expression at,
  Map<String, Expression> named,
  String kind,
  Refuse refuse,
) {
  var colorList = named.remove('colors');
  if (colorList is! ListLiteral) {
    refuse(
      at.offset,
      'paint',
      'a gradient names its colours — '
          '$kind(colors: [SceneColor(0x…), SceneColor(0x…)])',
    );
    return null;
  }
  var colors = <SceneColor>[];
  for (var c in colorList.elements) {
    if (c is! Expression) continue;
    var color = _readColor(c, refuse);
    if (color == null) return null;
    colors.add(color);
  }
  if (colors.length < 2) {
    refuse(
      colorList.offset,
      'paint',
      'a gradient has two colours at least — one colour is '
          'SolidPaint(SceneColor(0x…))',
    );
    return null;
  }
  List<double>? stops;
  if (named.remove('stops') case var s?) {
    var read = s is ListLiteral
        ? [
            for (var e in s.elements)
              if (e is Expression) _number(e),
          ]
        : null;
    if (read == null || read.length != colors.length || read.contains(null)) {
      refuse(
        s.offset,
        'paint',
        'a gradient has one stop per colour, each a number from 0 to 1 — '
            'or no stops, which spreads the colours evenly',
      );
      return null;
    }
    stops = [for (var v in read) v!];
  }
  return (colors: colors, stops: stops);
}
```

- [ ] **Step 6: Keep the swatch and the detail compiling for any gradient**

In `app/lib/src/scene/ui/layer_list.dart`, replace the `decoration:` of `_chip` with:

```dart
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(context.radii.micro),
        border: Border.all(color: context.colors.line),
        color: switch (layer.paint) {
          SolidPaint(:var color) => Color(color.argb),
          null => widget.color,
          SceneGradient(:var colors) when colors.length < 2 =>
            colors.isEmpty ? widget.color : Color(colors.first.argb),
          SceneGradient() => null,
        },
        gradient: switch (layer.paint) {
          SceneGradient g when g.colors.length >= 2 => _swatch(g),
          _ => null,
        },
      ),
```

add below `_chip`:

```dart
  /// A gradient as a swatch draws it — Flutter's own gradient classes, since
  /// a swatch is a decoration; the pass itself goes through the scene's
  /// shader.
  static Gradient _swatch(SceneGradient g) {
    var colors = [for (var c in g.colors) Color(c.argb)];
    return switch (g) {
      LinearPaint(:var begin, :var end) => LinearGradient(
        colors: colors,
        stops: g.resolvedStops,
        begin: Alignment(begin.x, begin.y),
        end: Alignment(end.x, end.y),
      ),
    };
  }
```

and in `_detail` change `if (layer.paint case LinearPaint _) ...[` to `if (layer.paint case SceneGradient _) ...[`.

- [ ] **Step 7: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_gradient_paint_test.dart test/scene/scene_paint_test.dart test/scene/scene_layers_test.dart test/scene/scene_props_test.dart test/scene/scene_layered_text_test.dart`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: gradients of three or more colours paint instead of throwing

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: A radial gradient, stretched to the box

**Files:**
- Modify: `lib/src/scene/core/values.dart` (add `RadialPaint`, a `fromWire` arm)
- Modify: `lib/src/scene/gradient_shader.dart`
- Modify: `app/lib/src/scene/paint_grammar.dart` (`_paint`, `_readPaint`, `_readAlignment`)
- Modify: `app/lib/src/scene/ui/layer_list.dart` (`_swatch`)
- Modify: `app/test/scene/scene_props_test.dart:20-38`
- Test: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_gradient_paint_test.dart`, `app/test/scene/scene_layers_test.dart`

**Interfaces:**
- Consumes: `SceneGradient`, `_stopsWire`, `_sameStops`, `_stopsHash`, `_wireColors`, `_wireStops` (Task 2); `_readStops` (Task 2).
- Produces: `class RadialPaint extends SceneGradient` — `RadialPaint({required List<SceneColor> colors, List<double>? stops, SceneAlignment center = SceneAlignment.center, double radius = 1})`, `RadialPaint copyWith({SceneAlignment? center, double? radius})`. Wire: `{'k': 'radial', 'colors', 'stops'?, 'center'? (when not centre), 'r'? (when not 1)}`.
- Produces (renderer, private to `gradient_shader.dart`): `Float64List _placed(Offset at, {double sx = 1, double sy = 1, double radians = 0})`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/scene/scene_paint_test.dart`, inside `main()`:

```dart
  group('a radial gradient', () {
    const a = SceneColor(0xFFFFFFFF);
    const b = SceneColor(0xFF000000);

    test('says nothing on the wire that a default already says', () {
      expect(const RadialPaint(colors: [a, b]).toWire(), {
        'k': 'radial',
        'colors': [a.argb, b.argb],
      });
    });

    test('round-trips its centre and radius', () {
      const g = RadialPaint(
        colors: [a, b],
        stops: [0, 0.7],
        center: SceneAlignment(0.2, -0.4),
        radius: 1.5,
      );
      expect(ScenePaint.fromWire(g.toWire()), g);
    });

    test('changes its shape by copy and keeps its stops', () {
      const g = RadialPaint(colors: [a, b], stops: [0, 0.7]);
      expect(
        g.copyWith(radius: 0.5),
        const RadialPaint(colors: [a, b], stops: [0, 0.7], radius: 0.5),
      );
    });
  });
```

Add to `app/test/scene/scene_gradient_paint_test.dart`, inside `main()`:

```dart
  test('a radial gradient is stretched to the box, not its short side', () async {
    var image = await _paint(const [
      FillLayer(
        paint: RadialPaint(
          colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFF000000)],
        ),
      ),
    ]);
    // 20px left of the middle of a 200px line is a fifth of the way to the
    // edge: still light. Measured on the 20px side, the way Flutter's
    // RadialGradient is, the circle would have ended 10px before it.
    var near = await _mean(image, _spot(80, 10));
    expect(near.r, greaterThan(150));
    var edge = await _mean(image, _spot(195, 10));
    expect(edge.r, lessThan(40));
  });
```

Add to `app/test/scene/scene_layers_test.dart`, inside `group('a paint stack', …)`:

```dart
    test('a radial gradient round-trips, and writes no default', () {
      var layers = <TextLayer>[
        const FillLayer(
          paint: RadialPaint(
            colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFFFF2D95)],
            center: SceneAlignment(0.5, -0.25),
            radius: 1.2,
          ),
        ),
      ];
      var out = _emit(layers);
      expect(_read(out), layers);
      expect(_emit(_read(out)), out);
      expect(
        _emit(const [
          FillLayer(
            paint: RadialPaint(
              colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFF000000)],
            ),
          ),
        ]),
        contains(
          'RadialPaint(colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFF000000)])',
        ),
      );
    });
```

In `app/test/scene/scene_props_test.dart`, add this layer to the `ScenePropKind.layers` sample list, before `FillLayer(),`:

```dart
    FillLayer(
      paint: RadialPaint(
        colors: [SceneColor(0xFFFFFFFF), SceneColor(0xFFFF2D95)],
        stops: [0, 0.8],
        center: SceneAlignment(0.2, -0.4),
        radius: 1.5,
      ),
    ),
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: compile error — `Undefined name 'RadialPaint'`.

- [ ] **Step 3: Add the value**

In `lib/src/scene/core/values.dart`, add to `ScenePaint.fromWire`, after the `'linear'` arm:

```dart
    Map m when m['k'] == 'radial' => RadialPaint(
      colors: _wireColors(m),
      stops: _wireStops(m),
      center: SceneAlignment.fromWire(m['center'], SceneAlignment.center),
      radius: (m['r'] as num?)?.toDouble() ?? 1,
    ),
```

and after `class LinearPaint`:

```dart
/// A gradient out from a point, STRETCHED TO THE BOX: at [radius] 1 it
/// reaches the edges on both axes, so on a wide headline it is an ellipse.
/// Flutter's `RadialGradient` measures its radius against the shortest side
/// instead, and on a 600×80 title that is a dot in the middle.
class RadialPaint extends SceneGradient {
  const RadialPaint({
    required super.colors,
    super.stops,
    this.center = SceneAlignment.center,
    this.radius = 1,
  });

  final SceneAlignment center;

  /// In half-box units: 1 reaches the edge from the middle, on each axis.
  final double radius;

  @override
  RadialPaint withStops(List<SceneColor> colors, List<double>? stops) =>
      RadialPaint(colors: colors, stops: stops, center: center, radius: radius);

  RadialPaint copyWith({SceneAlignment? center, double? radius}) => RadialPaint(
    colors: colors,
    stops: stops,
    center: center ?? this.center,
    radius: radius ?? this.radius,
  );

  @override
  Object toWire() => {
    'k': 'radial',
    ..._stopsWire,
    if (center != SceneAlignment.center) 'center': center.toWire(),
    if (radius != 1) 'r': radius,
  };

  @override
  bool operator ==(Object other) =>
      other is RadialPaint &&
      _sameStops(other) &&
      other.center == center &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(_stopsHash, center, radius);

  @override
  String toString() => 'RadialPaint($colors)';
}
```

- [ ] **Step 4: Paint it**

In `lib/src/scene/gradient_shader.dart`, add imports `import 'dart:math' as math;` and `import 'dart:typed_data';`, add this arm to the `switch (g)`:

```dart
    RadialPaint(:var center, :var radius) => ui.Gradient.radial(
      Offset.zero,
      math.max(radius, 0.001),
      colors,
      stops,
      ui.TileMode.clamp,
      // A circle at the origin, carried to the centre and stretched to half
      // the box on each axis: at radius 1 it reaches every edge.
      _placed(
        Alignment(center.x, center.y).withinRect(box),
        sx: math.max(box.width / 2, _minHalf),
        sy: math.max(box.height / 2, _minHalf),
      ),
    ),
```

and at the end of the file:

```dart
/// Half a pixel: an empty box would otherwise give the shader a singular
/// matrix, which the engine draws as nothing rather than as an error.
const _minHalf = 0.5;

/// A local matrix that scales by [sx] and [sy], turns by [radians] and then
/// moves to [at] — column-major, the way the engine reads it. Hand-built,
/// since these six numbers are the whole of what is needed.
Float64List _placed(
  Offset at, {
  double sx = 1,
  double sy = 1,
  double radians = 0,
}) {
  var cos = math.cos(radians);
  var sin = math.sin(radians);
  return Float64List.fromList([
    cos * sx, sin * sx, 0, 0, //
    -sin * sy, cos * sy, 0, 0, //
    0, 0, 1, 0, //
    at.dx, at.dy, 0, 1, //
  ]);
}
```

- [ ] **Step 5: Spell and read it in the file**

In `app/lib/src/scene/paint_grammar.dart`, add to `_paint`:

```dart
  RadialPaint(:var colors, :var stops, :var center, :var radius) => [
    'RadialPaint(colors: [${colors.map(_color).join(', ')}]',
    if (stops != null) ', stops: [${stops.map(_num).join(', ')}]',
    if (center != SceneAlignment.center) ', center: ${_alignment(center)}',
    if (radius != 1) ', radius: ${_num(radius)}',
    ')',
  ].join(),
```

add to `_readPaint`, after the `LinearPaint` arm:

```dart
    case ('RadialPaint', var args):
      var named = _named(args, 'a gradient', refuse);
      if (named == null) return null;
      var read = _readStops(e, named, 'RadialPaint', refuse);
      if (read == null) return null;
      var center = _readAlignment(named.remove('center'), refuse);
      var radius = _take(named, 'radius', refuse);
      if (!_rest(named, 'RadialPaint', refuse)) return null;
      return RadialPaint(
        colors: read.colors,
        stops: read.stops,
        center: center ?? SceneAlignment.center,
        radius: radius ?? 1,
      );
```

change the default arm's message to:

```dart
        'a paint is SolidPaint(SceneColor(0x…)), LinearPaint(colors: […]) or '
            'RadialPaint(colors: […]) — nothing else is on the allowlist',
```

and the refusal in `_readAlignment` to:

```dart
    'a point in the box is SceneAlignment.center or SceneAlignment(0, -1)',
```

- [ ] **Step 6: Give it a swatch**

In `app/lib/src/scene/ui/layer_list.dart`, add to the `switch (g)` in `_swatch`:

```dart
      RadialPaint(:var center, :var radius) => RadialGradient(
        colors: colors,
        stops: g.resolvedStops,
        center: Alignment(center.x, center.y),
        // A swatch is square, so the box-stretched radius is Flutter's
        // shortest-side one at half the number.
        radius: radius / 2,
      ),
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart test/scene/scene_gradient_paint_test.dart test/scene/scene_layers_test.dart test/scene/scene_props_test.dart`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: radial gradients on text layers, stretched to the text's box

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: A sweep gradient, in degrees from twelve o'clock

**Files:**
- Modify: `lib/src/scene/core/values.dart` (add `SweepPaint`, a `fromWire` arm)
- Modify: `lib/src/scene/gradient_shader.dart`
- Modify: `app/lib/src/scene/paint_grammar.dart`
- Modify: `app/lib/src/scene/ui/layer_list.dart` (`_swatch`, imports)
- Modify: `app/test/scene/scene_props_test.dart`
- Test: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_gradient_paint_test.dart`, `app/test/scene/scene_layers_test.dart`

**Interfaces:**
- Consumes: `SceneGradient` helpers and `_readStops` (Task 2); `_placed` (Task 3).
- Produces: `class SweepPaint extends SceneGradient` — `SweepPaint({required List<SceneColor> colors, List<double>? stops, SceneAlignment center = SceneAlignment.center, double startAngle = 0, double endAngle = 360})`, `SweepPaint copyWith({SceneAlignment? center, double? startAngle, double? endAngle})`. Wire: `{'k': 'sweep', 'colors', 'stops'?, 'center'?, 'a0'? (when not 0), 'a1'? (when not 360)}`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/scene/scene_paint_test.dart`, inside `main()`:

```dart
  group('a sweep gradient', () {
    const a = SceneColor(0xFFFF0000);
    const b = SceneColor(0xFF0000FF);

    test('says nothing on the wire that a default already says', () {
      expect(const SweepPaint(colors: [a, b]).toWire(), {
        'k': 'sweep',
        'colors': [a.argb, b.argb],
      });
    });

    test('round-trips its centre and angles', () {
      const g = SweepPaint(
        colors: [a, b],
        center: SceneAlignment(-0.5, 0),
        startAngle: 45,
        endAngle: 300,
      );
      expect(ScenePaint.fromWire(g.toWire()), g);
      expect(g.copyWith(startAngle: 90).startAngle, 90);
      expect(g.copyWith(startAngle: 90).endAngle, 300);
    });
  });
```

Add to `app/test/scene/scene_gradient_paint_test.dart`, inside `main()`:

```dart
  group('a sweep gradient', () {
    test('starts at twelve o\'clock and runs clockwise', () async {
      var image = await _paint(const [
        FillLayer(paint: SweepPaint(colors: [_red, _blue])),
      ]);
      // Three o'clock is a quarter of the way round, nine o'clock three
      // quarters. With the engine's own zero at three o'clock, nine would be
      // halfway and read as purple.
      var three = await _mean(image, _spot(150, 10));
      var nine = await _mean(image, _spot(50, 10));
      expect(three.r, greaterThan(three.b));
      expect(nine.b, greaterThan(nine.r));
    });

    test('puts its first colour at its start angle', () async {
      var image = await _paint(const [
        FillLayer(
          paint: SweepPaint(
            colors: [_red, _blue],
            startAngle: 180,
            endAngle: 540,
          ),
        ),
      ]);
      var three = await _mean(image, _spot(150, 10));
      var nine = await _mean(image, _spot(50, 10));
      expect(nine.r, greaterThan(nine.b));
      expect(three.b, greaterThan(three.r));
    });
  });
```

Add to `app/test/scene/scene_layers_test.dart`, inside `group('a paint stack', …)`:

```dart
    test('a sweep gradient round-trips, and writes no default', () {
      var layers = <TextLayer>[
        const StrokeLayer(
          width: 6,
          paint: SweepPaint(
            colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
            startAngle: 45,
            endAngle: 300,
          ),
        ),
      ];
      var out = _emit(layers);
      expect(_read(out), layers);
      expect(_emit(_read(out)), out);
      expect(out, contains('startAngle: 45, endAngle: 300'));
      expect(
        _emit(const [
          FillLayer(
            paint: SweepPaint(
              colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
            ),
          ),
        ]),
        isNot(contains('Angle')),
      );
    });
```

In `app/test/scene/scene_props_test.dart`, add this layer to the `ScenePropKind.layers` sample, before `FillLayer(),`:

```dart
    StrokeLayer(
      width: 3,
      paint: SweepPaint(
        colors: [SceneColor(0xFFFF2D95), SceneColor(0xFF00E5FF)],
        center: SceneAlignment(-0.5, 0),
        startAngle: 45,
        endAngle: 300,
      ),
    ),
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: compile error — `Undefined name 'SweepPaint'`.

- [ ] **Step 3: Add the value**

In `lib/src/scene/core/values.dart`, add to `ScenePaint.fromWire`, after the `'radial'` arm:

```dart
    Map m when m['k'] == 'sweep' => SweepPaint(
      colors: _wireColors(m),
      stops: _wireStops(m),
      center: SceneAlignment.fromWire(m['center'], SceneAlignment.center),
      startAngle: (m['a0'] as num?)?.toDouble() ?? 0,
      endAngle: (m['a1'] as num?)?.toDouble() ?? 360,
    ),
```

and after `class RadialPaint`:

```dart
/// A gradient around a point, the way a clock hand sweeps: 0° is twelve
/// o'clock and angles run clockwise, in degrees — the unit `rotate` uses.
/// Flutter's `SweepGradient` starts at three o'clock in radians; the
/// renderer turns it, so the file never has to.
///
/// Not stretched to the box the way [RadialPaint] is: an angle in a
/// stretched box is not the angle that was typed.
class SweepPaint extends SceneGradient {
  const SweepPaint({
    required super.colors,
    super.stops,
    this.center = SceneAlignment.center,
    this.startAngle = 0,
    this.endAngle = 360,
  });

  final SceneAlignment center;

  /// Where the first colour sits.
  final double startAngle;

  /// Where the last colour sits; past it the last colour holds. 360 more
  /// than [startAngle] is a full turn.
  final double endAngle;

  @override
  SweepPaint withStops(List<SceneColor> colors, List<double>? stops) =>
      SweepPaint(
        colors: colors,
        stops: stops,
        center: center,
        startAngle: startAngle,
        endAngle: endAngle,
      );

  SweepPaint copyWith({
    SceneAlignment? center,
    double? startAngle,
    double? endAngle,
  }) => SweepPaint(
    colors: colors,
    stops: stops,
    center: center ?? this.center,
    startAngle: startAngle ?? this.startAngle,
    endAngle: endAngle ?? this.endAngle,
  );

  @override
  Object toWire() => {
    'k': 'sweep',
    ..._stopsWire,
    if (center != SceneAlignment.center) 'center': center.toWire(),
    if (startAngle != 0) 'a0': startAngle,
    if (endAngle != 360) 'a1': endAngle,
  };

  @override
  bool operator ==(Object other) =>
      other is SweepPaint &&
      _sameStops(other) &&
      other.center == center &&
      other.startAngle == startAngle &&
      other.endAngle == endAngle;

  @override
  int get hashCode => Object.hash(_stopsHash, center, startAngle, endAngle);

  @override
  String toString() => 'SweepPaint($colors)';
}
```

- [ ] **Step 4: Paint it**

In `lib/src/scene/gradient_shader.dart`, add to the `switch (g)`:

```dart
    SweepPaint(:var center, :var startAngle, :var endAngle) =>
      ui.Gradient.sweep(
        Offset.zero,
        colors,
        stops,
        ui.TileMode.clamp,
        // The engine gets a sweep from its own zero, and the turn is in the
        // matrix: it misreads a negative start or one that wraps past a full
        // turn, and an editor's dial produces both. Its start must also be
        // below its end, which a drag of one past the other would break.
        0,
        _radians((endAngle - startAngle).clamp(0.01, 360)),
        // The engine's zero is three o'clock; the file's is twelve.
        _placed(
          Alignment(center.x, center.y).withinRect(box),
          radians: _radians(startAngle - 90),
        ),
      ),
```

and at the end of the file:

```dart
double _radians(double degrees) => degrees * math.pi / 180;
```

- [ ] **Step 5: Spell and read it in the file**

In `app/lib/src/scene/paint_grammar.dart`, add to `_paint`:

```dart
  SweepPaint(:var colors, :var stops, :var center, :var startAngle, :var endAngle) =>
    [
      'SweepPaint(colors: [${colors.map(_color).join(', ')}]',
      if (stops != null) ', stops: [${stops.map(_num).join(', ')}]',
      if (center != SceneAlignment.center) ', center: ${_alignment(center)}',
      if (startAngle != 0) ', startAngle: ${_num(startAngle)}',
      if (endAngle != 360) ', endAngle: ${_num(endAngle)}',
      ')',
    ].join(),
```

add to `_readPaint`, after the `RadialPaint` arm:

```dart
    case ('SweepPaint', var args):
      var named = _named(args, 'a gradient', refuse);
      if (named == null) return null;
      var read = _readStops(e, named, 'SweepPaint', refuse);
      if (read == null) return null;
      var center = _readAlignment(named.remove('center'), refuse);
      var start = _take(named, 'startAngle', refuse);
      var end = _take(named, 'endAngle', refuse);
      if (!_rest(named, 'SweepPaint', refuse)) return null;
      return SweepPaint(
        colors: read.colors,
        stops: read.stops,
        center: center ?? SceneAlignment.center,
        startAngle: start ?? 0,
        endAngle: end ?? 360,
      );
```

and change the default arm's message to:

```dart
        'a paint is SolidPaint(SceneColor(0x…)), or LinearPaint, RadialPaint '
            'or SweepPaint(colors: […]) — nothing else is on the allowlist',
```

- [ ] **Step 6: Give it a swatch**

In `app/lib/src/scene/ui/layer_list.dart`, add `import 'dart:math' as math;` and add to `_swatch`:

```dart
      SweepPaint(:var center, :var startAngle, :var endAngle) => SweepGradient(
        colors: colors,
        stops: g.resolvedStops,
        center: Alignment(center.x, center.y),
        endAngle: (endAngle - startAngle).clamp(0.01, 360) * math.pi / 180,
        transform: GradientRotation((startAngle - 90) * math.pi / 180),
      ),
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart test/scene/scene_gradient_paint_test.dart test/scene/scene_layers_test.dart test/scene/scene_props_test.dart`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: sweep gradients on text layers, in degrees from twelve o'clock

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: A pass can lay its gradient across each line

**Files:**
- Modify: `lib/src/scene/core/values.dart` (`SceneLayerBox`; `box` on `TextLayer`, `FillLayer`, `StrokeLayer`)
- Modify: `lib/src/scene/layered_text.dart` (`paint`, `_painterFor`, `_paintFor`, new `_paintPerLine`, `_PainterKey`)
- Modify: `app/lib/src/scene/paint_grammar.dart` (`_layer`, `_readLayer`)
- Modify: `app/test/scene/scene_props_test.dart`, `app/test/scene/scene_layered_text_test.dart:101-118`
- Test: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_gradient_paint_test.dart`, `app/test/scene/scene_layers_test.dart`

**Interfaces:**
- Consumes: `sceneGradientShader` (Task 2), `TextLayer.copyWith`/`withPaint` (Task 1).
- Produces: `enum SceneLayerBox { text, line }`; `TextLayer.box` (default `SceneLayerBox.text`); `copyWith({…, SceneLayerBox? box})` on all three layer classes. Wire: `'box': 'line'` only when not `text`. File: `box: SceneLayerBox.line`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/scene/scene_paint_test.dart`, inside `main()`:

```dart
  group('a pass\'s box', () {
    test('is on the wire only when it is not the text', () {
      expect(const FillLayer().toWire(), {'k': 'fill'});
      const lined = StrokeLayer(width: 4, box: SceneLayerBox.line);
      expect(lined.toWire()['box'], 'line');
      expect(TextLayer.fromWire(lined.toWire()), lined);
    });

    test('is carried by every copy', () {
      const lined = FillLayer(box: SceneLayerBox.line);
      expect(lined.copyWith(dx: 3).box, SceneLayerBox.line);
      expect(lined.withPaint(const SolidPaint(SceneColor(0xFF000000))).box,
          SceneLayerBox.line);
      expect(const FillLayer().copyWith(box: SceneLayerBox.line), lined);
    });
  });
```

Add to `app/test/scene/scene_gradient_paint_test.dart`, inside `main()`:

```dart
  group('a pass laid across each line', () {
    // Ten Ms over two: the second line is a fifth as long as the first.
    const twoLines = 'MMMMMMMMMM\nMM';
    const size = Size(200, 40);
    const across = LinearPaint(
      colors: [_red, _blue],
      begin: SceneAlignment.centerLeft,
      end: SceneAlignment.centerRight,
    );

    test('runs a short line through the whole gradient', () async {
      var boxed = await _paint(
        const [FillLayer(paint: across)],
        text: twoLines,
        size: size,
      );
      var lined = await _paint(
        const [FillLayer(paint: across, box: SceneLayerBox.line)],
        text: twoLines,
        size: size,
      );
      // The end of "MM": across the text it is a fifth of the way along and
      // still red; across its own line it is the blue end.
      var inBox = await _mean(boxed, _spot(35, 30));
      var inLine = await _mean(lined, _spot(35, 30));
      expect(inBox.r, greaterThan(inBox.b));
      expect(inLine.b, greaterThan(inLine.r));
    });

    test('restarts a gradient down the text on every line', () async {
      var lined = await _paint(
        const [
          FillLayer(
            paint: LinearPaint(colors: [_red, _blue]),
            box: SceneLayerBox.line,
          ),
        ],
        text: twoLines,
        size: size,
      );
      var topOfSecond = await _mean(lined, _spot(20, 22));
      expect(topOfSecond.r, greaterThan(topOfSecond.b));
    });

    test('changes nothing for a solid pass', () async {
      Future<List<int>> bytes(SceneLayerBox box) async {
        var image = await _paint(
          [FillLayer(paint: const SolidPaint(_green), box: box)],
          text: twoLines,
          size: size,
        );
        return (await image.toByteData())!.buffer.asUint8List();
      }

      expect(await bytes(SceneLayerBox.line), await bytes(SceneLayerBox.text));
    });
  });
```

Add to `app/test/scene/scene_layers_test.dart`, inside `group('a paint stack', …)`:

```dart
    test('a pass laid across each line says so, and nothing otherwise', () {
      var layers = <TextLayer>[
        const FillLayer(
          paint: LinearPaint(
            colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
          ),
          box: SceneLayerBox.line,
        ),
      ];
      var out = _emit(layers);
      expect(out, contains('box: SceneLayerBox.line'));
      expect(_read(out), layers);
      expect(_emit(const [FillLayer()]), isNot(contains('box:')));
      var parsed = parseSceneFile(_scene('[FillLayer(box: SceneLayerBox.glyph)]'));
      expect(parsed.refusals.single.message, contains('SceneLayerBox.line'));
    });
```

In `app/test/scene/scene_props_test.dart`, give the sample's `LinearPaint` fill a box — the entry becomes:

```dart
    FillLayer(
      paint: LinearPaint(
        colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
        stops: [0, 1],
        begin: SceneAlignment.centerLeft,
        end: SceneAlignment.centerRight,
      ),
      box: SceneLayerBox.line,
    ),
```

In `app/test/scene/scene_layered_text_test.dart`, in `'the box is the same whether it is painted once or nine times'`, add as the last layer of the second `_mount`:

```dart
        FillLayer(
          paint: LinearPaint(
            colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
          ),
          box: SceneLayerBox.line,
        ),
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: compile error — `Undefined name 'SceneLayerBox'`.

- [ ] **Step 3: Add the box to the values**

In `lib/src/scene/core/values.dart`, add before `sealed class TextLayer`:

```dart
/// What a pass's paint is laid across. A solid colour is the same either
/// way; a gradient is not — a two-line title in gold wants the gold to run
/// down EACH line, not once down the paragraph with the second line in its
/// darker half.
///
/// On the pass rather than on the paint, because a paint is shaped to be a
/// frame's fill one day (master plan §6), and a frame has no lines.
enum SceneLayerBox { text, line }
```

Then make these changes to the three layer classes:

- `TextLayer` constructor gains `this.box = SceneLayerBox.text,` and the class gains the field:

```dart
  /// What [paint] is measured against: the whole text, or each line.
  final SceneLayerBox box;
```

- `_common` gains `if (box != SceneLayerBox.text) 'box': box.name,`.
- `TextLayer.fromWire` reads `var box = SceneLayerBox.values.asNameMap()[raw['box']] ?? SceneLayerBox.text;` and passes `box: box` to both constructors.
- The abstract `copyWith` becomes `TextLayer copyWith({double? blur, double? dx, double? dy, double? opacity, SceneLayerBox? box});`
- `FillLayer`:

```dart
class FillLayer extends TextLayer {
  const FillLayer({
    super.paint,
    super.blur,
    super.dx,
    super.dy,
    super.opacity,
    super.box,
  });

  @override
  Map<String, Object?> toWire() => {'k': 'fill', ..._common};

  @override
  FillLayer withPaint(ScenePaint? paint) => FillLayer(
    paint: paint,
    blur: blur,
    dx: dx,
    dy: dy,
    opacity: opacity,
    box: box,
  );

  @override
  FillLayer copyWith({
    double? blur,
    double? dx,
    double? dy,
    double? opacity,
    SceneLayerBox? box,
  }) => FillLayer(
    paint: paint,
    blur: blur ?? this.blur,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    opacity: opacity ?? this.opacity,
    box: box ?? this.box,
  );

  @override
  bool operator ==(Object other) =>
      other is FillLayer &&
      other.paint == paint &&
      other.blur == blur &&
      other.dx == dx &&
      other.dy == dy &&
      other.opacity == opacity &&
      other.box == box;

  @override
  int get hashCode => Object.hash(paint, blur, dx, dy, opacity, box);

  @override
  String toString() => 'FillLayer($paint)';
}
```

- `StrokeLayer`:

```dart
class StrokeLayer extends TextLayer {
  const StrokeLayer({
    this.width = 1,
    this.join = SceneStrokeJoin.round,
    super.paint,
    super.blur,
    super.dx,
    super.dy,
    super.opacity,
    super.box,
  });

  final double width;
  final SceneStrokeJoin join;

  @override
  Map<String, Object?> toWire() => {
    'k': 'stroke',
    'w': width,
    if (join != SceneStrokeJoin.round) 'j': join.index,
    ..._common,
  };

  @override
  StrokeLayer withPaint(ScenePaint? paint) => StrokeLayer(
    width: width,
    join: join,
    paint: paint,
    blur: blur,
    dx: dx,
    dy: dy,
    opacity: opacity,
    box: box,
  );

  @override
  StrokeLayer copyWith({
    double? blur,
    double? dx,
    double? dy,
    double? opacity,
    SceneLayerBox? box,
    double? width,
    SceneStrokeJoin? join,
  }) => StrokeLayer(
    width: width ?? this.width,
    join: join ?? this.join,
    paint: paint,
    blur: blur ?? this.blur,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    opacity: opacity ?? this.opacity,
    box: box ?? this.box,
  );

  @override
  bool operator ==(Object other) =>
      other is StrokeLayer &&
      other.width == width &&
      other.join == join &&
      other.paint == paint &&
      other.blur == blur &&
      other.dx == dx &&
      other.dy == dy &&
      other.opacity == opacity &&
      other.box == box;

  @override
  int get hashCode =>
      Object.hash(width, join, paint, blur, dx, dy, opacity, box);

  @override
  String toString() => 'StrokeLayer($width, $paint)';
}
```

- [ ] **Step 4: Spell and read it in the file**

In `app/lib/src/scene/paint_grammar.dart`, in `_layer` after the `opacity` line:

```dart
  if (l.box != SceneLayerBox.text) {
    args.add('box: SceneLayerBox.${l.box.name}');
  }
```

In `_readLayer`, after `var opacity = …`:

```dart
  var box = SceneLayerBox.text;
  if (named.remove('box') case var b?) {
    var read = _enumMember(
      b,
      'SceneLayerBox',
      SceneLayerBox.values.map((v) => v.name),
    );
    if (read == null) {
      refuse(
        b.offset,
        'layers',
        'a box is SceneLayerBox.text or SceneLayerBox.line',
      );
      return null;
    }
    box = SceneLayerBox.values.byName(read);
  }
```

and pass `box: box,` to both the `FillLayer(…)` and `StrokeLayer(…)` it returns.

- [ ] **Step 5: Paint a line-box pass as a mask coloured line by line**

In `lib/src/scene/layered_text.dart`, replace `paint`:

```dart
  @override
  void paint(Canvas canvas, Size size) {
    for (var layer in layers) {
      var moved = layer.dx != 0 || layer.dy != 0;
      if (moved) {
        canvas.save();
        canvas.translate(layer.dx, layer.dy);
      }
      if (_perLine(layer)) {
        _paintPerLine(canvas, layer, size);
      } else {
        _painterFor(layer, size).paint(canvas, Offset.zero);
      }
      if (moved) canvas.restore();
    }
  }

  /// Whether [layer]'s paint restarts on every line. Only a gradient can
  /// tell the difference, so a solid pass never pays for it.
  static bool _perLine(TextLayer layer) =>
      layer.box == SceneLayerBox.line &&
      layer.paint is SceneGradient &&
      (layer.paint! as SceneGradient).colors.length >= 2;

  /// A pass whose gradient is laid across each line rather than the text.
  ///
  /// One gradient cannot restart per line, so the pass is painted as a MASK
  /// — the same glyphs, stroke and blur, in opaque black — and each line's
  /// gradient is drawn over it keeping only where the mask is (`srcIn`).
  /// Still one layout; the price is a layer save, paid only by passes that
  /// ask for it. A band runs to the midpoint of the gap to its neighbours
  /// and far past the box at the ends, so a stroke or a blur that spills
  /// out of its line still takes that line's colours.
  void _paintPerLine(Canvas canvas, TextLayer layer, Size size) {
    var gradient = layer.paint! as SceneGradient;
    var mask = _painterFor(layer, size, mask: true);
    var lines = mask.computeLineMetrics();
    canvas.saveLayer(null, Paint());
    mask.paint(canvas, Offset.zero);
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var top = line.baseline - line.ascent;
      var bottom = line.baseline + line.descent;
      var bandTop = i == 0
          ? -_spill
          : (lines[i - 1].baseline + lines[i - 1].descent + top) / 2;
      var bandBottom = i == lines.length - 1
          ? size.height + _spill
          : (bottom + lines[i + 1].baseline - lines[i + 1].ascent) / 2;
      canvas.drawRect(
        Rect.fromLTRB(-_spill, bandTop, size.width + _spill, bandBottom),
        Paint()
          ..blendMode = BlendMode.srcIn
          ..shader = sceneGradientShader(
            gradient,
            Rect.fromLTRB(line.left, top, line.left + line.width, bottom),
            opacity: layer.opacity,
          ),
      );
    }
    canvas.restore();
  }
```

Change `_painterFor` to take the mask flag and key on it:

```dart
  TextPainter _painterFor(TextLayer layer, Size size, {bool mask = false}) {
    var key = _PainterKey(
      span.toPlainText(),
      style,
      layer,
      size,
      textAlign,
      maxLines,
      textDirection,
      scaler,
      widthBasis,
      heightBehavior,
      mask,
    );
```

and inside its builder, `foreground: _paintFor(layer, size, style.color, mask: mask),`.

Change `_paintFor`'s signature to `ui.Paint _paintFor(TextLayer layer, Size size, Color? own, {bool mask = false})`, and replace its `switch (layer.paint) { … }` with:

```dart
    if (mask) {
      // Coverage only: the colours arrive per line, and opacity with them.
      paint.color = const Color(0xFF000000);
    } else {
      switch (layer.paint) {
        case SolidPaint(:var color):
          paint.color = _faded(color.flutter, layer.opacity);
        case SceneGradient(:var colors) when colors.length < 2:
          // One colour is that colour, and none is the text's: the engine
          // refuses both as gradients.
          paint.color = _faded(
            colors.firstOrNull?.flutter ?? own ?? const Color(0xFF000000),
            layer.opacity,
          );
        case SceneGradient g:
          paint.shader = sceneGradientShader(
            g,
            Offset.zero & size,
            opacity: layer.opacity,
          );
        case null:
          // No paint of its own: the text's colour, which is what lets one
          // stack serve several colours.
          paint.color = _faded(own ?? const Color(0xFF000000), layer.opacity);
      }
    }
```

The stroke setup before it and the `maskFilter` blur after it stay as they are, so a mask carries the pass's stroke and blur.

In `_PainterKey`, add a trailing constructor parameter `this.mask`, the field `final bool mask;`, `other.mask == mask &&` to `==`, and `mask` to the `Object.hash` in `hashCode`. Add to the file's constants:

```dart
/// Far enough past the box that no stroke or blur reaches the end of a band.
const _spill = 1e4;
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart test/scene/scene_gradient_paint_test.dart test/scene/scene_layers_test.dart test/scene/scene_props_test.dart test/scene/scene_layered_text_test.dart`
Expected: all PASS.

- [ ] **Step 7: Run the whole scene suite** — the library rescale and the presets now carry `box` through `copyWith`.

Run: `cd app && fvm flutter test test/scene`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test/scene
git commit -m "Scene: a text layer can lay its gradient across each line instead of the whole text

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The arithmetic of editing a paint

Everything the editor does to a paint, as pure functions — so each rule is a unit test rather than a drag in a harness.

**Files:**
- Create: `app/lib/src/scene/gradient_edit.dart`
- Create: `app/test/scene/scene_gradient_edit_test.dart`

**Interfaces:**
- Consumes: `SceneGradient.withStops`, `resolvedStops` (Task 2); `RadialPaint`, `SweepPaint` (Tasks 3–4); `SceneColor.lerp` (existing).
- Produces:
  - `enum ScenePaintKind { text, solid, linear, radial, sweep }` with `String label` and `static ScenePaintKind of(ScenePaint? p)`
  - `ScenePaint? convertPaint(ScenePaint? from, ScenePaintKind kind, {required SceneColor own})`
  - `SceneColor colorAt(SceneGradient g, double t)`
  - `typedef StopEdit = ({SceneGradient gradient, int index});`
  - `StopEdit addStop(SceneGradient g, double t)`, `StopEdit moveStop(SceneGradient g, int index, double t)`, `StopEdit recolorStop(SceneGradient g, int index, SceneColor color)`, `StopEdit removeStop(SceneGradient g, int index)`
  - `double linearAngle(LinearPaint p)`, `LinearPaint withLinearAngle(LinearPaint p, double degrees)`

- [ ] **Step 1: Write the failing tests**

Create `app/test/scene/scene_gradient_edit_test.dart`:

```dart
// What an edit to a paint does, as arithmetic: a converted paint keeps what
// it can, stops stay in order and two at least, and an angle is one number
// for a line through the middle.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/gradient_edit.dart';

const _red = SceneColor(0xFFFF0000);
const _green = SceneColor(0xFF00FF00);
const _blue = SceneColor(0xFF0000FF);

void main() {
  group('changing what a pass is painted with', () {
    test('a colour becomes a gradient that fades out of it', () {
      expect(
        convertPaint(const SolidPaint(_red), ScenePaintKind.linear, own: _blue),
        const LinearPaint(colors: [_red, SceneColor(0x00FF0000)]),
      );
    });

    test('the text colour becomes a gradient out of the text colour', () {
      expect(
        convertPaint(null, ScenePaintKind.radial, own: _blue),
        const RadialPaint(colors: [_blue, SceneColor(0x000000FF)]),
      );
    });

    test('a gradient keeps its colours and stops through a change of shape', () {
      expect(
        convertPaint(
          const LinearPaint(colors: [_red, _green, _blue], stops: [0, 0.2, 1]),
          ScenePaintKind.sweep,
          own: _blue,
        ),
        const SweepPaint(colors: [_red, _green, _blue], stops: [0, 0.2, 1]),
      );
    });

    test('a gradient becomes its first colour, and anything the text colour', () {
      var g = const RadialPaint(colors: [_green, _blue]);
      expect(convertPaint(g, ScenePaintKind.solid, own: _red), const SolidPaint(_green));
      expect(convertPaint(g, ScenePaintKind.text, own: _red), isNull);
    });

    test('the same kind is the same paint, untouched', () {
      const g = LinearPaint(colors: [_red, _blue], begin: SceneAlignment.topLeft);
      expect(identical(convertPaint(g, ScenePaintKind.linear, own: _red), g), isTrue);
      expect(ScenePaintKind.of(g), ScenePaintKind.linear);
      expect(ScenePaintKind.of(null), ScenePaintKind.text);
    });
  });

  group('stops', () {
    const g = LinearPaint(colors: [_red, _blue]);

    test('a colour at a point is the one the gradient paints there', () {
      expect(colorAt(g, 0), _red);
      expect(colorAt(g, 1), _blue);
      expect(colorAt(g, 0.5), SceneColor.lerp(_red, _blue, 0.5));
    });

    test('an added stop changes nothing until it is moved or recoloured', () {
      var edit = addStop(g, 0.5);
      expect(edit.gradient.colors, [_red, SceneColor.lerp(_red, _blue, 0.5), _blue]);
      expect(edit.gradient.stops, [0, 0.5, 1]);
      expect(edit.index, 1);
    });

    test('a stop moved past its neighbour is re-sorted, and followed', () {
      var three = const LinearPaint(colors: [_red, _green, _blue]);
      var edit = moveStop(three, 0, 0.8);
      expect(edit.gradient.colors, [_green, _red, _blue]);
      expect(edit.gradient.stops, [0.5, 0.8, 1]);
      expect(edit.index, 1);
    });

    test('a moved stop lands on a round number', () {
      expect(moveStop(g, 0, 0.123456).gradient.stops!.first, 0.123);
    });

    test('recolouring leaves an even spread unwritten', () {
      var edit = recolorStop(g, 1, _green);
      expect(edit.gradient.colors, [_red, _green]);
      expect(edit.gradient.stops, isNull);
    });

    test('a stop is removed down to two, and no further', () {
      var three = const LinearPaint(colors: [_red, _green, _blue]);
      var edit = removeStop(three, 2);
      expect(edit.gradient.colors, [_red, _green]);
      expect(edit.gradient.stops, [0, 0.5]);
      expect(edit.index, 1);
      expect(identical(removeStop(g, 0).gradient, g), isTrue);
    });

    test('shape survives every stop edit', () {
      const r = RadialPaint(colors: [_red, _blue], radius: 0.4);
      expect((addStop(r, 0.3).gradient as RadialPaint).radius, 0.4);
    });
  });

  group('a linear gradient\'s angle', () {
    test('is 180 for the default, which runs top to bottom', () {
      expect(linearAngle(const LinearPaint(colors: [_red, _blue])), 180);
    });

    test('spells the named ends where there are some', () {
      var across = withLinearAngle(const LinearPaint(colors: [_red, _blue]), 90);
      expect(across.begin, SceneAlignment.centerLeft);
      expect(across.end, SceneAlignment.centerRight);
      var corner = withLinearAngle(const LinearPaint(colors: [_red, _blue]), 45);
      expect(corner.begin, SceneAlignment.bottomLeft);
      expect(corner.end, SceneAlignment.topRight);
    });

    test('reads back what was written, and keeps the stops', () {
      const g = LinearPaint(colors: [_red, _blue], stops: [0.1, 0.9]);
      var turned = withLinearAngle(g, 30);
      expect(linearAngle(turned), 30);
      expect(turned.stops, [0.1, 0.9]);
      expect(linearAngle(withLinearAngle(g, -30)), 330);
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene/scene_gradient_edit_test.dart`
Expected: compile error — the import `gradient_edit.dart` does not exist.

- [ ] **Step 3: Write the arithmetic**

Create `app/lib/src/scene/gradient_edit.dart`:

```dart
// What an edit to a paint is, as arithmetic — kept apart from the widgets so
// every rule (stops stay sorted, two colours at least, a converted paint
// keeps what it can) is a unit test rather than a drag in a test harness.
import 'dart:math' as math;

import 'package:flutterware/scene_authoring.dart';

/// The five things a pass can be painted with, as the picker offers them.
enum ScenePaintKind {
  text('Text colour'),
  solid('Colour'),
  linear('Linear'),
  radial('Radial'),
  sweep('Sweep');

  const ScenePaintKind(this.label);

  final String label;

  static ScenePaintKind of(ScenePaint? p) => switch (p) {
    null => text,
    SolidPaint() => solid,
    LinearPaint() => linear,
    RadialPaint() => radial,
    SweepPaint() => sweep,
  };
}

/// [from] as a paint of [kind], keeping what carries over: a gradient's
/// colours and stops survive a change of shape, a colour becomes a gradient
/// that fades out of it, and a gradient becomes its first colour. [own] is
/// the text's colour, which is what "no paint" means.
ScenePaint? convertPaint(
  ScenePaint? from,
  ScenePaintKind kind, {
  required SceneColor own,
}) {
  if (ScenePaintKind.of(from) == kind) return from;
  var (List<SceneColor> colors, List<double>? stops) = switch (from) {
    SceneGradient g => (g.colors, g.stops),
    SolidPaint(:var color) => ([color, _clear(color)], null),
    null => ([own, _clear(own)], null),
  };
  return switch (kind) {
    ScenePaintKind.text => null,
    ScenePaintKind.solid => SolidPaint(colors.first),
    ScenePaintKind.linear => LinearPaint(colors: colors, stops: stops),
    ScenePaintKind.radial => RadialPaint(colors: colors, stops: stops),
    ScenePaintKind.sweep => SweepPaint(colors: colors, stops: stops),
  };
}

SceneColor _clear(SceneColor c) => SceneColor(c.argb & 0x00FFFFFF);

/// The colour [g] paints at [t], 0..1 along it — what a stop added there
/// starts as, so adding one changes nothing until it is moved or recoloured.
SceneColor colorAt(SceneGradient g, double t) {
  var stops = g.resolvedStops;
  var colors = g.colors;
  if (t <= stops.first) return colors.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      var span = stops[i] - stops[i - 1];
      var k = span == 0 ? 0.0 : (t - stops[i - 1]) / span;
      return SceneColor.lerp(colors[i - 1], colors[i], k);
    }
  }
  return colors.last;
}

/// An edit's result: the next gradient, and where the stop being edited is
/// now — a sort can move it.
typedef StopEdit = ({SceneGradient gradient, int index});

StopEdit addStop(SceneGradient g, double t) {
  var at = _round(t.clamp(0.0, 1.0));
  return _sorted(
    g,
    [...g.colors, colorAt(g, at)],
    [...g.resolvedStops, at],
    g.colors.length,
  );
}

StopEdit moveStop(SceneGradient g, int index, double t) {
  var stops = [...g.resolvedStops];
  stops[index] = _round(t.clamp(0.0, 1.0));
  return _sorted(g, g.colors, stops, index);
}

StopEdit recolorStop(SceneGradient g, int index, SceneColor color) {
  var colors = [...g.colors];
  colors[index] = color;
  // Stops left as they were: recolouring an even spread is no reason to
  // start writing its positions into the file.
  return (gradient: g.withStops(colors, g.stops), index: index);
}

/// Refused below two colours: a gradient of one is a solid, and the kind
/// picker is where that change is made.
StopEdit removeStop(SceneGradient g, int index) {
  if (g.colors.length <= 2) return (gradient: g, index: index);
  var colors = [...g.colors]..removeAt(index);
  var stops = [...g.resolvedStops]..removeAt(index);
  return (
    gradient: g.withStops(colors, stops),
    index: math.min(index, colors.length - 1),
  );
}

/// [colors] at [stops], put in order, with [follow] tracked to wherever the
/// sort puts it. Ties keep their order: `List.sort` is not stable, and a tie
/// broken by the old position is.
StopEdit _sorted(
  SceneGradient g,
  List<SceneColor> colors,
  List<double> stops,
  int follow,
) {
  var order = List.generate(stops.length, (i) => i)
    ..sort((a, b) {
      var c = stops[a].compareTo(stops[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  return (
    gradient: g.withStops(
      [for (var i in order) colors[i]],
      [for (var i in order) stops[i]],
    ),
    index: order.indexOf(follow),
  );
}

/// Three decimals: a dragged stop would otherwise write 0.4372093 into the
/// file, and nobody chose those digits.
double _round(double v) => (v * 1000).roundToDouble() / 1000;

/// A linear gradient's direction as one number, the way a design tool shows
/// it: degrees clockwise from pointing up, so 180 runs top to bottom — the
/// default — and 90 left to right. The dial under the field draws the same.
double linearAngle(LinearPaint p) {
  var dx = p.end.x - p.begin.x;
  var dy = p.end.y - p.begin.y;
  if (dx == 0 && dy == 0) return 180;
  var degrees = math.atan2(dx, -dy) * 180 / math.pi;
  return ((degrees * 10).roundToDouble() / 10 + 360) % 360;
}

/// [p] pointed at [degrees], through the middle of the box and out to its
/// edge, so 45° runs corner to corner. A hand-written begin and end that did
/// not pass through the middle are re-centred by this: an angle is one
/// number, and one number cannot also say where.
LinearPaint withLinearAngle(LinearPaint p, double degrees) {
  var r = degrees * math.pi / 180;
  var x = math.sin(r);
  var y = -math.cos(r);
  var k = 1 / math.max(x.abs(), y.abs());
  var end = SceneAlignment(_tidy(x * k), _tidy(y * k));
  return LinearPaint(
    colors: p.colors,
    stops: p.stops,
    begin: SceneAlignment(-end.x + 0, -end.y + 0),
    end: end,
  );
}

/// Four decimals and no negative zero, so 90° is `centerLeft` to
/// `centerRight` and the file spells it by name.
double _tidy(double v) {
  var r = (v * 10000).roundToDouble() / 10000;
  return r == 0 ? 0 : r;
}
```

Note on `-end.x + 0`: negating `0.0` gives `-0.0`, and adding `0` turns it back into `0.0`, so `begin` compares and prints the same as the named alignment.

- [ ] **Step 4: Run them to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_gradient_edit_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene/gradient_edit.dart app/test/scene/scene_gradient_edit_test.dart
git commit -m "Scene editor: the arithmetic of converting a paint and editing its stops

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The stop bar

**Files:**
- Create: `app/lib/src/scene/ui/gradient_field.dart`
- Create: `app/tool/catalog/demos/scene_gradient_field.dart`
- Create: `app/test/scene/scene_gradient_field_test.dart`

**Interfaces:**
- Consumes: `addStop`, `moveStop`, `recolorStop`, `removeStop`, `StopEdit` (Task 6); `SceneColorField` (`swatches.dart`), `SceneNumberField`/`SceneNumberShape`, `editingDevices`.
- Produces: `typedef GradientChanged = void Function(SceneGradient next, {required String label, String? mergeKey});` and `SceneGradientField({required SceneGradient gradient, required GradientChanged onChanged})`. Keys: `ValueKey('gradient:bar')`, `ValueKey('gradient:stop:$i')`, `ValueKey('gradient:remove')`. `mergeKey`s it emits: `'stop'` (drag), `'stop:at'` (the position field).

- [ ] **Step 1: Write the failing widget test**

Create `app/test/scene/scene_gradient_field_test.dart`:

```dart
// The stop bar, driven the way a hand drives it: a tap on the bar adds a
// stop, a drag moves one past its neighbour, and the last two stay.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/gradient_field.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _red = SceneColor(0xFFFF0000);
const _green = SceneColor(0xFF00FF00);
const _blue = SceneColor(0xFF0000FF);

void main() {
  late SceneGradient current;
  late List<String> labels;

  Future<void> pump(WidgetTester tester, SceneGradient g) async {
    current = g;
    labels = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Material(
          child: Center(
            child: SizedBox(
              width: 240,
              child: StatefulBuilder(
                builder: (context, setState) => SceneGradientField(
                  gradient: current,
                  onChanged: (next, {required label, mergeKey}) {
                    labels.add(label);
                    setState(() => current = next);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a tap on the bar adds a stop there, in the colour there', (
    tester,
  ) async {
    await pump(tester, const LinearPaint(colors: [_red, _blue]));
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('gradient:bar'))));
    await tester.pump();
    expect(current.colors, hasLength(3));
    expect(current.resolvedStops[1], closeTo(0.5, 0.01));
    expect(labels, ['Add stop']);
  });

  testWidgets('a stop dragged past its neighbour is re-sorted', (tester) async {
    await pump(tester, const LinearPaint(colors: [_red, _green, _blue]));
    // The track is 240 less a 12px handle: 180px is ~0.79 of the way,
    // past green at 0.5.
    await tester.drag(
      find.byKey(const ValueKey('gradient:stop:0')),
      const Offset(180, 0),
    );
    await tester.pump();
    expect(current.colors, [_green, _red, _blue]);
    expect(current.resolvedStops[1], closeTo(0.79, 0.01));
  });

  testWidgets('removing stops refuses the last two', (tester) async {
    await pump(tester, const LinearPaint(colors: [_red, _green, _blue]));
    await tester.tap(find.byKey(const ValueKey('gradient:stop:1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gradient:remove')));
    await tester.pump();
    expect(current.colors, [_red, _blue]);
    await tester.tap(find.byKey(const ValueKey('gradient:remove')));
    await tester.pump();
    expect(current.colors, [_red, _blue]);
    expect(labels, ['Remove stop']);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd app && fvm flutter test test/scene/scene_gradient_field_test.dart`
Expected: compile error — `gradient_field.dart` does not exist.

- [ ] **Step 3: Build the field**

Create `app/lib/src/scene/ui/gradient_field.dart`:

```dart
// A gradient's stops, as the bar every design tool draws: the gradient
// itself, a handle under each stop, a tap on the bar to add one, a drag to
// move one, and the selected stop's colour and position beneath.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/tappable.dart';
import '../gradient_edit.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'pointer.dart';
import 'swatches.dart';

/// A change to the gradient, with the words for its undo entry. [mergeKey]
/// is set while a gesture runs, so one drag is one undo entry.
typedef GradientChanged =
    void Function(SceneGradient next, {required String label, String? mergeKey});

class SceneGradientField extends StatefulWidget {
  const SceneGradientField({
    super.key,
    required this.gradient,
    required this.onChanged,
  });

  final SceneGradient gradient;
  final GradientChanged onChanged;

  @override
  State<SceneGradientField> createState() => _SceneGradientFieldState();
}

class _SceneGradientFieldState extends State<SceneGradientField> {
  static const _barHeight = 18.0;
  static const _handle = 12.0;

  /// Which stop is selected, by position — a stop is a value with no
  /// identity, so an index is all there is, and every edit says where the
  /// stop went.
  var _selected = 0;

  /// The gradient as this field last wrote it, until the parent hands it
  /// back. A drag delivers updates faster than the editor rebuilds, and an
  /// update computed from the previous gradient moves the wrong stop the
  /// moment a sort has reordered them.
  SceneGradient? _pending;

  /// Where the dragged handle's centre is, in the track's pixels — kept here
  /// rather than read back from the stop, which is rounded to three places.
  double? _dragX;

  SceneGradient get _g => _pending ?? widget.gradient;

  int get _index => _selected.clamp(0, _g.colors.length - 1);

  @override
  void didUpdateWidget(SceneGradientField old) {
    super.didUpdateWidget(old);
    _pending = null;
  }

  void _apply(StopEdit edit, String label, {String? mergeKey}) {
    setState(() {
      _pending = edit.gradient;
      _selected = edit.index;
    });
    widget.onChanged(edit.gradient, label: label, mergeKey: mergeKey);
  }

  @override
  Widget build(BuildContext context) {
    var colors = context.colors;
    var stops = _g.resolvedStops;
    var index = _index;
    var removable = _g.colors.length > 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Handles ride a track inset by half a handle at each end, so the
            // first and last sit under the bar's ends without overhanging.
            var track = constraints.maxWidth - _handle;
            double at(double t) => _handle / 2 + t * track;
            double tOf(double x) =>
                ((x - _handle / 2) / track).clamp(0.0, 1.0);
            return SizedBox(
              width: double.infinity,
              height: _barHeight + FwSpacing.xxs + _handle,
              child: Stack(
                children: [
                  Positioned(
                    left: _handle / 2,
                    right: _handle / 2,
                    top: 0,
                    height: _barHeight,
                    child: GestureDetector(
                      key: const ValueKey('gradient:bar'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _apply(
                        addStop(_g, tOf(d.localPosition.dx + _handle / 2)),
                        'Add stop',
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            context.radii.micro,
                          ),
                          border: Border.all(color: colors.line),
                          gradient: LinearGradient(
                            colors: [for (var c in _g.colors) Color(c.argb)],
                            stops: stops,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < stops.length; i++)
                    Positioned(
                      left: at(stops[i]) - _handle / 2,
                      top: _barHeight + FwSpacing.xxs,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          key: ValueKey('gradient:stop:$i'),
                          supportedDevices: editingDevices,
                          dragStartBehavior: DragStartBehavior.down,
                          onTap: () => setState(() => _selected = i),
                          onHorizontalDragStart: (_) {
                            setState(() => _selected = i);
                            _dragX = at(stops[i]);
                          },
                          onHorizontalDragUpdate: (d) {
                            _dragX = _dragX! + d.delta.dx;
                            _apply(
                              moveStop(_g, _index, tOf(_dragX!)),
                              'Move stop',
                              mergeKey: 'stop',
                            );
                          },
                          onHorizontalDragEnd: (_) => _dragX = null,
                          child: _StopHandle(
                            color: _g.colors[i],
                            selected: i == index,
                            size: _handle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const Gap(FwSpacing.sm),
        Row(
          children: [
            Expanded(
              child: SceneColorField(
                current: _g.colors[index],
                allowNone: false,
                onPick: (c) =>
                    _apply(recolorStop(_g, index, c!), 'Stop colour'),
              ),
            ),
            const Gap(FwSpacing.sm),
            SizedBox(
              width: 64,
              child: SceneNumberField(
                value: stops[index] * 100,
                shape: const SceneNumberShape(
                  perPixel: 0.5,
                  decimals: 0,
                  unit: '%',
                  min: 0,
                  max: 100,
                ),
                onChanged: (v) => _apply(
                  moveStop(_g, index, v / 100),
                  'Move stop',
                  mergeKey: 'stop:at',
                ),
                onCommit: (v) => _apply(
                  moveStop(_g, index, v / 100),
                  'Move stop',
                  mergeKey: 'stop:at',
                ),
              ),
            ),
            Tappable(
              key: const ValueKey('gradient:remove'),
              onTap: removable
                  ? () => _apply(removeStop(_g, index), 'Remove stop')
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(FwSpacing.xxs),
                child: Icon(
                  Icons.close,
                  size: FwIconSize.xs,
                  color: removable ? colors.mut2 : colors.line,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One stop's handle: its colour in a small square, ringed in the accent
/// when it is the one the fields below are editing.
class _StopHandle extends StatelessWidget {
  const _StopHandle({
    required this.color,
    required this.selected,
    required this.size,
  });

  final SceneColor color;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(color.argb),
      borderRadius: BorderRadius.circular(context.radii.micro),
      border: Border.all(
        color: selected ? context.colors.accent : context.colors.line,
        width: selected ? 2 : 1,
      ),
    ),
  );
}
```

- [ ] **Step 4: Run the test to see it pass**

Run: `cd app && fvm flutter test test/scene/scene_gradient_field_test.dart`
Expected: all PASS.

- [ ] **Step 5: Add the preview**

Create `app/tool/catalog/demos/scene_gradient_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/gradient_field.dart';
import 'package:flutterware_app/src/ui/design/design.dart';

import 'app_theme.dart';

/// A gradient's stops, at the width the inspector gives a paint pass — live,
/// so a stop can be dragged, added and taken away in the preview.
///
/// The question it answers is whether the handles read as belonging to the
/// bar above them, and whether the selected one is obvious in both themes.
@Preview(name: 'Gradient stops', group: 'Scene', wrapper: wrapInAppTheme)
Widget sceneGradientField() => const _Stops();

@Preview(
  name: 'Gradient stops · dark',
  group: 'Scene',
  wrapper: wrapInDarkTheme,
)
Widget sceneGradientFieldDark() => const _Stops();

class _Stops extends StatefulWidget {
  const _Stops();

  @override
  State<_Stops> createState() => _StopsState();
}

class _StopsState extends State<_Stops> {
  SceneGradient _gradient = const LinearPaint(
    colors: [
      SceneColor(0xFFFFF3B0),
      SceneColor(0xFFFFB020),
      SceneColor(0xFF8A4B00),
    ],
    stops: [0, 0.55, 1],
  );

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.panel,
    child: Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(FwSpacing.lg),
        child: SizedBox(
          width: 250,
          child: SceneGradientField(
            gradient: _gradient,
            onChanged: (next, {required label, mergeKey}) =>
                setState(() => _gradient = next),
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 6: Look at it, light and dark**

Invoke (MCP): `flutterware_invoke {plugin: previews, action: screenshot, arguments: {entry: "tool/catalog/demos/scene_gradient_field.dart#sceneGradientField", node: "SceneGradientField"}}`, then the same with `#sceneGradientFieldDark`.
Check: the handles sit centred under their stop positions; the selected handle is clearly ringed; the colour field, the `%` field and the `×` sit on one row at body size; nothing overflows at 250px. Fix and re-shoot until true.

- [ ] **Step 7: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene/ui/gradient_field.dart app/tool/catalog/demos/scene_gradient_field.dart app/test/scene/scene_gradient_field_test.dart
git commit -m "Scene editor: a stop bar for editing a gradient's colours and positions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: The paint editor in the inspector's layer list

**Files:**
- Create: `app/lib/src/scene/ui/paint_field.dart`
- Create: `app/tool/catalog/demos/scene_paint_field.dart`
- Modify: `app/lib/src/scene/ui/layer_list.dart` (`_replace`, `_detail`, `_describe`, imports; new `_labelled`)
- Create: `app/test/scene/scene_layer_list_test.dart`

**Interfaces:**
- Consumes: `SceneGradientField`, `GradientChanged` (Task 7); `ScenePaintKind`, `convertPaint`, `linearAngle`, `withLinearAngle` (Task 6); `RadialPaint.copyWith`, `SweepPaint.copyWith` (Tasks 3–4); `TextLayer.withPaint`, `copyWith(box:)` (Tasks 1, 5); `FwPicker`, `FwChoice`.
- Produces: `typedef PaintChanged = void Function(ScenePaint? next, {required String label, String? mergeKey});` and `ScenePaintField({required ScenePaint? paint, required SceneColor own, required PaintChanged onChanged})`. Keys: `ValueKey('paint:kind')`, `ValueKey('layer:box')`. `_labelled(BuildContext, String, Widget)` in `layer_list.dart` for Task 11.

- [ ] **Step 1: Write the failing widget test**

Create `app/test/scene/scene_layer_list_test.dart`:

```dart
// The layer list's paint editor, driven: a colour pass becomes a gradient
// through the kind picker, and a gradient pass can be laid across each line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/layer_list.dart';
import 'package:flutterware_app/src/ui/theme.dart';

const _red = SceneColor(0xFFFF0000);

void main() {
  late List<TextLayer> layers;
  late List<String> labels;

  Future<void> pump(WidgetTester tester, List<TextLayer> start) async {
    // Tall enough for the blend picker's sixteen rows to open on screen.
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    layers = start;
    labels = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: StatefulBuilder(
                builder: (context, setState) => SceneLayerList(
                  layers: layers,
                  fontSize: 54,
                  color: const Color(0xFFFFFFFF),
                  onChanged: (next, {required label, mergeKey}) {
                    labels.add(label);
                    setState(() => layers = next);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pick(WidgetTester tester, Key picker, String choice) async {
    await tester.tap(find.byKey(picker));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a colour pass becomes a gradient that fades out of it', (
    tester,
  ) async {
    await pump(tester, const [FillLayer(paint: SolidPaint(_red))]);
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    await pick(tester, const ValueKey('paint:kind'), 'Linear');
    expect(
      layers.single.paint,
      const LinearPaint(colors: [_red, SceneColor(0x00FF0000)]),
    );
    expect(find.byKey(const ValueKey('gradient:bar')), findsOneWidget);
  });

  testWidgets('a gradient pass can be laid across each line', (tester) async {
    await pump(tester, const [
      FillLayer(paint: LinearPaint(colors: [_red, SceneColor(0xFF0000FF)])),
    ]);
    await tester.tap(find.textContaining('Fill'));
    await tester.pumpAndSettle();
    await pick(tester, const ValueKey('layer:box'), 'Each line');
    expect(layers.single.box, SceneLayerBox.line);
    expect(find.textContaining('per line'), findsOneWidget);
  });

  testWidgets('a colour pass offers no box: it would change nothing', (
    tester,
  ) async {
    await pump(tester, const [FillLayer(paint: SolidPaint(_red))]);
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layer:box')), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd app && fvm flutter test test/scene/scene_layer_list_test.dart`
Expected: FAIL — `find.byKey(ValueKey('paint:kind'))` finds nothing.

- [ ] **Step 3: Build the paint field**

Create `app/lib/src/scene/ui/paint_field.dart`:

```dart
// What one pass paints with: the kind as a picker, then whatever that kind
// is made of — a colour, or a gradient's stops and its shape.
import 'package:flutter/material.dart';
import 'package:flutterware/scene_authoring.dart';

import '../../ui/design/design.dart';
import '../../ui/picker.dart';
import '../gradient_edit.dart';
import 'gradient_field.dart';
import 'number_field.dart';
import 'number_shape.dart';
import 'swatches.dart';

/// A change to the paint, with the words for its undo entry.
typedef PaintChanged =
    void Function(ScenePaint? next, {required String label, String? mergeKey});

class ScenePaintField extends StatelessWidget {
  const ScenePaintField({
    super.key,
    required this.paint,
    required this.own,
    required this.onChanged,
  });

  /// Null is "the text's own colour".
  final ScenePaint? paint;

  /// The text's colour — what no paint draws, and what a gradient made out
  /// of no paint starts from.
  final SceneColor own;

  final PaintChanged onChanged;

  static const _degrees = SceneNumberShape(
    perPixel: 1,
    decimals: 0,
    unit: '°',
    angular: true,
  );
  static const _percent = SceneNumberShape(
    perPixel: 0.5,
    decimals: 0,
    unit: '%',
    softMin: 0,
    softMax: 100,
  );
  static const _radius = SceneNumberShape(
    perPixel: 0.005,
    decimals: 2,
    min: 0.01,
    softMin: 0,
    softMax: 2,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FwPicker<ScenePaintKind>(
        key: const ValueKey('paint:kind'),
        choices: [
          for (var k in ScenePaintKind.values)
            FwChoice(value: k, label: k.label),
        ],
        selected: ScenePaintKind.of(paint),
        onChanged: (k) =>
            onChanged(convertPaint(paint, k, own: own), label: 'Layer paint'),
      ),
      ...switch (paint) {
        null => const <Widget>[],
        SolidPaint(:var color) => [
          const Gap(FwSpacing.sm),
          SceneColorField(
            current: color,
            allowNone: false,
            onPick: (c) => onChanged(SolidPaint(c!), label: 'Layer colour'),
          ),
        ],
        SceneGradient g => [
          const Gap(FwSpacing.sm),
          SceneGradientField(
            gradient: _editable(g),
            onChanged: (next, {required label, mergeKey}) =>
                onChanged(next, label: label, mergeKey: mergeKey),
          ),
          const Gap(FwSpacing.sm),
          ..._shape(g),
        ],
      },
    ],
  );

  /// A gradient the bar can hold: two colours at least. Only a hand-edited
  /// wire payload can arrive with fewer — the file refuses them — and this
  /// pads with the text's colour rather than drawing a bar with one stop.
  SceneGradient _editable(SceneGradient g) => g.colors.length >= 2
      ? g
      : g.withStops([
          ...g.colors,
          for (var i = g.colors.length; i < 2; i++) own,
        ], null);

  List<Widget> _shape(SceneGradient g) => switch (g) {
    LinearPaint p => [
      _number(
        'Angle',
        linearAngle(p),
        _degrees,
        (v) => onChanged(
          withLinearAngle(p, v),
          label: 'Gradient angle',
          mergeKey: 'angle',
        ),
      ),
    ],
    RadialPaint p => [
      _centre(
        p.center,
        (c) => onChanged(
          p.copyWith(center: c),
          label: 'Gradient centre',
          mergeKey: 'centre',
        ),
      ),
      const Gap(FwSpacing.sm),
      _number(
        'Radius',
        p.radius,
        _radius,
        (v) => onChanged(
          p.copyWith(radius: v),
          label: 'Gradient radius',
          mergeKey: 'radius',
        ),
      ),
    ],
    SweepPaint p => [
      _centre(
        p.center,
        (c) => onChanged(
          p.copyWith(center: c),
          label: 'Gradient centre',
          mergeKey: 'centre',
        ),
      ),
      const Gap(FwSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _number(
              'From',
              p.startAngle,
              _degrees,
              (v) => onChanged(
                p.copyWith(startAngle: v),
                label: 'Gradient start',
                mergeKey: 'from',
              ),
            ),
          ),
          const Gap(FwSpacing.md),
          Expanded(
            child: _number(
              'To',
              p.endAngle,
              _degrees,
              (v) => onChanged(
                p.copyWith(endAngle: v),
                label: 'Gradient end',
                mergeKey: 'to',
              ),
            ),
          ),
        ],
      ),
    ],
  };

  /// A point in the box as two percentages from its top-left — what a
  /// designer reads, where the model's -1..1 is what Flutter's `Alignment`
  /// reads.
  Widget _centre(SceneAlignment c, ValueChanged<SceneAlignment> apply) => Row(
    children: [
      Expanded(
        child: _number(
          'Centre X',
          (c.x + 1) * 50,
          _percent,
          (v) => apply(SceneAlignment(v / 50 - 1, c.y)),
        ),
      ),
      const Gap(FwSpacing.md),
      Expanded(
        child: _number(
          'Centre Y',
          (c.y + 1) * 50,
          _percent,
          (v) => apply(SceneAlignment(c.x, v / 50 - 1)),
        ),
      ),
    ],
  );

  Widget _number(
    String label,
    double value,
    SceneNumberShape shape,
    ValueChanged<double> apply,
  ) => SceneNumberField(
    label: label,
    value: value,
    shape: shape,
    onChanged: apply,
    onCommit: apply,
  );
}
```

- [ ] **Step 4: Put it in the layer list**

In `app/lib/src/scene/ui/layer_list.dart`:

1. Imports: add `import '../../ui/picker.dart';` and `import 'paint_field.dart';`; remove `import 'swatches.dart';` (the colour field now lives in the paint field). Keep `'../layer_presets.dart'`.

2. `_replace` takes a label:

```dart
  void _replace(
    int i,
    TextLayer layer, {
    String label = 'Layer',
    String? mergeKey,
  }) {
    var next = [..._layers];
    next[i] = layer;
    _write(label, next, mergeKey: mergeKey);
  }
```

3. In `_detail`, delete `var caption = …;` and replace the whole `if (layer.paint case SceneGradient _) ...[ … ] else SceneColorField(…),` block with:

```dart
          ScenePaintField(
            paint: layer.paint,
            own: SceneColor(widget.color.toARGB32()),
            onChanged: (next, {required label, mergeKey}) => _replace(
              i,
              layer.withPaint(next),
              label: label,
              mergeKey: mergeKey == null ? null : 'layer:$i:paint:$mergeKey',
            ),
          ),
          if (layer.paint is SceneGradient) ...[
            const Gap(FwSpacing.sm),
            _labelled(
              context,
              'Laid across',
              FwPicker<SceneLayerBox>(
                key: const ValueKey('layer:box'),
                choices: const [
                  FwChoice(value: SceneLayerBox.text, label: 'The whole text'),
                  FwChoice(
                    value: SceneLayerBox.line,
                    label: 'Each line',
                    detail: 'every line runs the whole gradient',
                  ),
                ],
                selected: layer.box,
                onChanged: (b) =>
                    _replace(i, layer.copyWith(box: b), label: 'Layer box'),
              ),
            ),
          ],
```

4. Add below `_number`:

```dart
  /// A control under a caption, the way [SceneNumberField] labels itself —
  /// so a picker in this column reads as the same kind of row as a number.
  Widget _labelled(BuildContext context, String label, Widget control) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: FwSpacing.xs),
            child: Text(
              label,
              style: context.type.caption.copyWith(
                color: context.colors.mut2,
              ),
            ),
          ),
          control,
        ],
      );
```

5. In `_describe`, make the notes:

```dart
    var notes = [
      if (layer.paint == null) 'text colour',
      if (layer.paint case SceneGradient g) switch (g) {
        LinearPaint() => 'linear',
        RadialPaint() => 'radial',
        SweepPaint() => 'sweep',
      },
      if (layer.box == SceneLayerBox.line && layer.paint is SceneGradient)
        'per line',
      if (layer.blur > 0) 'blur ${_short(layer.blur)}',
      if (layer.dx != 0 || layer.dy != 0)
        '${_short(layer.dx)},${_short(layer.dy)}',
      if (layer.opacity != 1) '${(layer.opacity * 100).round()}%',
    ];
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene/scene_layer_list_test.dart test/scene/scene_gradient_field_test.dart test/material_drift_test.dart`
Expected: all PASS.

- [ ] **Step 6: Add the preview**

Create `app/tool/catalog/demos/scene_paint_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/ui/paint_field.dart';
import 'package:flutterware_app/src/ui/design/design.dart';

import 'app_theme.dart';

/// One paint field per kind a pass can be painted with, at the width the
/// inspector gives a layer's detail — each live, so a kind can be switched
/// and a stop dragged in the preview.
///
/// What it answers is whether the four shapes read as one control: the
/// picker, then a colour or a bar, then the numbers that shape it, at one
/// type size down the column.
@Preview(name: 'Paint field', group: 'Scene', wrapper: wrapInAppTheme)
Widget scenePaintField() => const _Paints();

@Preview(name: 'Paint field · dark', group: 'Scene', wrapper: wrapInDarkTheme)
Widget scenePaintFieldDark() => const _Paints();

class _Paints extends StatefulWidget {
  const _Paints();

  @override
  State<_Paints> createState() => _PaintsState();
}

class _PaintsState extends State<_Paints> {
  final _paints = <ScenePaint?>[
    const SolidPaint(SceneColor(0xFFFFC400)),
    const LinearPaint(
      colors: [
        SceneColor(0xFFFFF3B0),
        SceneColor(0xFFFFB020),
        SceneColor(0xFF8A4B00),
      ],
      stops: [0, 0.55, 1],
    ),
    const RadialPaint(
      colors: [SceneColor(0xFFFFFFFF), SceneColor(0x00FFFFFF)],
      radius: 0.8,
    ),
    const SweepPaint(
      colors: [
        SceneColor(0xFFFF2D95),
        SceneColor(0xFF00E5FF),
        SceneColor(0xFFFF2D95),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.panel,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(FwSpacing.lg),
      child: Wrap(
        spacing: FwSpacing.xxl,
        runSpacing: FwSpacing.xxl,
        children: [
          for (var i = 0; i < _paints.length; i++)
            SizedBox(
              width: 240,
              child: ScenePaintField(
                paint: _paints[i],
                own: const SceneColor(0xFFFFFFFF),
                onChanged: (next, {required label, mergeKey}) =>
                    setState(() => _paints[i] = next),
              ),
            ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 7: Look at it, light and dark**

Invoke (MCP): `flutterware_invoke {plugin: previews, action: screenshot, arguments: {entry: "tool/catalog/demos/scene_paint_field.dart#scenePaintField"}}` and `#scenePaintFieldDark`.
Check: one type size down every column (13px body, captions for labels); the angle dial under the linear field; the centre's two fields sit side by side without truncating `Centre X`; sweep's `From`/`To` dials fit 240px. If `Centre X` truncates, shorten the labels to `X`/`Y` under a `_labelled`-style `Centre` caption. Re-shoot until true.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene/ui app/tool/catalog/demos/scene_paint_field.dart app/test/scene/scene_layer_list_test.dart
git commit -m "Scene inspector: edit a text layer's paint as a colour or a linear, radial or sweep gradient

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Specimens, a Gloss preset, and the real thing

**Files:**
- Modify: `app/tool/catalog/demos/scene_layers.dart` (whole file below)
- Modify: `app/lib/src/scene/layer_presets.dart` (append a preset)
- Modify: `app/test/scene/scene_paint_test.dart`

**Interfaces:**
- Consumes: everything in Tasks 1–8.

- [ ] **Step 1: Write the failing preset test**

Add to `app/test/scene/scene_paint_test.dart` (add the import `package:flutterware_app/src/scene/layer_presets.dart`), inside `main()`:

```dart
  test('the gloss preset keeps its sheen per line when scaled', () {
    var gloss = layerPresets.firstWhere((p) => p.name == 'Gloss');
    var small = gloss.forSize(27);
    expect(small.last.box, SceneLayerBox.line);
    expect(small.last.paint, isA<LinearPaint>());
    expect(small.first.paint, isNull, reason: 'the text keeps its own colour');
  });
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: FAIL — `Bad state: No element`.

- [ ] **Step 3: Add the preset**

Append to `layerPresets` in `app/lib/src/scene/layer_presets.dart`:

```dart
  // A sheen over the top half of every line, white fading to nothing — so it
  // sits on whatever colour the text is, which is what a gold would not do.
  LayerPreset('Gloss', [
    FillLayer(),
    FillLayer(
      paint: LinearPaint(
        colors: [SceneColor(0x99FFFFFF), SceneColor(0x00FFFFFF)],
        stops: [0, 0.5],
      ),
      box: SceneLayerBox.line,
    ),
  ]),
```

- [ ] **Step 4: Run it to see it pass**

Run: `cd app && fvm flutter test test/scene/scene_paint_test.dart`
Expected: PASS.

- [ ] **Step 5: Show the new paints in the specimen sheet**

Replace `app/tool/catalog/demos/scene_layers.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutterware/scene.dart';
import 'package:flutterware/scene_authoring.dart';

/// A text's paint stack, in the shapes it is actually reached for.
///
/// Each of these is the same one list with different numbers in it — an
/// outline is a stroke beneath the fill, a sticker is stroke-stroke-fill, a
/// shadow is a blurred offset fill, an extrusion is a run of offset fills
/// under a gradient one. That combinatorial reach is the argument for a list
/// over a `shadows` property and a `stroke` property, which are two points in
/// it and do not compose (master plan §4.5). The last four are paint rather
/// than structure: a radial, a sweep, a gradient laid across each line of a
/// two-line title, and a gloss that fades to nothing so it sits on any colour.
///
/// It is a picture rather than a test because that is what it answers: does a
/// 14px stroke survive a tight counter, does an extrusion read as depth, is
/// the gradient measured against the box, the line or the glyph.
@Preview(name: 'Text layers', group: 'Scene')
Widget sceneLayers() => const _Layers();

const _ink = SceneColor(0xFF120720);
const _neon = SceneColor(0xFFFF2D95);
const _gold = LinearPaint(
  colors: [SceneColor(0xFFFFF3B0), SceneColor(0xFFFFB020)],
);

/// The stack for each specimen, what it is called in a design tool, and the
/// words it is shown on.
const _specimens = <(String, List<TextLayer>, String)>[
  ('plain', [], 'Layers'),
  (
    'outline',
    [
      StrokeLayer(width: 8, paint: SolidPaint(_ink)),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
    ],
    'Layers',
  ),
  (
    'sticker',
    [
      StrokeLayer(width: 20, paint: SolidPaint(SceneColor(0xFFFFFFFF))),
      StrokeLayer(width: 10, paint: SolidPaint(_ink)),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFC400))),
    ],
    'Layers',
  ),
  (
    'shadow',
    [
      FillLayer(
        paint: SolidPaint(SceneColor(0xCC000000)),
        dx: 4,
        dy: 6,
        blur: 8,
      ),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFFFFF))),
    ],
    'Layers',
  ),
  (
    'neon',
    [
      FillLayer(paint: SolidPaint(_neon), blur: 24),
      FillLayer(paint: SolidPaint(_neon), blur: 10),
      FillLayer(paint: SolidPaint(SceneColor(0xFFFFFFFF))),
    ],
    'Layers',
  ),
  // One pixel a step: a depth is a run of offsets close enough to read as a
  // solid side, and two apart is where it starts to band instead.
  (
    'extruded',
    [
      FillLayer(paint: SolidPaint(_ink), dx: 8, dy: 8),
      FillLayer(paint: SolidPaint(_ink), dx: 7, dy: 7),
      FillLayer(paint: SolidPaint(_ink), dx: 6, dy: 6),
      FillLayer(paint: SolidPaint(_ink), dx: 5, dy: 5),
      FillLayer(paint: SolidPaint(_ink), dx: 4, dy: 4),
      FillLayer(paint: SolidPaint(_ink), dx: 3, dy: 3),
      FillLayer(paint: SolidPaint(_ink), dx: 2, dy: 2),
      FillLayer(paint: SolidPaint(_ink), dx: 1, dy: 1),
      FillLayer(paint: _gold),
    ],
    'Layers',
  ),
  (
    'radial',
    [
      StrokeLayer(width: 6, paint: SolidPaint(_ink)),
      FillLayer(
        paint: RadialPaint(
          colors: [SceneColor(0xFFFFFFFF), _neon],
          radius: 1.1,
        ),
      ),
    ],
    'Layers',
  ),
  (
    'sweep',
    [
      StrokeLayer(
        width: 8,
        paint: SweepPaint(
          colors: [
            _neon,
            SceneColor(0xFF00E5FF),
            SceneColor(0xFFFFE600),
            _neon,
          ],
        ),
      ),
      FillLayer(paint: SolidPaint(SceneColor(0xFF1B0F26))),
    ],
    'Layers',
  ),
  // Two lines, so the difference shows: across each line both start pale and
  // end deep; across the text, the second line would be all deep.
  (
    'gold, per line',
    [
      StrokeLayer(width: 8, paint: SolidPaint(_ink)),
      FillLayer(paint: _gold, box: SceneLayerBox.line),
    ],
    'Game\nover',
  ),
  (
    'gloss',
    [
      FillLayer(paint: SolidPaint(SceneColor(0xFF2D7BFF))),
      FillLayer(
        paint: LinearPaint(
          colors: [SceneColor(0x99FFFFFF), SceneColor(0x00FFFFFF)],
          stops: [0, 0.5],
        ),
        box: SceneLayerBox.line,
      ),
    ],
    'Layers',
  ),
];

class _Layers extends StatelessWidget {
  const _Layers();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: const Color(0xFF1B0F26),
      child: Align(
        alignment: Alignment.topLeft,
        child: SceneView.document(_specimenSheet()),
      ),
    ),
  );
}

SceneDocument _specimenSheet() {
  var rows = <SceneNode>[];
  // Nodes are named by position: a specimen's name is a caption with spaces
  // and commas in it, and a node name is an identifier.
  for (var (i, (name, layers, words)) in _specimens.indexed) {
    var label = TextNode(
      name,
      name: 'label_$i',
      style: const SceneTextStyle(
        fontSize: 11,
        letterSpacing: 2,
        textCase: SceneTextCase.upper,
        color: SceneColor(0xFF7A6A88),
      ),
    );
    var word = TextNode(
      words,
      name: 'word_$i',
      style: SceneTextStyle(
        fontSize: 54,
        weight: SceneFontWeight.w900,
        letterSpacing: -1,
        color: const SceneColor(0xFFFFFFFF),
        layers: layers,
      ),
    );
    rows.add(
      FrameNode(name: 'row_$i', layout: NodeLayout.column)
        ..gap = 2
        ..crossAlign = SceneCrossAxisAlignment.start
        ..children.addAll([label, word]),
    );
  }
  var root = FrameNode(name: 'root', layout: NodeLayout.column)
    ..width = 380
    ..height = 1120
    ..fill = const SceneColor(0xFF1B0F26)
    ..padding = const SceneEdges.all(24)
    ..gap = 18
    ..children.addAll(rows);
  return SceneDocument(root);
}
```

- [ ] **Step 6: Look at the sheet**

Invoke (MCP): `flutterware_invoke {plugin: previews, action: screenshot, arguments: {entry: "tool/catalog/demos/scene_layers.dart#sceneLayers", height: 1160}}`.
Check, against the pre-change shot of the same entry: the six existing specimens are pixel-identical in shape; `radial` is pale in the middle of the word, not a dot; `sweep`'s outline cycles pink → cyan → yellow clockwise from the top; in `gold, per line` BOTH lines run pale to deep; `gloss` shows a sheen on the top half of the word only.

- [ ] **Step 7: Check it in the running studio**

The renderer changed in `package:flutterware`, so the scene guest has to be rebuilt to show it.
1. `flutterware_act {verb: observe}` — if nothing is running, `flutterware_invoke {plugin: run, action: launch, arguments: {package: app, entrypoint: lib/main_dev.dart, device: macos, wait: true}}`.
2. `flutterware_act {verb: navigate, route: "fw:///worktrees/dependency-plugin-pub-get-perf-041aa1/flutterware.scene"}` — the refusal, if any, lists the valid segments; open any scene of `examples/example` that has a text node.
3. Reload the scene guest (its reload control in the editor, or relaunch the studio) so it runs the new renderer.
4. Select a text node; in the inspector's Paint section, `+` → `Fill`; open the row; kind picker → `Linear`; tap the bar to add a stop; drag a handle; set `Laid across` → `Each line`.
5. `flutterware_act {verb: observe, screenshot: true}` after each step: the canvas follows every edit; one drag is one undo entry (Cmd+Z once undoes the whole drag); the scene file on disk (autosave) now contains `LinearPaint(` with the stops and `box: SceneLayerBox.line`.

- [ ] **Step 8: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/tool/catalog/demos/scene_layers.dart app/lib/src/scene/layer_presets.dart app/test/scene/scene_paint_test.dart
git commit -m "Scene: gradient specimens in the text layers preview, and a Gloss preset

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

# Phase 2 — Blend modes

### Task 10: A pass blends with what is under it

**Files:**
- Modify: `lib/src/scene/core/values.dart` (`SceneBlendMode`; `blend` on the three layer classes)
- Modify: `lib/src/scene/flutter_bridge.dart`
- Modify: `lib/src/scene/layered_text.dart` (`_paintFor`, `_paintPerLine`)
- Modify: `app/lib/src/scene/paint_grammar.dart` (`_layer`, `_readLayer`)
- Modify: `app/test/scene_bridge_test.dart`, `app/test/scene/scene_props_test.dart`
- Test: `app/test/scene/scene_paint_test.dart`, `app/test/scene/scene_gradient_paint_test.dart`, `app/test/scene/scene_layers_test.dart`

**Interfaces:**
- Consumes: the layer classes as Task 5 left them.
- Produces: `enum SceneBlendMode { normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, hardLight, softLight, difference, exclusion, hue, saturation, color, luminosity }`; `TextLayer.blend` (default `normal`), `copyWith({…, SceneBlendMode? blend})`; `extension SceneBlendModeToFlutter on SceneBlendMode { BlendMode get flutter; }`. Wire `'blend': '<name>'` when not normal; file `blend: SceneBlendMode.multiply`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/scene_bridge_test.dart`, inside `main()`:

```dart
  test('blend modes convert by name, and normal is source-over', () {
    expect(SceneBlendMode.normal.flutter, BlendMode.srcOver);
    for (var m in SceneBlendMode.values.skip(1)) {
      expect(m.flutter.name, m.name);
    }
  });
```

Add to `app/test/scene/scene_paint_test.dart`, inside `main()`:

```dart
  test('a pass says its blend on the wire only when it is not normal', () {
    expect(const FillLayer().toWire().containsKey('blend'), isFalse);
    const multiplied = FillLayer(blend: SceneBlendMode.multiply);
    expect(multiplied.toWire()['blend'], 'multiply');
    expect(TextLayer.fromWire(multiplied.toWire()), multiplied);
    expect(multiplied.copyWith(dx: 2).blend, SceneBlendMode.multiply);
    expect(multiplied.withPaint(null).blend, SceneBlendMode.multiply);
  });
```

Add to `app/test/scene/scene_gradient_paint_test.dart`, inside `main()`:

```dart
  test('a multiplied pass multiplies the pass beneath it', () async {
    // Cyan times yellow is green; painted normally, yellow is yellow.
    var image = await _paint(const [
      FillLayer(paint: SolidPaint(SceneColor(0xFF00FFFF))),
      FillLayer(
        paint: SolidPaint(SceneColor(0xFFFFFF00)),
        blend: SceneBlendMode.multiply,
      ),
    ]);
    var mixed = await _mean(image, _spot(100, 10));
    expect(mixed.g, greaterThan(200));
    expect(mixed.r, lessThan(60));
    expect(mixed.b, lessThan(60));
  });
```

Add to `app/test/scene/scene_layers_test.dart`, inside `group('a paint stack', …)`:

```dart
    test('a blended pass says so, and nothing when it is normal', () {
      var layers = <TextLayer>[
        const FillLayer(
          paint: SolidPaint(SceneColor(0x66FFFFFF)),
          blend: SceneBlendMode.screen,
        ),
      ];
      var out = _emit(layers);
      expect(out, contains('blend: SceneBlendMode.screen'));
      expect(_read(out), layers);
      expect(_emit(const [FillLayer()]), isNot(contains('blend:')));
      var parsed = parseSceneFile(_scene('[FillLayer(blend: BlendMode.plus)]'));
      expect(parsed.refusals.single.message, contains('SceneBlendMode'));
    });
```

In `app/test/scene/scene_props_test.dart`, add `blend: SceneBlendMode.screen,` to the sample's `RadialPaint` fill layer.

- [ ] **Step 2: Run them to see them fail**

Run: `cd app && fvm flutter test test/scene_bridge_test.dart`
Expected: compile error — `Undefined name 'SceneBlendMode'`.

- [ ] **Step 3: Add the blend to the values**

In `lib/src/scene/core/values.dart`, add before `sealed class TextLayer`:

```dart
/// How a pass lands on what is already there — the modes a design tool
/// offers on a layer, by Flutter's names. `normal` is the engine's
/// `srcOver`; the rest are spelled the same on both sides, which the bridge
/// test pins name by name.
enum SceneBlendMode {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  hue,
  saturation,
  color,
  luminosity,
}
```

Then thread the field through every place a pass is built, compared or copied:
- `TextLayer` constructor gains `this.blend = SceneBlendMode.normal,`; the class gains `final SceneBlendMode blend;` documented `/// How this pass lands on the passes beneath it and on what is behind the text.`
- `_common` gains `if (blend != SceneBlendMode.normal) 'blend': blend.name,`.
- `fromWire` reads `var blend = SceneBlendMode.values.asNameMap()[raw['blend']] ?? SceneBlendMode.normal;` and passes `blend: blend` to both constructors.
- The abstract `copyWith` gains `SceneBlendMode? blend`.
- `FillLayer` and `StrokeLayer`: constructors gain `super.blend,`; `withPaint` passes `blend: blend`; `copyWith` gains `SceneBlendMode? blend` and passes `blend: blend ?? this.blend`; `==` gains `&& other.blend == blend`; `hashCode` gains `blend` as the last argument of `Object.hash`.

- [ ] **Step 4: Bridge it**

Add to `lib/src/scene/flutter_bridge.dart`:

```dart
extension SceneBlendModeToFlutter on SceneBlendMode {
  /// By name, not by index: the scene's list is the designer's sixteen and
  /// Flutter's is the engine's twenty-nine, in another order.
  BlendMode get flutter => this == SceneBlendMode.normal
      ? BlendMode.srcOver
      : BlendMode.values.byName(name);
}
```

- [ ] **Step 5: Paint with it**

In `lib/src/scene/layered_text.dart`:
- In `_paintFor`, inside the `else` branch (not the mask), after the `switch`, add `paint.blendMode = layer.blend.flutter;`.
- In `_paintPerLine`, change `canvas.saveLayer(null, Paint());` to `canvas.saveLayer(null, Paint()..blendMode = layer.blend.flutter);` — the mask and its bands compose normally inside the layer, and the layer is what lands on the passes beneath.

- [ ] **Step 6: Spell and read it in the file**

In `app/lib/src/scene/paint_grammar.dart`, in `_layer` after the `box` line:

```dart
  if (l.blend != SceneBlendMode.normal) {
    args.add('blend: SceneBlendMode.${l.blend.name}');
  }
```

In `_readLayer`, after the `box` block:

```dart
  var blend = SceneBlendMode.normal;
  if (named.remove('blend') case var m?) {
    var read = _enumMember(
      m,
      'SceneBlendMode',
      SceneBlendMode.values.map((v) => v.name),
    );
    if (read == null) {
      refuse(
        m.offset,
        'layers',
        'a blend is SceneBlendMode.multiply, .screen, .overlay or another '
            'of the sixteen SceneBlendMode names',
      );
      return null;
    }
    blend = SceneBlendMode.values.byName(read);
  }
```

and pass `blend: blend,` to both returned constructors.

- [ ] **Step 7: Run the tests to see them pass**

Run: `cd app && fvm flutter test test/scene test/scene_bridge_test.dart`
Expected: all PASS.

- [ ] **Step 8: Check it on the real renderer**

`flutter_tester` is not the macOS guest, and a paragraph's foreground paint is where an engine is most likely to drop a blend mode. In the running studio (Task 9 step 7's loop), give a text two fills — cyan beneath, yellow on top with `blend: SceneBlendMode.multiply` (edit the scene file; the editor adopts external changes) — and `flutterware_act {verb: observe, screenshot: true}`.
Expected: the word is green. If it is yellow, the engine ignored the paragraph paint's blend: paint every non-normal pass inside its own layer instead — in `paint`, wrap the `_painterFor(layer, size).paint(...)` call in `canvas.saveLayer(null, Paint()..blendMode = layer.blend.flutter)` / `canvas.restore()` when `layer.blend != SceneBlendMode.normal`, and drop the `paint.blendMode` line from `_paintFor`. Re-run step 7 and this check.

- [ ] **Step 9: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add lib/src/scene app/lib/src/scene app/test
git commit -m "Scene: text layers take a blend mode

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: The blend picker

**Files:**
- Modify: `app/lib/src/scene/ui/layer_list.dart` (`_detail`, `_describe`)
- Modify: `app/test/scene/scene_layer_list_test.dart`

**Interfaces:**
- Consumes: `SceneBlendMode`, `TextLayer.copyWith(blend:)` (Task 10); `_labelled`, `_replace(label:)` (Task 8).

- [ ] **Step 1: Write the failing test**

Add to `app/test/scene/scene_layer_list_test.dart`, inside `main()`:

```dart
  testWidgets('a pass can be set to multiply', (tester) async {
    await pump(tester, const [FillLayer(paint: SolidPaint(_red))]);
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();
    await pick(tester, const ValueKey('layer:blend'), 'Multiply');
    expect(layers.single.blend, SceneBlendMode.multiply);
    expect(find.textContaining('multiply'), findsOneWidget);
    expect(labels.last, 'Layer blend');
  });
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd app && fvm flutter test test/scene/scene_layer_list_test.dart`
Expected: FAIL — `find.byKey(ValueKey('layer:blend'))` finds nothing.

- [ ] **Step 3: Add the picker and the note**

In `app/lib/src/scene/ui/layer_list.dart`, in `_detail`, after the `Row` holding `Blur` and `Opacity` (the last child of the column):

```dart
          const Gap(FwSpacing.sm),
          _labelled(
            context,
            'Blend',
            FwPicker<SceneBlendMode>(
              key: const ValueKey('layer:blend'),
              choices: [
                for (var m in SceneBlendMode.values)
                  FwChoice(value: m, label: _blendLabel(m)),
              ],
              selected: layer.blend,
              onChanged: (m) =>
                  _replace(i, layer.copyWith(blend: m), label: 'Layer blend'),
            ),
          ),
```

add below `_short`:

```dart
  /// A mode in the words a design tool uses — Flutter's names are camel-case
  /// identifiers, and this panel spells colour the British way throughout.
  static String _blendLabel(SceneBlendMode m) => switch (m) {
    SceneBlendMode.normal => 'Normal',
    SceneBlendMode.multiply => 'Multiply',
    SceneBlendMode.screen => 'Screen',
    SceneBlendMode.overlay => 'Overlay',
    SceneBlendMode.darken => 'Darken',
    SceneBlendMode.lighten => 'Lighten',
    SceneBlendMode.colorDodge => 'Colour dodge',
    SceneBlendMode.colorBurn => 'Colour burn',
    SceneBlendMode.hardLight => 'Hard light',
    SceneBlendMode.softLight => 'Soft light',
    SceneBlendMode.difference => 'Difference',
    SceneBlendMode.exclusion => 'Exclusion',
    SceneBlendMode.hue => 'Hue',
    SceneBlendMode.saturation => 'Saturation',
    SceneBlendMode.color => 'Colour',
    SceneBlendMode.luminosity => 'Luminosity',
  };
```

and in `_describe`'s notes, after the `per line` entry:

```dart
      if (layer.blend != SceneBlendMode.normal)
        _blendLabel(layer.blend).toLowerCase(),
```

- [ ] **Step 4: Run it to see it pass**

Run: `cd app && fvm flutter test test/scene/scene_layer_list_test.dart test/material_drift_test.dart`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
fvm dart tool/prepare_submit.dart
git add app/lib/src/scene/ui/layer_list.dart app/test/scene/scene_layer_list_test.dart
git commit -m "Scene inspector: a blend picker on each text layer

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Verify the whole, and open one PR

- [ ] **Step 1: Format, analyze, test**

```bash
fvm dart tool/prepare_submit.dart
fvm flutter analyze
cd app && fvm flutter test test/scene test/scene_bridge_test.dart test/material_drift_test.dart
```

Expected: no formatter diff, no analyzer issues, all tests PASS. Paste the failing output into the PR rather than claiming green if any is red.

- [ ] **Step 2: Update the master plan**

In `docs/superpowers/specs/2026-09-05-scene-master-plan.md`, under **M10b**, append a dated line (2026-09-10) saying what landed — radial and sweep gradients, a pass laid across each line, blend modes, the inspector's paint editor — and that shaders are Phase 3 of `docs/superpowers/plans/2026-09-10-scene-text-layer-gradients.md`. Commit it with the code it describes.

- [ ] **Step 3: Check the text for names**

`git log master..HEAD` and `git diff master...HEAD` must name no client, their repository, people or product. Fix before pushing, not after.

- [ ] **Step 4: Open the PR** — only when the user asks for it. Suggested title: `Scene: gradients and blend modes on text layers, editable in the inspector`. Body: the design decisions above in two lines each, the before/after `sceneLayers` screenshots, and the fixed three-colour bug called out on its own.

---

# Phase 3 — Shader paint (design, then its own plan)

This phase is written down now so the phases before it keep its door open, and so its plan starts from measurements rather than guesses. **It does not start until Phases 1–2 are merged**, and it begins with a spike whose answers decide the plan.

### The shape already decided

- **A shader is one more `ScenePaint`, not a new kind of pass:** `ShaderPaint('shaders/foil.frag', uniforms: {'uAngle': 0.4, 'uTint': [1, 0.8, 0.2]})`. Because it sits in `TextLayer.paint`, strokes, blur, offsets, `box` and `blend` all compose with it for free — a foil stroke under a plasma fill is two passes.
- **Uniforms by name.** The pinned SDK has `FragmentShader.getUniformFloat(name)` and `getUniformVec2/3/4(name)`, so the file names uniforms the way the `.frag` does, never by slot index. The model holds `Map<String, List<double>>` (a float is a list of one); the file may spell a float bare.
- **Three uniforms the renderer supplies**, set only when the shader declares them: `uSize` (the box that `box` picks — the whole text or one line — so per-line works exactly as it does for gradients, through the same mask path), `uColor` (the text's own colour, so a shader can respect the stack's "no paint" convention), `uTime` (scene time in seconds — not the wall clock — so a shader animates with the motion runtime and a reel renders the same frame twice).
- **It is raster in any vector export.** `lib/src/render/` already reports `unresolvedShader`; scene export is raster today (master plan §6).
- **A filter shader (`ImageFilter.shader`) is deferred** until an effect needs to read the glyphs' pixels — bevel, chrome, displacement. It is Impeller-only (the SDK throws otherwise) and costs an offscreen layer per pass.

### The spike: five questions, each answered by a measurement

1. **Does a `TextStyle.foreground` paint carrying a `FragmentShader` render text?** On the macOS guest (Impeller) and on `flutter_tester` (the reels and video lane). Put a two-uniform `.frag` in `examples/example`, declare it under `flutter: shaders:`, paint a pass with it, and screenshot both lanes.
2. **Does editing a `.frag` reach the scene guest by reload, or only by rebuild?** Time both.
3. **Where does a capture wait for async work?** `FragmentProgram.fromAsset` is async and the painter is synchronous; a capture that settles before the program has loaded ships a frame without it — the same race that produced a black phone in previews. Name the hook each lane settles on (previews, scene export, reels) that a program load can register with.
4. **How does scene time reach a text pass?** `LayeredText` receives no clock today; find the motion runtime's time at `view.dart`'s text case and decide how it travels (an argument, or an inherited clock).
5. **Can the inspector list a shader's uniforms?** Name lookup is public; enumeration is not (`FragmentProgram._uniformInfo` is private). Either read the compiled asset's reflection data app-side, or require a declaration beside the shader (name, min, max, default — like a run knob). Decide on what reading the asset costs.

The spike's output is `docs/superpowers/plans/<date>-scene-shader-paint.md`, in this document's format, with these five answers in its design section.
