// The parameter doors: declare, rename, retype, delete, set the mockup, and
// connect a property to a parameter. Every refusal here is a file that would
// not have compiled.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/scene_authoring.dart';
import 'package:flutterware_app/src/scene/editor.dart';
import 'package:flutterware_app/src/scene/fixtures.dart';
import 'package:flutterware_app/src/scene/motion_file.dart';
import 'package:flutterware_app/src/scene/scene_file.dart';

const _source =
    '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card({
  final String title = 'Hello',
  final SceneColor accent = const SceneColor(0xFF112233),
}) extends SceneDefinition {
  late final headline = TextNode(title, fontSize: 20, color: accent);
  late final box = FrameNode(x: 40, width: 80, height: 20, fill: accent);
  @override
  late final root = FrameNode(width: 200, height: 100, children: [headline, box]);
}
''';

SceneEditor open() => SceneEditor(parseSceneFile(_source).doc!);

String emit(SceneEditor e) => emitSceneFile(e.doc, className: 'Card');

void main() {
  visibleTests();
  listTests();
  motionKeyTests();
  asideTests();
  drawerTests();
  nestedArgTests();
  test("add declares a parameter at the kind's zero, or a chosen mockup", () {
    var e = open();
    e.addParam('slide', SceneParamKind.number);
    e.addParam('cta', SceneParamKind.string, defaultValue: 'Go');
    expect(e.doc.paramNamed('slide')!.defaultValue, 0.0);
    expect(emit(e), contains("final String cta = 'Go'"));
    expect(emit(e), contains('final double slide = 0'));
  });

  test('a name a node or parameter already has is refused', () {
    var e = open();
    expect(() => e.addParam('box', SceneParamKind.number), throwsArgumentError);
    expect(
      () => e.addParam('title', SceneParamKind.number),
      throwsArgumentError,
    );
    expect(
      () => e.addParam('1bad', SceneParamKind.number),
      throwsArgumentError,
    );
    expect(e.freeParamName('title'), 'title2');
  });

  test('rename follows every reader', () {
    var e = open();
    e.renameParam('accent', 'tint');
    var box = e.doc.nodeNamed('box')!;
    var headline = e.doc.nodeNamed('headline')!;
    expect(box.bindings['fill'], const ParamRef('tint'));
    expect(headline.bindings['color'], const ParamRef('tint'));
    var out = emit(e);
    expect(out, contains('final SceneColor tint'));
    expect(out, contains('fill: tint'));
    expect(out, isNot(contains('accent')));
    expect(parseSceneFile(out).refusals, isEmpty);
  });

  test('setting the mockup reaches every reader', () {
    var e = open();
    e.setParamDefault('accent', const SceneColor(0xFFABCDEF));
    expect(e.doc.nodeNamed('box')!.fill, const SceneColor(0xFFABCDEF));
    expect(
      (e.doc.nodeNamed('headline')! as TextNode).color,
      const SceneColor(0xFFABCDEF),
    );
    expect(() => e.setParamDefault('accent', 'red'), throwsArgumentError);
  });

  test('delete and retype refuse while something reads the parameter', () {
    var e = open();
    expect(() => e.deleteParam('accent'), throwsArgumentError);
    expect(
      () => e.retypeParam('accent', SceneParamKind.string),
      throwsArgumentError,
    );
    expect(e.readersOf('accent').map((r) => '${r.$1.name}.${r.$2}'), [
      'headline.color',
      'box.fill',
    ]);
    e.unbind(e.doc.nodeNamed('headline')!, 'color');
    e.unbind(e.doc.nodeNamed('box')!, 'fill');
    e.retypeParam('accent', SceneParamKind.string);
    expect(e.doc.paramNamed('accent')!.kind, SceneParamKind.string);
    e.deleteParam('accent');
    expect(e.doc.paramNamed('accent'), isNull);
    // The values stayed where they were.
    expect(e.doc.nodeNamed('box')!.fill, const SceneColor(0xFF112233));
  });

  test("bind takes the parameter's default and refuses a kind mismatch", () {
    var e = open();
    var box = e.doc.nodeNamed('box')!;
    e.addParam('slide', SceneParamKind.number, defaultValue: 24.0);
    e.bind(box, 'x', 'slide');
    expect(box.x, 24);
    expect(box.bindings['x'], const ParamRef('slide'));
    expect(() => e.bind(box, 'x', 'title'), throwsArgumentError);
    expect(() => e.bind(box, 'layout', 'slide'), throwsArgumentError);
    expect(emit(e), contains('x: slide'));
  });

  test('promote makes a parameter of the value a property holds', () {
    var e = open();
    var box = e.doc.nodeNamed('box')!;
    var name = e.promote(box, 'x');
    expect(name, 'x');
    expect(e.doc.paramNamed('x')!.defaultValue, 40.0);
    expect(box.bindings['x'], const ParamRef('x'));
    var out = emit(e);
    expect(out, contains('final double x = 40'));
    expect(out, contains('x: x'));
    expect(parseSceneFile(out).refusals, isEmpty);
    // One undo entry takes both the declaration and the binding back.
    e.undo();
    expect(e.doc.paramNamed('x'), isNull);
    expect(box.bindings.containsKey('x'), isFalse);
    expect(box.x, 40);
  });

  test('move reorders the constructor', () {
    var e = open();
    e.moveParam('accent', 0);
    expect(e.doc.params.map((p) => p.name), ['accent', 'title']);
    expect(emit(e), matches(RegExp(r'accent.*\n.*title', dotAll: false)));
  });
}

void visibleTests() {
  const source =
      '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Card({final bool showFooter = true}) extends SceneDefinition {
  late final body = TextNode('Body', fontSize: 20);
  late final footer = TextNode('Footer', fontSize: 12, visible: showFooter);
  late final hidden = FrameNode(width: 10, height: 10, visible: false);
  @override
  late final root = FrameNode(
    width: 200,
    height: 100,
    layout: NodeLayout.column,
    children: [body, footer, hidden],
  );
}
''';

  group('visible', () {
    test('round-trips, literal and bound to a bool parameter', () {
      var parsed = parseSceneFile(source);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var doc = parsed.doc!;
      var footer = doc.nodeNamed('footer')!;
      var hidden = doc.nodeNamed('hidden')!;
      expect(footer.visible, isTrue);
      expect(footer.bindings['visible'], const ParamRef('showFooter'));
      expect(hidden.visible, isFalse);
      expect(doc.paramNamed('showFooter')!.kind, SceneParamKind.bool);
      var out = emitSceneFile(doc, className: 'Card');
      expect(out, contains('final bool showFooter = true'));
      expect(out, contains('visible: showFooter'));
      expect(out, contains('visible: false'));
      expect(emitSceneFile(parseSceneFile(out).doc!, className: 'Card'), out);
    });

    test(
      'an argument hides the node; hiding a bound node flips the default',
      () {
        var doc = parseSceneFile(source).doc!..applyArgs({'showFooter': false});
        expect(doc.nodeNamed('footer')!.visible, isFalse);

        var e = SceneEditor(parseSceneFile(source).doc!);
        var footer = e.doc.nodeNamed('footer')!;
        e.perform('Hide', () => footer.visible = false);
        expect(e.doc.paramNamed('showFooter')!.defaultValue, false);
        expect(emit(e), contains('final bool showFooter = false'));
      },
    );

    test('a hidden node keeps no rect and is not hit', () {
      var doc = parseSceneFile(source).doc!;
      var hidden = doc.nodeNamed('hidden')!
        ..measured = const SceneRect(0, 0, 10, 10);
      expect(doc.hitDeep(5, 5), isNull);
      hidden.visible = false;
      expect(hidden.measured, isNull);
    });

    test('promote and the toggle kind', () {
      var e = SceneEditor(parseSceneFile(source).doc!);
      var body = e.doc.nodeNamed('body')!;
      expect(e.promote(body, 'visible', name: 'showBody'), 'showBody');
      expect(e.doc.paramNamed('showBody')!.defaultValue, true);
      e.setParamDefault('showBody', false);
      expect(body.visible, isFalse);
      e.setVisible(true);
      expect(body.visible, isFalse, reason: 'nothing selected, nothing done');
      e.select(body);
      e.setVisible(true);
      expect(body.visible, isTrue);
      expect(e.doc.paramNamed('showBody')!.defaultValue, true);
    });
  });
}

void listTests() {
  group('list parameters', () {
    SceneEditor repeated() {
      var cell = TextNode('Espresso', name: 'cell')
        ..bindings['text'] = const ItemRef('lines', 'item');
      var qty = TextNode('12', name: 'qty')
        ..bindings['text'] = const ItemRef('lines', 'qty');
      var row = FrameNode(name: 'row', layout: NodeLayout.row)
        ..children.addAll([cell, qty]);
      recordRepeat(row, 'lines');
      var root = FrameNode(name: 'root', layout: NodeLayout.column)
        ..width = 400
        ..height = 300
        ..children.add(row);
      var doc = SceneDocument(root)
        ..params.add(
          SceneParamDecl('lines', SceneParamKind.list, <SceneItem>[
            {'item': 'Espresso', 'qty': 12.0},
            {'item': 'Filter', 'qty': 3.0},
          ]),
        );
      bindRepeats(doc);
      return SceneEditor(doc);
    }

    test('setting the items redraws the repeat and rewrites the first row', () {
      var e = repeated();
      e.setParamDefault('lines', <SceneItem>[
        {'item': 'Latte', 'qty': 7.0},
        {'item': 'Filter', 'qty': 3.0},
        {'item': 'Mocha', 'qty': 1.0},
      ]);
      var row = e.doc.nodeNamed('row')! as FrameNode;
      expect((row.children[0] as TextNode).text, 'Latte');
      expect((row.children[1] as TextNode).text, '7');
      expect(e.doc.expand(row).length, 3);
      e.undo();
      expect((row.children[0] as TextNode).text, 'Espresso');
      expect(e.doc.expand(row).length, 2);
    });

    test('a list cannot be bound to a property, or given a scalar', () {
      var e = repeated();
      expect(
        () => e.bind(e.doc.nodeNamed('cell')!, 'text', 'lines'),
        throwsArgumentError,
      );
      expect(() => e.setParamDefault('lines', 'x'), throwsArgumentError);
      expect(e.readersOf('lines').map((r) => '${r.$1.name}.${r.$2}'), [
        'cell.text',
        'qty.text',
        'row.repeat',
      ]);
      expect(() => e.deleteParam('lines'), throwsArgumentError);
    });

    test('rename follows the item bindings and the repeat', () {
      var e = repeated();
      e.renameParam('lines', 'rows');
      var row = e.doc.nodeNamed('row')! as FrameNode;
      expect(row.repeated!.source, 'rows');
      expect(
        e.doc.nodeNamed('cell')!.bindings['text'],
        const ItemRef('rows', 'item'),
      );
      expect(e.doc.expand(row).length, 2);
    });
  });
}

void motionKeyTests() {
  group('motion keys reading a parameter', () {
    test('an edit to the key moves the default and every other reader', () {
      var scene = coffeeBannerDraft();
      var motion = coffeeIntroDraft(scene);
      var e = SceneEditor(scene, motions: {'BannerIntro': motion});
      var key = motion
          .groupNamed('headlineIn')!
          .tracks['translateY']!
          .keys
          .first;
      expect(key.paramRef, 'slideFrom');
      e.perform('Edit key', () => key.value = 40.0);
      expect(motion.params.single.defaultValue, 40.0);
      expect(key.paramRef, 'slideFrom');
      var out = StringBuffer();
      emitMotionClass(out, motion, scene, className: 'BannerIntro');
      expect('$out', contains('final double slideFrom = 40'));
      expect('$out', contains('value: slideFrom'));
      e.undo();
      expect(motion.params.single.defaultValue, 24.0);
      expect(key.value, 24.0);
    });

    test('a key reading a parameter that is gone loses the reference', () {
      var scene = coffeeBannerDraft();
      var motion = coffeeIntroDraft(scene);
      motion.params.clear();
      expect(reconcileMotionBindings(motion), ['headlineIn.translateY']);
      var key = motion
          .groupNamed('headlineIn')!
          .tracks['translateY']!
          .keys
          .first;
      expect(key.paramRef, isNull);
      expect(key.value, 24.0);
    });
  });
}

void asideTests() {
  group('the outline selection', () {
    test(
      'a parameter or a motion is selected instead of a node, never with',
      () {
        var scene = coffeeBannerDraft();
        var e = SceneEditor(
          scene,
          motions: {'BannerIntro': coffeeIntroDraft(scene)},
        )..addParam('title', SceneParamKind.string, defaultValue: 'Hi');
        e.select(scene.nodeNamed('headline'));
        e.aside = const ParamAside('title');
        expect(e.aside, const ParamAside('title'));
        expect(e.selectedNodes, isEmpty);
        e.select(scene.nodeNamed('glow'));
        expect(e.aside, isNull);
        e.aside = const MotionAside('BannerIntro');
        expect(e.primary, isNull);
        e.clearSelection();
        expect(e.aside, isNull);
      },
    );

    test('the selection follows a rename and drops with a delete', () {
      var e = SceneEditor(coffeeBannerDraft())
        ..addParam('title', SceneParamKind.string)
        ..aside = const ParamAside('title');
      e.renameParam('title', 'heading');
      expect(e.aside, const ParamAside('heading'));
      e.deleteParam('heading');
      expect(e.aside, isNull);
    });

    test('a motion selection follows its rename too', () {
      var scene = coffeeBannerDraft();
      var e = SceneEditor(
        scene,
        motions: {'BannerIntro': coffeeIntroDraft(scene)},
      )..aside = const MotionAside('BannerIntro');
      e.renameMotion('BannerIntro', 'Intro');
      expect(e.aside, const MotionAside('Intro'));
      e.removeMotion('Intro');
      expect(e.aside, isNull);
    });
  });
}

void drawerTests() {
  group('the drawer holds one thing', () {
    SceneEditor withList() {
      var scene = coffeeBannerDraft();
      var e = SceneEditor(
        scene,
        motions: {'BannerIntro': coffeeIntroDraft(scene)},
      );
      e.addParam(
        'lines',
        SceneParamKind.list,
        defaultValue: <SceneItem>[
          {'item': 'Espresso', 'qty': 12.0},
        ],
      );
      return e;
    }

    test('opening a parameter closes the motion, and the other way round', () {
      var e = withList()..activeMotion = 'BannerIntro';
      expect(e.drawer, const MotionAside('BannerIntro'));
      e.openParam = 'lines';
      expect(e.drawer, const ParamAside('lines'));
      expect(e.activeMotion, isNull);
      e.activeMotion = 'BannerIntro';
      expect(e.openParam, isNull);
      expect(e.drawer, const MotionAside('BannerIntro'));
    });

    test('only a list parameter can be open, and it follows a rename', () {
      var e = withList()..addParam('title', SceneParamKind.string);
      e.openParam = 'title';
      expect(e.openParam, isNull, reason: 'a text has no table');
      e.openParam = 'lines';
      e.renameParam('lines', 'rows');
      expect(e.openParam, 'rows');
      expect(e.drawer, const ParamAside('rows'));
    });

    test('folding keeps it open; opening anything unfolds', () {
      var e = withList()..openParam = 'lines';
      e.drawerCollapsed = true;
      expect(e.drawer, const ParamAside('lines'));
      e.activeMotion = 'BannerIntro';
      expect(e.drawerCollapsed, isFalse);
    });
  });
}

void nestedArgTests() {
  group('a parent parameter reaches a nested argument', () {
    SceneDocument badge() {
      var text = TextNode('New', name: 'text')
        ..bindings['text'] = const ParamRef('label');
      var root = FrameNode(name: 'root', layout: NodeLayout.row)
        ..width = 96
        ..height = 32
        ..children.add(text);
      return SceneDocument(root)
        ..params.add(SceneParamDecl('label', SceneParamKind.string, 'New'));
    }

    SceneEditor host() {
      var scene = coffeeBannerDraft();
      var promo = SceneRefNode.read('PromoBadge', name: 'promo')
        ..instance = instantiateScene(badge(), {});
      scene.root.children.add(promo);
      return SceneEditor(scene)
        ..addParam('title', SceneParamKind.string, defaultValue: 'Hello');
    }

    test('bind writes the parent default into the argument', () {
      var e = host();
      var promo = e.doc.nodeNamed('promo')! as SceneRefNode;
      expect(bindableKind(promo, 'args.label'), SceneParamKind.string);
      e.bind(promo, 'args.label', 'title');
      expect(promo.args['label'], 'Hello');
      expect(promo.bindings['args.label'], const ParamRef('title'));
      // The argument follows the parameter, and an edit to the argument
      // moves the parameter — the same rule as any bound property.
      e.setParamDefault('title', 'Hi');
      expect(promo.args['label'], 'Hi');
      e.perform('Edit', () => promo.args['label'] = 'Yo');
      expect(e.doc.paramNamed('title')!.defaultValue, 'Yo');
      expect(() => e.bind(promo, 'args.label', 'slide'), throwsArgumentError);
    });

    test('promote makes a parameter of an argument at the child default', () {
      var e = host();
      var promo = e.doc.nodeNamed('promo')! as SceneRefNode;
      expect(e.promote(promo, 'args.label'), 'label');
      expect(e.doc.paramNamed('label')!.defaultValue, 'New');
      expect(promo.args['label'], 'New');
      expect(promo.bindings['args.label'], const ParamRef('label'));
    });

    test('the file spells the reference, and drops const for it', () {
      var source =
          '''
$sceneFileMarker
import 'package:flutterware/scene_authoring.dart';

class Host({final String title = 'Hello'}) extends SceneDefinition {
  late final promo = SceneRefNode(PromoBadgeArgs(label: title), x: 10, y: 10);
  late final other = SceneRefNode(const PromoBadgeArgs(label: 'Fixed'), x: 10, y: 60);
  @override
  late final root = FrameNode(width: 200, height: 100, children: [promo, other]);
}
''';
      var parsed = parseSceneFile(source);
      expect(parsed.refusals, isEmpty, reason: parsed.refusals.join('\n'));
      var doc = parsed.doc!;
      var promo = doc.nodeNamed('promo')! as SceneRefNode;
      expect(promo.args['label'], 'Hello');
      expect(promo.bindings['args.label'], const ParamRef('title'));
      var other = doc.nodeNamed('other')! as SceneRefNode;
      expect(other.bindings, isEmpty);
      var out = emitSceneFile(doc, className: 'Host');
      expect(out, contains('PromoBadgeArgs(label: title)'));
      expect(out, isNot(contains('const PromoBadgeArgs(label: title)')));
      expect(out, contains("const PromoBadgeArgs(label: 'Fixed')"));
      expect(emitSceneFile(parseSceneFile(out).doc!, className: 'Host'), out);
    });
  });
}
