import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/services/headless_skill_runner.dart';
import 'package:pro_orc/data/services/skill_run_reconciler.dart';

String _fixture(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', 'fake_claude_cli', name);

String _watchdogScript() =>
    p.join(Directory.current.path, 'scripts', 'skill_watchdog.sh');

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('Condition not met within $timeout');
}

SkillRunTableData _buildRow({
  required int pid,
  required DateTime processStartTime,
  String id = 'run-1',
  String folderId = 'proj-a',
  String skillId = 'a1-progress',
  String status = 'running',
  String outputFilePath = '/tmp/out.log',
}) {
  return SkillRunTableData(
    id: id,
    folderId: folderId,
    skillId: skillId,
    pid: pid,
    processStartTime: processStartTime,
    startedAt: processStartTime,
    status: status,
    completedAt: null,
    outputFilePath: outputFilePath,
  );
}

void main() {
  group('SkillRunReconciler', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reconciler_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('live match: a real still-running process with matching PID + start '
        'time reconciles as stillRunning', () async {
      final runner = HeadlessSkillRunner(
        claudeExecutable: _fixture('claude_hang'),
        watchdogScriptPath: _watchdogScript(),
        outputDirectory: tempDir.path,
        timeout: const Duration(seconds: 10),
      );

      final spawnResult = await runner.start(
        projectPath: tempDir.path,
        skillId: 'a1-progress',
        skillPrompt: 'status check',
      );

      final row = _buildRow(
        pid: spawnResult.pid,
        processStartTime: spawnResult.processStartTime,
      );

      const reconciler = SkillRunReconciler();
      final outcome = await reconciler.reconcile(row);

      expect(outcome.stillRunning, isTrue);
      expect(outcome.resolvedTerminalStatus, isNull);

      // Cleanup: kill the process this test spawned so it doesn't outlive
      // the test (its own 10s watchdog timeout would also eventually
      // reap it, but end the test promptly).
      Process.killPid(spawnResult.pid, ProcessSignal.sigkill);
      await _waitUntil(() async => !await isProcessAlive(spawnResult.pid));
    });

    test('PID gone: a persisted row referencing a PID that no longer exists '
        'reconciles to a terminal status', () async {
      const reconciler = SkillRunReconciler();
      final row = _buildRow(
        pid: 999999, // astronomically unlikely to exist
        processStartTime: DateTime.now(),
      );

      final outcome = await reconciler.reconcile(row);

      expect(outcome.stillRunning, isFalse);
      expect(outcome.resolvedTerminalStatus, isNotNull);
    });

    test('PID reuse (core guard): a PID that exists but whose start time does '
        'not match the persisted value is never treated as live, and no '
        'signal is ever sent to the unrelated process', () async {
      // Use this test process's OWN pid as the "currently exists" process
      // — it is real and definitely alive, but was NOT started by this
      // test's fabricated row, so its real start time will not match the
      // row's fabricated (wrong) processStartTime.
      final unrelatedPid = pid;
      final realStartTime = await readProcessStartTime(unrelatedPid);
      expect(realStartTime, isNotNull);

      // Fabricate a processStartTime far from the real one — guarantees a
      // mismatch regardless of the reconciler's tolerance window.
      final wrongStartTime = realStartTime!.subtract(const Duration(days: 1));

      const reconciler = SkillRunReconciler();
      final row = _buildRow(
        pid: unrelatedPid,
        processStartTime: wrongStartTime,
      );

      final outcome = await reconciler.reconcile(row);

      expect(outcome.stillRunning, isFalse);
      expect(outcome.resolvedTerminalStatus, isNotNull);

      // The unrelated process (this very test process) must still be
      // alive — the reconciler must never signal/kill a PID-reuse
      // mismatch. If reconcile() had (incorrectly) sent a kill signal to
      // `unrelatedPid`, this test process itself would already be dead
      // and this assertion (indeed, the rest of the test run) would
      // never execute — the strongest possible proof no signal was sent.
      expect(await isProcessAlive(unrelatedPid), isTrue);
    });

    test('start-time tolerance absorbs sub-second truncation without '
        'weakening the PID-reuse guard', () async {
      final unrelatedPid = pid;
      final realStartTime = await readProcessStartTime(unrelatedPid);
      expect(realStartTime, isNotNull);

      // Within the default 1s tolerance — should still match.
      final almostSameTime = realStartTime!.add(
        const Duration(milliseconds: 500),
      );

      const reconciler = SkillRunReconciler();
      final row = _buildRow(
        pid: unrelatedPid,
        processStartTime: almostSameTime,
      );

      final outcome = await reconciler.reconcile(row);

      expect(outcome.stillRunning, isTrue);
    });
  });
}
