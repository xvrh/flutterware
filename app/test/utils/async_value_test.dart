import 'package:flutter_test/flutter_test.dart';
import 'package:flutterware_app/src/utils/async_value.dart';

void main() {
  group('laziness', () {
    test('constructing loads nothing', () async {
      var loads = 0;
      AsyncValue<int>(
        loader: () async {
          loads++;
          return 1;
        },
      );
      await pumpEventQueue();
      expect(loads, 0);
    });

    test('reading value loads nothing', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        loader: () async {
          loads++;
          return 1;
        },
      );

      expect(source.value.isLoading, isTrue);
      expect(source.value.hasData, isFalse);
      await pumpEventQueue();
      expect(loads, 0, reason: 'a pure read must never start work');
    });

    test('the first subscriber starts the load', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        loader: () async {
          loads++;
          return 7;
        },
      );

      var subscription = source.listen((_) {});
      await pumpEventQueue();

      expect(loads, 1);
      expect(source.value.data, 7);
      await subscription.cancel();
    });

    test('a second subscriber does not reload', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        loader: () async {
          loads++;
          return 7;
        },
      );

      var a = source.listen((_) {});
      var b = source.listen((_) {});
      await pumpEventQueue();

      expect(loads, 1);
      await a.cancel();
      await b.cancel();
    });

    test('re-subscribing keeps the cached value and does not reload', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        loader: () async {
          loads++;
          return 7;
        },
      );

      await source.listen((_) {}).cancel();
      await pumpEventQueue();
      expect(loads, 1);

      // What `DependenciesPlugin.untrack` then `track` does: demand says what
      // work is justified, not what must be discarded.
      var again = source.listen((_) {});
      await pumpEventQueue();
      expect(loads, 1, reason: 'the value was already loaded');
      expect(source.value.data, 7);
      await again.cancel();
    });

    test('lazy: false loads without any subscriber', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        lazy: false,
        loader: () async {
          loads++;
          return 3;
        },
      );
      await pumpEventQueue();
      expect(loads, 1);
      expect(source.value.data, 3);
    });

    test('a seed is the value, and suppresses the load', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        seed: 42,
        loader: () async {
          loads++;
          return 1;
        },
      );

      expect(source.value.data, 42);
      var subscription = source.listen((_) {});
      await pumpEventQueue();
      expect(loads, 0);
      await subscription.cancel();
    });
  });

  group('snapshots', () {
    test('a subscriber sees loading then data', () async {
      var source = AsyncValue<int>(loader: () async => 5);
      var seen = <Snapshot<int>>[];
      var subscription = source.listen(seen.add);
      await pumpEventQueue();

      expect(seen.first.isLoading, isTrue);
      expect(seen.last.data, 5);
      await subscription.cancel();
    });

    test('a failing loader produces an error snapshot, not a throw', () async {
      var source = AsyncValue<int>(
        loader: () async => throw const FormatException('nope'),
      );

      var subscription = source.listen((_) {});
      await pumpEventQueue();

      expect(source.value.hasError, isTrue);
      expect(source.value.error, isFormatException);
      await subscription.cancel();
    });

    test('refresh reloads and republishes', () async {
      var next = 1;
      var source = AsyncValue<int>(loader: () async => next++);

      var subscription = source.listen((_) {});
      await pumpEventQueue();
      expect(source.value.data, 1);

      await source.refresh();
      expect(source.value.data, 2);
      await subscription.cancel();
    });

    test('refresh with LoadingMode.none keeps the old data visible', () async {
      var next = 1;
      var source = AsyncValue<int>(loader: () async => next++);
      var subscription = source.listen((_) {});
      await pumpEventQueue();

      var seen = <Snapshot<int>>[];
      var watcher = source.listen(seen.add);
      await source.refresh(mode: LoadingMode.none);

      expect(
        seen.every((s) => s.hasData),
        isTrue,
        reason: 'no empty loading frame should have been published',
      );
      await subscription.cancel();
      await watcher.cancel();
    });

    test('update publishes without loading', () async {
      var source = AsyncValue<int>(loader: () async => 1, seed: 0);
      source.update(9);
      expect(source.value.data, 9);
    });

    test('invalidate is a no-op until something has loaded', () async {
      var loads = 0;
      var source = AsyncValue<int>(
        loader: () async {
          loads++;
          return 1;
        },
      );

      source.invalidate();
      await pumpEventQueue();
      expect(loads, 0);

      var subscription = source.listen((_) {});
      await pumpEventQueue();
      source.invalidate();
      await pumpEventQueue();
      expect(loads, 2);
      await subscription.cancel();
    });
  });

  test('a Disposable value is disposed when replaced', () async {
    var disposed = <int>[];
    var next = 0;
    var source = AsyncValue<_Resource>(
      loader: () async => _Resource(next++, disposed.add),
    );

    var subscription = source.listen((_) {});
    await pumpEventQueue();
    expect(disposed, isEmpty);

    await source.refresh();
    expect(disposed, [0], reason: 'the replaced resource is released');
    await subscription.cancel();
  });
}

class _Resource implements Disposable {
  _Resource(this.id, this.onDispose);

  final int id;
  final void Function(int id) onDispose;

  @override
  void dispose() => onDispose(id);
}
