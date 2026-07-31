import 'package:flutterware/flutter_test.dart';
import 'package:flutterware/src/scenarios/profile.dart';

/// What one `flutter test` invocation declares: the profile's heads by
/// default, the request's lists when CI names them.
void main() {
  const phones = ScenarioProfile(
    'phones',
    devices: [Devices.iphone16, Devices.iphoneSe],
    languages: ['en', 'fr'],
  );

  test('the head of each axis is the default, and it is one pass', () {
    var assignments = scenarioAssignments(phones);

    expect(assignments, hasLength(1));
    expect(assignments.single.device, Devices.iphone16);
    expect(assignments.single.language, 'en');
  });

  test('no profile means no assignment at all — the bare test surface', () {
    var assignments = scenarioAssignments(null);

    expect(assignments, hasLength(1));
    expect(assignments.single.isEmpty, isTrue);
  });

  test('a profile with no languages leaves the platform locale alone', () {
    var assignments = scenarioAssignments(
      const ScenarioProfile('one', devices: [Devices.iphoneSe]),
    );

    expect(assignments.single.device, Devices.iphoneSe);
    expect(assignments.single.language, isNull);
  });

  test("CI's lists win over the profile, and cross", () {
    var assignments = scenarioAssignments(
      phones,
      devicesOverride: 'iphone-se,android-tall',
      languagesOverride: 'en,fr,de',
    );

    expect(assignments, hasLength(6));
    expect(assignments.map((a) => a.slug), [
      'iphone-se-en',
      'iphone-se-fr',
      'iphone-se-de',
      'android-tall-en',
      'android-tall-fr',
      'android-tall-de',
    ]);
  });

  test('one axis overridden leaves the other on its default', () {
    var assignments = scenarioAssignments(phones, languagesOverride: 'ja');

    expect(assignments.single.device, Devices.iphone16);
    expect(assignments.single.language, 'ja');
  });

  test('fit is a device: the bare surface, named', () {
    var assignments = scenarioAssignments(phones, devicesOverride: 'fit');

    expect(assignments.single.device, isNull);
    expect(assignments.single.language, 'en');
  });

  test('a device this build does not know is refused, not approximated', () {
    expect(
      () => scenarioAssignments(phones, devicesOverride: 'iphone-99'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '$e',
          'message',
          allOf(contains('no such device'), contains('iphone-se')),
        ),
      ),
    );
  });

  test('an assignment names itself for a path and for a test name', () {
    var assignment = ScenarioAssignment(
      device: Devices.iphone16,
      language: 'fr',
    );

    expect(assignment.slug, 'iphone-16-fr');
    expect(assignment.label, 'iPhone 16 · fr');
  });
}
