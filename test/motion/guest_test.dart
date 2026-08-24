import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/motion.dart';

Duration ms(int value) => Duration(milliseconds: value);

Map<String, Object?> soleScope() {
  var scopes = MotionRegistry.instance.describe()['scopes']! as List<Object?>;
  expect(scopes, hasLength(1), reason: 'a previous test left a scope mounted');
  return scopes.single! as Map<String, Object?>;
}

List<Object?> targetsOf(Map<String, Object?> scope) =>
    scope['targets']! as List<Object?>;

Map<String, Object?> targetNamed(Map<String, Object?> scope, String name) =>
    targetsOf(scope)
        .cast<Map<String, Object?>>()
        .firstWhere((target) => target['name'] == name);

List<Object?> propertiesOf(Map<String, Object?> target) =>
    target['properties']! as List<Object?>;

Map<String, Object?> propertyNamed(Map<String, Object?> target, String name) =>
    propertiesOf(target)
        .cast<Map<String, Object?>>()
        .firstWhere((property) => property['name'] == name);

final _values = MotionValues(
  targets: {
    'title': {
      'opacity': [
        Seg<double>(
          start: ms(0),
          end: ms(400),
          from: 0,
          to: 1,
          curve: Curves.easeOutCubic,
        ),
      ],
    },
    // Tuned and never named by a build: the third state, and the one a panel
    // has to be able to show or nobody ever prunes anything.
    'ghost': {
      'color': [
        Seg<Color>(
          start: ms(0),
          end: ms(200),
          from: Color(0xFF102030),
          to: Color(0xFFA0B0C0),
        ),
      ],
    },
  },
);

void main() {
  group('the registry', () {
    testWidgets('a mounted scope describes itself', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) =>
              MotionBox(m.target('title'), child: const SizedBox(width: 10)),
        ),
      );

      var scope = soleScope();
      expect(scope['durationMs'], 400);
      expect(scope['progress'], 0);
      expect(scope['playing'], isFalse);
      expect(
        targetsOf(scope).cast<Map<String, Object?>>().map((t) => t['name']),
        ['ghost', 'title'],
      );
    });

    testWidgets('a target nobody named is still reported, and says so', (
      tester,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) => Opacity(
            opacity: m.target('title').opacity,
            child: const SizedBox(width: 10),
          ),
        ),
      );

      var scope = soleScope();
      expect(targetNamed(scope, 'title')['named'], isTrue);
      expect(targetNamed(scope, 'ghost')['named'], isFalse);
    });

    testWidgets('a property read but never tuned is reported as read', (
      tester,
    ) async {
      // The creation path: you write the read first, and the panel offers to
      // tune what it finds. Nothing in the values file mentions `translateY`.
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) =>
              SizedBox(width: 10, height: 20 + m.target('title').translateY),
        ),
      );

      var property = propertyNamed(
        targetNamed(soleScope(), 'title'),
        'translateY',
      );
      expect(property['read'], isTrue);
      expect(property['segments'], isEmpty);
    });

    testWidgets("a MotionBox's sweep is offered, never a property", (
      tester,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) =>
              MotionBox(m.target('title'), child: const SizedBox(width: 10)),
        ),
      );

      var target = targetNamed(soleScope(), 'title');
      expect(target['offered'], contains('blur'));
      // Eight swept properties would otherwise be eight empty lanes.
      expect(
        propertiesOf(target).cast<Map<String, Object?>>().map((p) => p['name']),
        ['opacity'],
      );
      expect(propertyNamed(target, 'opacity')['read'], isFalse);
    });

    testWidgets('a property a MotionBox applies is wired, not dead', (
      tester,
    ) async {
      // The bug the first live run of the transport had. `MotionBox` records
      // its sweep as offered rather than read, so a tuned property it applies
      // has `read: false` — and reading that as "nothing uses this" reported
      // seven of nine visibly animating targets as prunable.
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) =>
              MotionBox(m.target('title'), child: const SizedBox(width: 10)),
        ),
      );

      var opacity = propertyNamed(targetNamed(soleScope(), 'title'), 'opacity');
      expect(opacity['read'], isFalse);
      expect(opacity['offered'], isTrue);
      expect(opacity['state'], 'wired');
    });

    testWidgets('tuned and reached by nothing at all is dead', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) => const SizedBox(),
        ),
      );

      // Nobody named `ghost`, so nothing reads or offers its colour.
      var color = propertyNamed(targetNamed(soleScope(), 'ghost'), 'color');
      expect(color['state'], 'dead');
    });

    testWidgets('read but never tuned is the creation path', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) =>
              SizedBox(width: 10, height: 20 + m.target('title').translateY),
        ),
      );

      var target = targetNamed(soleScope(), 'title');
      expect(propertyNamed(target, 'translateY')['state'], 'untuned');
      // …and the one that is tuned but now reached by nothing is not dressed
      // up as anything else.
      expect(propertyNamed(target, 'opacity')['state'], 'dead');
    });

    testWidgets('values cross as two kinds and curves cross by name', (
      tester,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false, progress: 1),
          builder: (m) {
            m.target('title');
            m.target('ghost');
            return const SizedBox();
          },
        ),
      );

      var scope = soleScope();
      var opacity = propertyNamed(targetNamed(scope, 'title'), 'opacity');
      expect(opacity['value'], 1.0);
      expect(
        (opacity['segments']! as List<Object?>).single,
        containsPair('curve', 'easeOutCubic'),
      );

      var color = propertyNamed(targetNamed(scope, 'ghost'), 'color');
      expect(color['value'], {'color': 0xFFA0B0C0});
      // The default is `Curves.linear`, which has a name like any other.
      expect(
        (color['segments']! as List<Object?>).single,
        containsPair('curve', 'linear'),
      );
    });

    testWidgets('a curve with no standard name is left unnamed', (
      tester,
    ) async {
      // Absent rather than guessed at: a panel that showed the nearest name
      // would be lying about a curve somebody chose deliberately.
      await tester.pumpWidget(
        MotionScope(
          motion: MotionValues(
            targets: {
              'title': {
                'opacity': [
                  Seg<double>(
                    start: ms(0),
                    end: ms(100),
                    from: 0,
                    to: 1,
                    curve: Cubic(0.11, 0.83, 0.29, 0.47),
                  ),
                ],
              },
            },
          ),
          controller: MotionController(autoplay: false),
          builder: (m) => Opacity(
            opacity: m.target('title').opacity,
            child: const SizedBox(),
          ),
        ),
      );

      var opacity = propertyNamed(targetNamed(soleScope(), 'title'), 'opacity');
      expect(
        (opacity['segments']! as List<Object?>).single,
        isNot(contains('curve')),
      );
    });

    testWidgets('describing a scope does not make the panel look wired', (
      tester,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) {
            m.target('title');
            return const SizedBox();
          },
        ),
      );

      // `peek`, not `read`: asking twice must not turn an untouched property
      // into one the panel shows as reaching a widget.
      soleScope();
      soleScope();
      var target = targetNamed(soleScope(), 'title');
      expect(propertyNamed(target, 'opacity')['read'], isFalse);
    });

    testWidgets('one scope resolves without being named, two do not', (
      tester,
    ) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) => const SizedBox(),
        ),
      );
      expect(MotionRegistry.instance.resolve(null), isNotNull);
      expect(MotionRegistry.instance.resolve('nope'), isNull);

      await tester.pumpWidget(
        Row(
          textDirection: TextDirection.ltr,
          children: [
            MotionScope(
              motion: _values,
              controller: MotionController(autoplay: false),
              builder: (m) => const SizedBox(),
            ),
            MotionScope(
              motion: _values,
              controller: MotionController(autoplay: false),
              builder: (m) => const SizedBox(),
            ),
          ],
        ),
      );
      expect(MotionRegistry.instance.resolve(null), isNull);
      expect(MotionRegistry.instance.ids, hasLength(2));
    });

    testWidgets('an unmounted scope leaves the registry', (tester) async {
      await tester.pumpWidget(
        MotionScope(
          motion: _values,
          controller: MotionController(autoplay: false),
          builder: (m) => const SizedBox(),
        ),
      );
      expect(MotionRegistry.instance.ids, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(MotionRegistry.instance.ids, isEmpty);
    });
  });
}
