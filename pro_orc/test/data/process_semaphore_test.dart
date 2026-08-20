import 'dart:async';

import 'package:test/test.dart';

import 'package:pro_orc/data/services/process_runner.dart';

void main() {
  group('ProcessSemaphore', () {
    test('never lets more than maxConcurrent bodies run at once', () async {
      final semaphore = ProcessSemaphore(maxConcurrent: 4);
      var current = 0;
      var maxObserved = 0;

      Future<void> body() async {
        current++;
        if (current > maxObserved) maxObserved = current;
        // Yield control so overlapping calls actually interleave instead of
        // running to completion synchronously before the next one starts.
        await Future.delayed(const Duration(milliseconds: 20));
        current--;
      }

      // Simulate the process_scanner.dart burst: many more calls than the
      // limit, all fired at once via Future.wait (root cause 1's exact
      // shape — 45 repos x 2 sequential git calls = 90 concurrent spawns).
      await Future.wait(List.generate(40, (_) => semaphore.run(body)));

      expect(maxObserved, lessThanOrEqualTo(4));
      expect(semaphore.running, equals(0));
    });

    test('queued waiters still all complete', () async {
      final semaphore = ProcessSemaphore(maxConcurrent: 2);
      final completedOrder = <int>[];

      await Future.wait(
        List.generate(
          10,
          (i) => semaphore.run(() async {
            await Future.delayed(const Duration(milliseconds: 5));
            completedOrder.add(i);
          }),
        ),
      );

      expect(completedOrder.length, equals(10));
      expect(completedOrder.toSet().length, equals(10)); // no duplicates
    });

    test('a body that throws still releases its slot', () async {
      final semaphore = ProcessSemaphore(maxConcurrent: 1);

      await expectLater(
        semaphore.run(() async => throw Exception('boom')),
        throwsException,
      );

      // If the slot wasn't released, this would hang forever (timeout fails
      // the test) rather than complete.
      var ran = false;
      await semaphore.run(() async => ran = true);
      expect(ran, isTrue);
    });
  });

  group('runProcessWithTimeout with an injected semaphore', () {
    test(
      'caps real concurrent process spawns at the semaphore limit',
      () async {
        final semaphore = ProcessSemaphore(maxConcurrent: 3);
        var maxObserved = 0;

        // Poll semaphore.running (incremented only once a body actually
        // starts executing, i.e. after the gate let it through) rather than
        // a counter incremented before the gate — that would count queued
        // callers too, not just running ones.
        final pollSub = Stream<void>.periodic(const Duration(milliseconds: 5))
            .listen((_) {
              if (semaphore.running > maxObserved) {
                maxObserved = semaphore.running;
              }
            });

        await Future.wait(
          List.generate(
            12,
            (_) => runProcessWithTimeout(
              'sleep',
              ['0.1'],
              '.',
              semaphore: semaphore,
            ),
          ),
        );

        await pollSub.cancel();

        expect(maxObserved, lessThanOrEqualTo(3));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
