/// Regression tests for [runProcessWithTimeout] / [killProcessTree]
/// (process-storm round 3, WP2).
///
/// The round-2 postmortem claimed a SIGKILL on the spawned process was
/// sufficient because "no intermediate shell" survives it. Round 3's
/// `kill_probe.dart` disproved that for commands that fork their own
/// children (a compound `sh -c 'child & wait'` command): `runInShell: true`
/// spawns an intermediate shell, and killing only that shell orphans any
/// grandchild it forked — relevant for `gh` (credential helpers) and
/// `vercel` (Node). These tests use a real spawned process (no mocking, per
/// project convention) to prove the whole tree is reaped, not just the
/// direct child.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:pro_orc/data/services/process_runner.dart';

/// True if any process matching [pattern] is currently running, via
/// `pgrep -f`.
Future<bool> _anyProcessMatches(String pattern) async {
  final result = await Process.run('pgrep', ['-f', pattern]);
  return result.exitCode == 0 &&
      (result.stdout as String).trim().isNotEmpty;
}

void main() {
  // Use a distinctive sleep duration as the pgrep match pattern so this
  // test can never collide with an unrelated sleep process on the machine.
  const marker = 'sleep 424242';

  tearDown(() async {
    // Best-effort cleanup in case a test fails before reaping.
    await Process.run('pkill', ['-f', marker]);
  });

  test(
    'runProcessWithTimeout kills the WHOLE process tree on timeout, not '
    'just the direct shell child — no orphaned grandchild survives',
    () async {
      expect(
        await _anyProcessMatches(marker),
        isFalse,
        reason: 'Precondition: no stray marker process from a prior run.',
      );

      final semaphore = ProcessSemaphore();
      await expectLater(
        runProcessWithTimeout(
          'sh',
          ['-c', '$marker & wait'],
          '.',
          timeout: const Duration(milliseconds: 500),
          semaphore: semaphore,
        ),
        throwsA(isA<TimeoutException>()),
      );

      // Give the kill + OS reap a moment to land.
      await Future.delayed(const Duration(milliseconds: 800));

      expect(
        await _anyProcessMatches(marker),
        isFalse,
        reason:
            'The grandchild sleep process forked by the compound `sh -c` '
            'command must not survive the timeout kill — a plain '
            'process.kill() on just the intermediate shell leaves it running '
            'as an orphan (round-3 kill_probe.dart finding).',
      );
    },
  );

  test(
    'killProcessTree kills a direct child and its own forked grandchild',
    () async {
      expect(await _anyProcessMatches(marker), isFalse);

      final process = await Process.start('sh', [
        '-c',
        '$marker & wait',
      ], runInShell: true);

      // Let the grandchild actually spawn before killing.
      await Future.delayed(const Duration(milliseconds: 300));
      expect(
        await _anyProcessMatches(marker),
        isTrue,
        reason: 'Precondition: the grandchild sleep should be running.',
      );

      await killProcessTree(process.pid);
      await Future.delayed(const Duration(milliseconds: 500));

      expect(await _anyProcessMatches(marker), isFalse);
    },
  );

  test(
    'a normal (non-forking) command still completes successfully — the '
    'tree-kill mechanism does not interfere with the happy path',
    () async {
      final semaphore = ProcessSemaphore();
      final result = await runProcessWithTimeout(
        'echo',
        ['hello from process_runner_test'],
        '.',
        semaphore: semaphore,
      );

      expect(result.exitCode, equals(0));
      expect(
        (result.stdout as String).trim(),
        equals('hello from process_runner_test'),
      );
    },
  );
}
