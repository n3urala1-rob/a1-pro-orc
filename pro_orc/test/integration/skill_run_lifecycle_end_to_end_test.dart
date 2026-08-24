/// Wave 6 end-to-end integration test (011-skill-buttons-headless).
///
/// Proves the full chain composes correctly across Waves 1-4: a real
/// [AppDatabase] (Wave 1 schema/accessors), the real [HeadlessSkillRunner]
/// + `scripts/skill_watchdog.sh` (Wave 2, spawning the fake `claude_hang`
/// fixture — never the real CLI), the real [SkillRunReconciler] (Wave 3),
/// and the real [SkillRunNotifier] (Wave 4) — with only
/// [appDatabaseProvider] overridden (an in-memory DB instead of a real
/// SQLite file) and the notification/vault-writer providers overridden
/// with lightweight fakes purely to avoid touching the real OS notification
/// center / filesystem outside the test's own temp dirs, matching the
/// "override only what must not touch the real world" discipline the Wave
/// 5 vault E2E test established.
///
/// Covers exactly the one scenario no single wave's isolated tests can
/// exercise: reconciliation across a SIMULATED app restart — constructing a
/// fresh [SkillRunNotifier]/[ProviderContainer] pair against the SAME
/// underlying DB (never calling `cancel()` on the still-running process in
/// between) and confirming it correctly re-attaches to a still-live run, or
/// finalizes a run that finished (or was killed) while "the app was
/// closed".
library;

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
import 'package:pro_orc/data/services/skill_run_reconciler.dart';
import 'package:pro_orc/data/services/vault_record_writer.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/skill_run_provider.dart';

String _fixture(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', 'fake_claude_cli', name);

String _watchdogScript() =>
    p.join(Directory.current.path, 'scripts', 'skill_watchdog.sh');

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future.delayed(const Duration(milliseconds: 30));
  }
  throw TimeoutException('Condition not met within $timeout');
}

/// Records notification calls without touching the real OS notification
/// center — the one substitution this E2E test makes purely to keep CI
/// clean, mirroring the Wave 5 vault E2E test's "override only what must
/// not touch the real world" precedent (there: the writer stayed real, only
/// appDatabaseProvider was swapped for an in-memory DB).
class _RecordingNotificationPlugin implements NotificationPlugin {
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
  group('Skill run lifecycle end-to-end (Waves 1-4 composed)', () {
    late AppDatabase db;
    late Directory tempDir;
    late Directory vaultDir;
    late _RecordingNotificationPlugin notificationPlugin;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('skill_run_e2e_test_');
      vaultDir = await Directory.systemTemp.createTemp('skill_run_e2e_vault_');
      await db.setVaultDir(vaultDir.path);
      notificationPlugin = _RecordingNotificationPlugin();
    });

    tearDown(() async {
      await db.close();
      await tempDir.delete(recursive: true);
      await vaultDir.delete(recursive: true);
    });

    ProviderContainer buildContainer({
      Duration watchdogTimeout = const Duration(seconds: 10),
    }) {
      return ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          headlessSkillRunnerProvider.overrideWithValue(
            HeadlessSkillRunner(
              claudeExecutable: _fixture('claude_hang'),
              watchdogScriptPath: _watchdogScript(),
              outputDirectory: tempDir.path,
              timeout: watchdogTimeout,
            ),
          ),
          skillRunReconcilerProvider.overrideWithValue(
            const SkillRunReconciler(),
          ),
          vaultRecordWriterProvider.overrideWithValue(VaultRecordWriter()),
          skillNotificationServiceProvider.overrideWithValue(
            SkillNotificationService(plugin: notificationPlugin),
          ),
        ],
      );
    }

    test('app-quit-and-relaunch: a fresh notifier re-attaches to a still-'
        'running process persisted by a prior notifier instance', () async {
      // "App session 1": start a long-running fake claude_hang process
      // (10-minute watchdog timeout, well outside this test's runtime) and
      // let it be persisted to the DB.
      final container1 = buildContainer(
        watchdogTimeout: const Duration(seconds: 30),
      );
      final notifier1 = container1.read(skillRunProvider.notifier);
      final project = ProjectModel(
        folderId: 'pro-orc-e2e',
        displayName: 'Pro Orc E2E',
        path: tempDir.path,
      );

      await notifier1.start(project, 'a1-progress', '/a1-progress');

      final persistedRow = await db.getSkillRun('pro-orc-e2e', 'a1-progress');
      expect(persistedRow, isNotNull);
      expect(persistedRow!.status, equals('running'));

      // "App quits": dispose the first container WITHOUT ever calling
      // cancel() — the underlying process (per FR-009, this is exactly
      // the non-regression guarantee this feature relies on) keeps
      // running detached, untouched by the notifier's own teardown.
      container1.dispose();
      expect(await isProcessAlive(persistedRow.pid), isTrue);

      // "App relaunches": a brand-new container/notifier pair against the
      // SAME underlying DB — build() triggers startup reconciliation.
      final container2 = buildContainer(
        watchdogTimeout: const Duration(seconds: 30),
      );
      addTearDown(container2.dispose);
      // Force build() to run and its unawaited reconciliation to
      // complete.
      container2.read(skillRunProvider);
      await _waitUntil(() async {
        final key = skillRunKey('pro-orc-e2e', 'a1-progress');
        return container2.read(skillRunProvider).inFlightKeys.contains(key);
      });

      final state = container2.read(skillRunProvider);
      final key = skillRunKey('pro-orc-e2e', 'a1-progress');
      expect(
        state.inFlightKeys,
        contains(key),
        reason:
            'A still-running process must be re-attached as running, '
            'not silently dropped or marked terminal.',
      );
      expect(state.lastRunByKey[key]?.status, equals('running'));

      // Cleanup: kill the still-running process this test spawned.
      Process.killPid(persistedRow.pid, ProcessSignal.sigkill);
      await _waitUntil(() async => !await isProcessAlive(persistedRow.pid));
    });

    test('app-quit-and-relaunch: a fresh notifier finalizes a run whose '
        'process was killed externally while the app was closed', () async {
      final container1 = buildContainer(
        watchdogTimeout: const Duration(seconds: 30),
      );
      final notifier1 = container1.read(skillRunProvider.notifier);
      final project = ProjectModel(
        folderId: 'pro-orc-e2e-2',
        displayName: 'Pro Orc E2E 2',
        path: tempDir.path,
      );

      await notifier1.start(project, 'a1-checklist', '/a1-checklist');

      final persistedRow = await db.getSkillRun(
        'pro-orc-e2e-2',
        'a1-checklist',
      );
      expect(persistedRow, isNotNull);

      container1.dispose();

      // Simulate the process having been killed while "the app was
      // closed" (e.g. externally, or by the watchdog's own timeout —
      // covered separately below) — before the fresh notifier ever
      // reconciles it.
      Process.killPid(persistedRow!.pid, ProcessSignal.sigkill);
      await _waitUntil(() async => !await isProcessAlive(persistedRow.pid));

      final container2 = buildContainer();
      addTearDown(container2.dispose);
      container2.read(skillRunProvider);

      await _waitUntil(() async => notificationPlugin.titles.isNotEmpty);

      final key = skillRunKey('pro-orc-e2e-2', 'a1-checklist');
      final state = container2.read(skillRunProvider);
      expect(state.inFlightKeys, isNot(contains(key)));

      final finalizedRow = await db.getSkillRun(
        'pro-orc-e2e-2',
        'a1-checklist',
      );
      expect(finalizedRow!.status, isNot(equals('running')));

      // Exactly one notification fired for this first-time-observed
      // terminal outcome (no re-notify path is reachable, since a
      // terminal row is never returned by getAllRunningSkillRuns again).
      expect(notificationPlugin.titles, hasLength(1));

      // A record/-note was written for the finalized run (FR-012, real
      // VaultRecordWriter — not faked in this E2E test).
      final recordDir = Directory(p.join(vaultDir.path, 'record'));
      expect(await recordDir.exists(), isTrue);
      final recordFiles = await recordDir.list().toList();
      expect(recordFiles, isNotEmpty);
    });

    test('10-minute-timeout-survives-quit: a hung run is terminated by the '
        'process-level watchdog even though no notifier/app process is '
        'alive to observe it', () async {
      // Short but not razor-thin — see the same lesson in
      // headless_skill_runner_test.dart: start() itself spawns a real
      // `which claude` subprocess plus a PID-file poll before the
      // watchdog is even launched, so a too-tight timeout can race that
      // overhead and make this test flaky rather than actually testing
      // the watchdog's kill behavior.
      final container = buildContainer(
        watchdogTimeout: const Duration(seconds: 2),
      );
      final notifier = container.read(skillRunProvider.notifier);
      final project = ProjectModel(
        folderId: 'pro-orc-e2e-3',
        displayName: 'Pro Orc E2E 3',
        path: tempDir.path,
      );

      await notifier.start(project, 'a1-progress', '/a1-progress');
      final row = await db.getSkillRun('pro-orc-e2e-3', 'a1-progress');
      expect(row, isNotNull);
      expect(await isProcessAlive(row!.pid), isTrue);

      // Simulate "Pro Orc has already quit" — dispose the container (no
      // notifier alive to poll/observe anything) BEFORE the watchdog
      // timeout elapses.
      container.dispose();

      // Wait past the short injected timeout — the watchdog script
      // itself (not any Dart process) must SIGKILL the child.
      await _waitUntil(
        () async => !await isProcessAlive(row.pid),
        timeout: const Duration(seconds: 10),
      );

      expect(await isProcessAlive(row.pid), isFalse);
    });
  });
}
