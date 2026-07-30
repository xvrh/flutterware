import 'package:flutter/widgets.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware/ui_catalog.dart';

Widget _wrap(Widget child) => Center(child: child);

/// A project-defined annotation, which `Demo` being `base` rather than `final`
/// is what allows.
base class _Tablet extends Demo {
  const _Tablet({super.name})
    : super(formFactor: FormFactor.desktop, id: 'tablet');
}

void main() {
  test('Demo is a Preview', () {
    expect(const Demo(name: 'x'), isA<Preview>());
  });

  test('group defaults to the sentinel that triggers derivation', () {
    expect(const Demo(name: 'x').group, 'Default');
  });

  test('no formFactor leaves size null for the project default to fill', () {
    expect(const Demo(name: 'x').transform().size, isNull);
  });

  test('formFactor supplies the size through transform()', () {
    expect(
      const Demo(name: 'x', formFactor: FormFactor.desktop).transform().size,
      const Size(1440, 900),
    );
    expect(
      const Demo(name: 'x', formFactor: FormFactor.mobile).transform().size,
      const Size(390, 844),
    );
  });

  test('an explicit size wins over formFactor', () {
    expect(
      const Demo(
        name: 'x',
        size: Size(100, 200),
        formFactor: FormFactor.desktop,
      ).transform().size,
      const Size(100, 200),
    );
  });

  test('FormFactor.all states no size opinion', () {
    expect(
      const Demo(name: 'x', formFactor: FormFactor.all).transform().size,
      isNull,
    );
  });

  test('inherited fields survive the toBuilder/build round trip', () {
    var preview = const Demo(
      name: 'Empty',
      group: 'Member list view',
      textScaleFactor: 2,
      wrapper: _wrap,
      brightness: Brightness.dark,
    ).transform();

    expect(preview.name, 'Empty');
    expect(preview.group, 'Member list view');
    expect(preview.textScaleFactor, 2);
    expect(preview.wrapper, same(_wrap));
    expect(preview.brightness, Brightness.dark);
  });

  test('transform() drops id, figma and formFactor', () {
    const demo = Demo(name: 'x', id: 'stable', figma: 'node-id=1:234');
    var preview = demo.transform();

    expect(preview, isNot(isA<Demo>()));
    expect(demo.id, 'stable');
    expect(demo.figma, 'node-id=1:234');
  });

  test('a project subclass is legal and transforms', () {
    const tablet = _Tablet(name: 'On a tablet');

    expect(tablet, isA<Demo>());
    expect(tablet.id, 'tablet');
    expect(tablet.transform().size, const Size(1440, 900));
    expect(tablet.transform().name, 'On a tablet');
  });

  test('is usable in an annotation position', () {
    expect(annotated(), isA<Widget>());
  });
}

@Demo(name: 'Annotated', formFactor: FormFactor.desktop)
Widget annotated() => const SizedBox();
