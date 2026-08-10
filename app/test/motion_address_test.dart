import 'package:flutterware_app/src/plugins/native/motion_address.dart';
import 'package:test/test.dart';

void main() {
  group('segments round-trip', () {
    void roundTrips(MotionPlace place, {String? t}) {
      var segments = motionSegments(
        place.package,
        file: place.file,
        motion: place.motion,
      );
      expect(motionPlace(segments, t: t), place, reason: '$segments t=$t');
    }

    test('a package alone', () {
      roundTrips(const MotionPlace('packages/app'));
    });

    test('a file, whose end is its .dart suffix', () {
      roundTrips(const MotionPlace('.', file: 'lib/screens/onboarding.dart'));
    });

    test('a motion inside a file', () {
      roundTrips(
        const MotionPlace(
          '.',
          file: 'lib/screens/onboarding.dart',
          motion: 'onboardingMotion',
        ),
      );
    });

    test('a playhead rides above the segments', () {
      roundTrips(
        const MotionPlace(
          'packages/app',
          file: 'lib/home.dart',
          motion: 'homeMotion',
          t: 0.42,
        ),
        t: '0.42',
      );
    });
  });

  group('reading an address', () {
    test('a tail with no .dart segment is the package', () {
      expect(
        motionPlace(['packages/app', 'nonsense']),
        const MotionPlace('packages/app'),
      );
    });

    test('trailing rubbish past the motion is ignored, not fatal', () {
      // Showing something beats showing nothing: a stale link should land you
      // on the motion it names.
      expect(
        motionPlace(['.', 'lib', 'home.dart', 'homeMotion', 'extra', 'more']),
        const MotionPlace('.', file: 'lib/home.dart', motion: 'homeMotion'),
      );
    });

    test('no t means "wherever the playhead was", not zero', () {
      // Defaulting to 0 would rewind the motion every time anybody opened a
      // link to it.
      expect(motionPlace(['.', 'lib/a.dart'])?.t, isNull);
    });

    test(
      'a t that is not a number in 0..1 loses the playhead, not the page',
      () {
        for (var bad in ['', 'soon', '-0.5', '1.5', 'NaN']) {
          var place = motionPlace(['.', 'lib', 'a.dart', 'aMotion'], t: bad);
          expect(place?.motion, 'aMotion', reason: bad);
          expect(place?.t, isNull, reason: bad);
        }
      },
    );

    test('nothing at all is nowhere', () {
      expect(motionPlace(const []), isNull);
    });
  });

  group('formatting t', () {
    test('is short enough to paste into a message', () {
      // 1/3 of a 700ms motion is 0.4166666666666667 before this.
      expect(formatMotionT(0.4166666666666667), '0.417');
    });

    test('keeps the ends readable rather than padded', () {
      expect(formatMotionT(0), '0');
      expect(formatMotionT(1), '1');
      expect(formatMotionT(0.5), '0.5');
      expect(formatMotionT(0.42), '0.42');
    });

    test('is absent when there is no playhead to state', () {
      expect(formatMotionT(null), isNull);
    });

    test('survives the round trip it exists for', () {
      for (var t in [0.0, 0.25, 0.417, 0.999, 1.0]) {
        expect(
          motionPlace(['.', 'a.dart', 'm'], t: formatMotionT(t))?.t,
          t,
          reason: '$t',
        );
      }
    });
  });
}
