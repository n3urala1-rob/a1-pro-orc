import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/headless_skill_runner.dart';
import 'package:pro_orc/data/services/skill_notification_service.dart';
import 'package:pro_orc/data/services/vault_record_writer.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/skill_run_provider.dart';

/// Fake [HeadlessSkillRunner] — never spawns a real process. Returns a
/// pre-programmed [SpawnResult] and lets the test control when/how the
/// "process" exits by writing/removing a real backing file at [pidToUse]
/// via the OS's own liveness check would be too heavy; instead this fake's
/// paired [_FakeProcessLiveness] override (via [isProcessAliveOverride] in
/// the notifier under test) drives completion deterministically.
class _FakeHeadlessSkillRunner extends HeadlessSkillRunner {
  _FakeHeadlessSkillRunner() : super();

  int startCalls = 0;
  SpawnResult Function()? nextResult;
  Object? throwOnStart;

  @override
  Future<SpawnResult> start({
    required String projectPath,
    required String skillId,
    required String skillPrompt,
  }) async {
    startCalls++;
    if (throwOnStart != null) throw throwOnStart!;
    return nextResult!();
  }
}

class _FakeVaultRecordWriter implements VaultRecordWriter {
  final List<Map<String, Object?>> calls = [];

  @override
  Future<VaultRecordWriteResult> write({
    required String vaultRoot,
    required String projectHubSlug,
    required String skillSlug,
    required String skillDisplayName,
    required String outcome,
    required String bodyContent,
    required DateTime completedAt,
  }) async {
    calls.add({
      'vaultRoot': vaultRoot,
      'projectHubSlug': projectHubSlug,
      'skillSlug': skillSlug,
      'outcome': outcome,
    });
    return const VaultRecordWriteResult.written('/tmp/fake-record.md');
  }
}

class _FakeNotificationPlugin implements NotificationPlugin {
  final List<String?> titles = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> requestPermissions() async => true;

  @override
  Future<void> show({required int id, String? title, String? body}) async {
    titles.add(title);
  }
}

void main() {
  late AppDatabase db;
  late Directory vaultDir;
  late Directory tempOutputDir;
  late _FakeHeadlessSkillRunner fakeRunner;
  late _FakeVaultRecordWriter fakeVaultWriter;
  late _FakeNotificationPlugin fakeNotificationPlugin;
  late ProviderContainer container;

  ProjectModel project(String folderId) => ProjectModel(
    folderId: folderId,
    displayName: folderId,
    path: '/tmp/$folderId',
  );

  /// A [SpawnResult] pointing at a PID that is already guaranteed not to
  /// exist — same astronomically-unlikely-PID convention the reconciler
  /// test uses — so `_awaitCompletionAndFinalize`'s `isProcessAlive` poll
  /// resolves on its very first check instead of the test needing to wait
  /// out anything close to a real skill run's duration.
  SpawnResult alreadyExitedFakeResult(String outputFilePath) {
    return SpawnResult(
      pid: 999998,
      processStartTime: DateTime.now(),
      outputFilePath: outputFilePath,
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vaultDir = await Directory.systemTemp.createTemp('skill_run_vault_test_');
    tempOutputDir = await Directory.systemTemp.createTemp(
      'skill_run_output_test_',
    );
    await db.setVaultDir(vaultDir.path);

    fakeRunner = _FakeHeadlessSkillRunner();
    fakeVaultWriter = _FakeVaultRecordWriter();
    fakeNotificationPlugin = _FakeNotificationPlugin();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        headlessSkillRunnerProvider.overrideWithValue(fakeRunner),
        vaultRecordWriterProvider.overrideWithValue(fakeVaultWriter),
        skillNotificationServiceProvider.overrideWithValue(
          SkillNotificationService(plugin: fakeNotificationPlugin),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await vaultDir.delete(recursive: true);
    await tempOutputDir.delete(recursive: true);
  });

  SkillRunNotifier notifier() => container.read(skillRunProvider.notifier);

  Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await Future.delayed(const Duration(milliseconds: 20));
    }
    throw TimeoutException('Condition not met within $timeout');
  }

  group('start', () {
    test(
      'a successful start persists a running row and returns started',
      () async {
        final outputFile = p.join(tempOutputDir.path, 'out.log');
        fakeRunner.nextResult = () => SpawnResult(
          pid: 999999, // never actually polled to exit in this test
          processStartTime: DateTime.now(),
          outputFilePath: outputFile,
        );

        final result = await notifier().start(
          project('proj-a'),
          'a1-progress',
          'status check',
        );

        expect(result.started, isTrue);
        final row = await db.getSkillRun('proj-a', 'a1-progress');
        expect(row, isNotNull);
        expect(row!.status, equals('running'));

        final key = skillRunKey('proj-a', 'a1-progress');
        expect(container.read(skillRunProvider).inFlightKeys, contains(key));
      },
    );

    test('start rejected at the per-project limit — second skill for the '
        'same project is rejected, runner invoked only once', () async {
      final outputFile = p.join(tempOutputDir.path, 'out.log');
      fakeRunner.nextResult = () => SpawnResult(
        pid: 999999,
        processStartTime: DateTime.now(),
        outputFilePath: outputFile,
      );

      final first = await notifier().start(
        project('proj-a'),
        'a1-progress',
        'status check',
      );
      final second = await notifier().start(
        project('proj-a'),
        'a1-checklist',
        'checklist run',
      );

      expect(first.started, isTrue);
      expect(
        second.outcome,
        equals(StartSkillOutcome.rejectedConcurrencyLimit),
      );
      expect(fakeRunner.startCalls, equals(1));
    });

    test('CLI missing surfaces as claudeNotAvailable and frees the '
        'concurrency slot', () async {
      fakeRunner.throwOnStart = const ClaudeNotAvailableException();

      final result = await notifier().start(
        project('proj-a'),
        'a1-progress',
        'status check',
      );

      expect(result.outcome, equals(StartSkillOutcome.claudeNotAvailable));

      // The slot was freed — a subsequent start for the same project is
      // not blocked by the failed attempt.
      fakeRunner.throwOnStart = null;
      final outputFile = p.join(tempOutputDir.path, 'out2.log');
      fakeRunner.nextResult = () => SpawnResult(
        pid: 999999,
        processStartTime: DateTime.now(),
        outputFilePath: outputFile,
      );
      final second = await notifier().start(
        project('proj-a'),
        'a1-progress',
        'status check',
      );
      expect(second.started, isTrue);
    });

    test('vault write happens only after completion, not at start', () async {
      final outputFile = p.join(tempOutputDir.path, 'out.log');
      fakeRunner.nextResult = () => alreadyExitedFakeResult(outputFile);

      await notifier().start(project('proj-a'), 'a1-progress', 'x');

      // Immediately after start() returns, before the completion loop
      // has had a chance to observe the (already-exited) PID as dead.
      expect(fakeVaultWriter.calls, isEmpty);

      await waitUntil(() => fakeVaultWriter.calls.isNotEmpty);
      expect(fakeVaultWriter.calls, hasLength(1));
    });
  });

  group('cancel', () {
    test(
      'cancel updates status to cancelled, clears in-flight, notifies once',
      () async {
        final outputFile = p.join(tempOutputDir.path, 'out.log');
        // A genuinely long-lived process so cancel() has something real to
        // kill and the completion-poll loop does not race it to 'success'
        // first.
        final proc = await Process.start('sleep', ['30']);
        addTearDown(() => proc.kill(ProcessSignal.sigkill));

        fakeRunner.nextResult = () => SpawnResult(
          pid: proc.pid,
          processStartTime: DateTime.now(),
          outputFilePath: outputFile,
        );

        await notifier().start(project('proj-a'), 'a1-progress', 'x');
        await notifier().cancel('proj-a', 'a1-progress');

        final row = await db.getSkillRun('proj-a', 'a1-progress');
        expect(row!.status, equals('cancelled'));

        final key = skillRunKey('proj-a', 'a1-progress');
        expect(
          container.read(skillRunProvider).inFlightKeys,
          isNot(contains(key)),
        );
        expect(fakeNotificationPlugin.titles, hasLength(1));
      },
    );
  });

  group('startup reconciliation', () {
    test('a running DB row whose PID no longer exists reconciles to a '
        'terminal status and notifies once', () async {
      await db.upsertSkillRun(
        SkillRunTableCompanion.insert(
          id: 'stale-run',
          folderId: 'proj-a',
          skillId: 'a1-progress',
          pid: 999999,
          processStartTime: DateTime.now(),
          startedAt: DateTime.now(),
          status: 'running',
          outputFilePath: p.join(tempOutputDir.path, 'stale.log'),
        ),
      );

      final freshContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          headlessSkillRunnerProvider.overrideWithValue(fakeRunner),
          vaultRecordWriterProvider.overrideWithValue(fakeVaultWriter),
          skillNotificationServiceProvider.overrideWithValue(
            SkillNotificationService(plugin: fakeNotificationPlugin),
          ),
        ],
      );
      addTearDown(freshContainer.dispose);

      // Trigger build() by reading the provider.
      freshContainer.read(skillRunProvider);

      await waitUntil(() => fakeNotificationPlugin.titles.isNotEmpty);

      final row = await db.getSkillRun('proj-a', 'a1-progress');
      expect(row!.status, isNot(equals('running')));
      expect(fakeNotificationPlugin.titles, hasLength(1));

      final key = skillRunKey('proj-a', 'a1-progress');
      expect(
        freshContainer.read(skillRunProvider).inFlightKeys,
        isNot(contains(key)),
      );
    });
  });
}
