import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/services/claude_detection_service.dart';
import 'package:pro_orc/data/services/headless_skill_runner.dart';

/// Absolute path to this repo's fake `claude` CLI fixtures — tests NEVER
/// invoke the real `claude` CLI. `Directory.current` is the package root
/// (`pro_orc/`) when `flutter test` runs.
String _fixture(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', 'fake_claude_cli', name);

String _watchdogScript() =>
    p.join(Directory.current.path, 'scripts', 'skill_watchdog.sh');

/// Returns true if a process with [pid] currently exists, via `ps -p`.
Future<bool> _isProcessAlive(int pid) async {
  final result = await Process.run('ps', ['-p', pid.toString()]);
  return result.exitCode == 0;
}

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future.delayed(pollInterval);
  }
  throw TimeoutException('Condition not met within $timeout');
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('headless_runner_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('HeadlessSkillRunner', () {
    test(
      'success path: spawns via the claude fixture and captures output',
      () async {
        final runner = HeadlessSkillRunner(
          claudeExecutable: _fixture('claude'),
          watchdogScriptPath: _watchdogScript(),
          outputDirectory: tempDir.path,
          timeout: const Duration(seconds: 5),
        );

        final result = await runner.start(
          projectPath: tempDir.path,
          skillId: 'a1-progress',
          skillPrompt: 'status check',
        );

        expect(result.pid, greaterThan(0));
        expect(
          result.processStartTime.difference(DateTime.now()).abs(),
          lessThan(const Duration(minutes: 1)),
        );

        // Wait for the watchdog+fixture to actually finish writing output —
        // the process is detached, so poll the output file rather than
        // awaiting a Process handle this test never held.
        final outputFile = File(result.outputFilePath);
        await _waitUntil(() async => outputFile.existsSync());
        await _waitUntil(() async {
          if (!outputFile.existsSync()) return false;
          final content = await outputFile.readAsString();
          return content.contains('FAKE_CLAUDE_SUCCESS');
        });

        final content = await outputFile.readAsString();
        expect(content, contains('FAKE_CLAUDE_SUCCESS'));

        // Give the detached watchdog a moment to fully exit before the
        // test's tearDown removes the temp dir it's writing into.
        await _waitUntil(
          () async => !await _isProcessAlive(result.pid),
          timeout: const Duration(seconds: 5),
        );
      },
    );

    test('argument-list only: a metacharacter-laden prompt is passed as a '
        'literal argument, never shell-evaluated', () async {
      final runner = HeadlessSkillRunner(
        claudeExecutable: _fixture('claude'),
        watchdogScriptPath: _watchdogScript(),
        outputDirectory: tempDir.path,
        timeout: const Duration(seconds: 5),
      );

      const dangerousPrompt = r'$(rm -rf /) `touch /tmp/pwned` ; echo hi';
      final result = await runner.start(
        projectPath: tempDir.path,
        skillId: 'a1-progress',
        skillPrompt: dangerousPrompt,
      );

      final outputFile = File(result.outputFilePath);
      await _waitUntil(() async {
        if (!outputFile.existsSync()) return false;
        final content = await outputFile.readAsString();
        return content.contains('ARG:');
      });

      final content = await outputFile.readAsString();
      // The fixture echoes argv verbatim — '-p' then the prompt. If the
      // value had been shell-evaluated, this literal string would never
      // appear (it would instead run rm/touch/echo and their output, if
      // any, would look nothing like this).
      expect(content, contains('ARG: -p'));
      expect(content, contains('ARG: $dangerousPrompt'));
      expect(File('/tmp/pwned').existsSync(), isFalse);

      await _waitUntil(
        () async => !await _isProcessAlive(result.pid),
        timeout: const Duration(seconds: 5),
      );
    });

    test('watchdog timeout kill: a hung run is SIGKILLed after the injected '
        'timeout elapses', () async {
      final runner = HeadlessSkillRunner(
        claudeExecutable: _fixture('claude_hang'),
        watchdogScriptPath: _watchdogScript(),
        outputDirectory: tempDir.path,
        // Short but not razor-thin: start() itself spawns a real `which
        // claude` subprocess (ClaudeDetectionService) before the watchdog
        // is even launched, so a too-tight timeout can race that
        // overhead and make the "confirm alive" assertion below flaky
        // rather than testing the watchdog's actual kill behavior.
        timeout: const Duration(seconds: 2),
      );

      final result = await runner.start(
        projectPath: tempDir.path,
        skillId: 'a1-progress',
        skillPrompt: 'status check',
      );

      // Confirm it's actually alive before asserting the kill.
      expect(await _isProcessAlive(result.pid), isTrue);

      // Outer test-level timeout guard: if the watchdog is broken and
      // never kills the child, this fails the test instead of hanging CI
      // indefinitely (the `test` package's own default test timeout is
      // the ultimate backstop, but this makes the failure mode explicit).
      await _waitUntil(
        () async => !await _isProcessAlive(result.pid),
        timeout: const Duration(seconds: 10),
      );

      expect(await _isProcessAlive(result.pid), isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('failure path: stderr is captured in the output file', () async {
      final runner = HeadlessSkillRunner(
        claudeExecutable: _fixture('claude_fail'),
        watchdogScriptPath: _watchdogScript(),
        outputDirectory: tempDir.path,
        timeout: const Duration(seconds: 5),
      );

      final result = await runner.start(
        projectPath: tempDir.path,
        skillId: 'a1-progress',
        skillPrompt: 'status check',
      );

      final outputFile = File(result.outputFilePath);
      await _waitUntil(() async {
        if (!outputFile.existsSync()) return false;
        final content = await outputFile.readAsString();
        return content.contains('FAKE_CLAUDE_FAILURE');
      });

      final content = await outputFile.readAsString();
      expect(content, contains('FAKE_CLAUDE_FAILURE: something went wrong'));

      await _waitUntil(
        () async => !await _isProcessAlive(result.pid),
        timeout: const Duration(seconds: 5),
      );
    });

    test('CLI missing: throws ClaudeNotAvailableException before spawning '
        'anything', () async {
      final runner = HeadlessSkillRunner(
        claudeExecutable: _fixture('claude'),
        watchdogScriptPath: _watchdogScript(),
        outputDirectory: tempDir.path,
        claudeDetectionService: const ClaudeDetectionService(
          whichCommand: 'which_nonexistent_binary_xyz',
        ),
      );

      await expectLater(
        runner.start(
          projectPath: tempDir.path,
          skillId: 'a1-progress',
          skillPrompt: 'status check',
        ),
        throwsA(isA<ClaudeNotAvailableException>()),
      );

      // No output file (and therefore no watchdog/claude process) was
      // ever created for this attempt.
      final entries = await tempDir.list().toList();
      final logFiles = entries.where((e) => e.path.endsWith('.log'));
      expect(logFiles, isEmpty);
    });

    test(
      'detached survives parent: the spawned process outlives this test '
      'holding no reference to the Process handle beyond SpawnResult',
      () async {
        final runner = HeadlessSkillRunner(
          claudeExecutable: _fixture('claude_hang'),
          watchdogScriptPath: _watchdogScript(),
          outputDirectory: tempDir.path,
          timeout: const Duration(seconds: 10),
        );

        final result = await runner.start(
          projectPath: tempDir.path,
          skillId: 'a1-progress',
          skillPrompt: 'status check',
        );

        // No Process object from Process.start is held anywhere beyond
        // what SpawnResult returned (which is just pid/time/path, not a
        // Process handle) — this is the structural proof that
        // ProcessStartMode.detached actually detaches on this OS/Dart
        // version, not just in theory. Wait past a normal GC/event-loop
        // tick to be sure nothing tears it down as a side effect.
        await Future.delayed(const Duration(milliseconds: 500));

        expect(await _isProcessAlive(result.pid), isTrue);

        // Clean up: this run's own 10s timeout will eventually kill it,
        // but end the test promptly and without leaking a process past
        // this test's lifetime.
        Process.killPid(result.pid, ProcessSignal.sigkill);
        await _waitUntil(
          () async => !await _isProcessAlive(result.pid),
          timeout: const Duration(seconds: 5),
        );
      },
    );
  });

  group('readProcessStartTime', () {
    test('returns a DateTime close to now for the current process', () async {
      final pid = pid_;
      final startTime = await readProcessStartTime(pid);
      expect(startTime, isNotNull);
      // The current test process started well before "now", but within a
      // generous window for a CI/dev machine.
      expect(
        DateTime.now().difference(startTime!),
        lessThan(const Duration(minutes: 10)),
      );
    });

    test('returns null for a PID that does not exist', () async {
      // A PID astronomically unlikely to exist on any real system.
      final startTime = await readProcessStartTime(999999);
      expect(startTime, isNull);
    });
  });
}

/// The current Dart process's own PID (top-level `pid` from dart:io,
/// aliased to avoid shadowing inside the nested test closures above).
int get pid_ => pid;
