import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/vault_status_writer.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';

/// Records every call and returns a pre-programmed [VaultWriteResult]
/// without touching disk — the "fake writer via constructor injection or a
/// test seam" the wave plan calls for.
class _FakeVaultStatusWriter implements VaultStatusWriter {
  final List<Map<String, Object?>> calls = [];
  VaultWriteResult nextResult = VaultWriteResult.created;
  Completer<void>? blockUntil;

  @override
  Future<VaultWriteResult> write({
    required String vaultRoot,
    required String hubFolder,
    required String hubSlug,
    required String displayName,
    required VaultStatusFields fields,
  }) async {
    calls.add({
      'vaultRoot': vaultRoot,
      'hubFolder': hubFolder,
      'hubSlug': hubSlug,
      'displayName': displayName,
      'status': fields.status,
    });
    if (blockUntil != null) await blockUntil!.future;
    return nextResult;
  }
}

ProjectModel _project(
  String folderId, {
  int progress = 40,
  bool activePhase = true,
  DateTime? lastCommitDate,
}) {
  // checkedTasks/totalTasks drives A1Data.overallProgress — vary
  // checkedTasks by [progress] (0-100, in steps of 10 against a 10-task
  // total) so callers can produce genuinely different computed tuples
  // (e.g. progress: 40 vs progress: 55 must NOT collapse to the same
  // A1Phase.progress, otherwise the FR-012 value-equality gate under test
  // would trivially never see a "changed" tuple).
  final totalTasks = 10;
  final checkedTasks = (progress / 10).round().clamp(0, totalTasks);
  return ProjectModel(
    folderId: folderId,
    displayName: folderId,
    path: '/tmp/$folderId',
    a1: A1Data(
      phases: [
        A1Phase(
          name: 'Phase 1',
          checkedTasks: activePhase ? checkedTasks : totalTasks,
          totalTasks: totalTasks,
          planPath: '/tmp/$folderId/.a1/phases/p1/PLAN.md',
        ),
      ],
    ),
    git: lastCommitDate == null
        ? null
        : GitData(lastCommitDate: lastCommitDate),
  );
}

void main() {
  late AppDatabase db;
  late Directory vaultDir;
  late _FakeVaultStatusWriter fakeWriter;
  late DateTime fakeNow;
  late ProviderContainer container;

  DateTime clock() => fakeNow;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vaultDir = await Directory.systemTemp.createTemp('vault_status_test_');
    await db.setVaultDir(vaultDir.path);
    fakeWriter = _FakeVaultStatusWriter();
    fakeNow = DateTime.utc(2026, 8, 23, 12, 0, 0);

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        vaultStatusWriterProvider.overrideWithValue(fakeWriter),
        vaultClockProvider.overrideWithValue(clock),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await vaultDir.delete(recursive: true);
  });

  VaultStatusNotifier notifier() =>
      container.read(vaultStatusProvider.notifier);

  group('value-equality gate (FR-012)', () {
    test(
      'two consecutive syncIfDue calls with an unchanged tuple write once',
      () async {
        final project = _project('proj-a');

        await notifier().syncIfDue(project);
        await notifier().syncIfDue(project);

        expect(fakeWriter.calls.length, equals(1));
      },
    );

    test('a changed tuple after the debounce interval writes again', () async {
      final project = _project('proj-a', progress: 40);
      await notifier().syncIfDue(project);
      expect(fakeWriter.calls.length, equals(1));

      fakeNow = fakeNow.add(const Duration(minutes: 16));
      final changed = _project('proj-a', progress: 55);
      await notifier().syncIfDue(changed);

      expect(fakeWriter.calls.length, equals(2));
    });
  });

  group('debounce interval (FR-012/SC-008)', () {
    test(
      'changed tuple but only 5 minutes since last write: no write',
      () async {
        final project = _project('proj-a', progress: 40);
        await notifier().syncIfDue(project);
        expect(fakeWriter.calls.length, equals(1));

        fakeNow = fakeNow.add(const Duration(minutes: 5));
        final changed = _project('proj-a', progress: 55);
        await notifier().syncIfDue(changed);

        expect(
          fakeWriter.calls.length,
          equals(1),
          reason: 'Debounce interval (15min) not yet elapsed — must not write.',
        );
      },
    );

    test('changed tuple after 16 minutes: writes', () async {
      final project = _project('proj-a', progress: 40);
      await notifier().syncIfDue(project);
      expect(fakeWriter.calls.length, equals(1));

      fakeNow = fakeNow.add(const Duration(minutes: 16));
      final changed = _project('proj-a', progress: 55);
      await notifier().syncIfDue(changed);

      expect(fakeWriter.calls.length, equals(2));
    });
  });

  group('Archiv exclusion (FR-013)', () {
    test('a project in the Archiv group: syncIfDue is a no-op', () async {
      await db.setProjectGroup('archived-proj', kArchiveGroupId);
      final project = _project('archived-proj');

      await notifier().syncIfDue(project);

      expect(fakeWriter.calls, isEmpty);
    });

    test('a project in the Archiv group: syncNow is also a no-op', () async {
      await db.setProjectGroup('archived-proj', kArchiveGroupId);
      final project = _project('archived-proj');

      final result = await notifier().syncNow(project);

      expect(fakeWriter.calls, isEmpty);
      expect(result, isNot(equals(VaultWriteResult.written)));
      expect(result, isNot(equals(VaultWriteResult.created)));
    });

    test(
      'Archiv exclusion applies even with no existing hub (no auto-create)',
      () async {
        await db.setProjectGroup('archived-proj', kArchiveGroupId);
        final project = _project('archived-proj');

        await notifier().syncIfDue(project);
        await notifier().syncNow(project);

        expect(fakeWriter.calls, isEmpty);
        final hubFile = File(
          p.join(vaultDir.path, 'project', 'archived-proj.md'),
        );
        expect(hubFile.existsSync(), isFalse);
      },
    );
  });

  group('manual bypass (US-010-5)', () {
    test(
      'syncNow writes even 1 minute after a prior automatic write',
      () async {
        final project = _project('proj-a', progress: 40);
        await notifier().syncIfDue(project);
        expect(fakeWriter.calls.length, equals(1));

        fakeNow = fakeNow.add(const Duration(minutes: 1));
        final result = await notifier().syncNow(project);

        expect(fakeWriter.calls.length, equals(2));
        expect(result, equals(VaultWriteResult.created));
      },
    );
  });

  group('per-project serialization', () {
    test(
      'two concurrent syncNow calls for the same project write once',
      () async {
        final project = _project('proj-a');
        fakeWriter.blockUntil = Completer<void>();

        final first = notifier().syncNow(project);
        // Give the first call a chance to register itself as in-flight before
        // firing the second — both are still awaiting the writer's Future.
        await Future.delayed(Duration.zero);
        final second = notifier().syncNow(project);

        fakeWriter.blockUntil!.complete();
        final results = await Future.wait([first, second]);

        expect(fakeWriter.calls.length, equals(1));
        // The short-circuited call must not silently claim success.
        expect(
          results.where((r) => r == VaultWriteResult.created).length,
          equals(1),
        );
      },
    );

    test(
      'a concurrent syncNow for a DIFFERENT project proceeds independently',
      () async {
        final projectA = _project('proj-a');
        final projectB = _project('proj-b');
        fakeWriter.blockUntil = Completer<void>();

        final callA = notifier().syncNow(projectA);
        await Future.delayed(Duration.zero);
        // proj-b is not blocked by proj-a's in-flight write.
        fakeWriter.blockUntil!.complete();
        final resultB = await notifier().syncNow(projectB);
        await callA;

        expect(resultB, equals(VaultWriteResult.created));
        expect(fakeWriter.calls.length, equals(2));
      },
    );
  });

  group('vault unreachable (FR-016)', () {
    test(
      'syncIfDue skips without throwing when the vault root does not exist',
      () async {
        await db.setVaultDir(p.join(vaultDir.path, 'does-not-exist'));
        final project = _project('proj-a');

        await notifier().syncIfDue(project);

        expect(fakeWriter.calls, isEmpty);
      },
    );

    test(
      'syncNow skips without throwing when the vault root does not exist',
      () async {
        await db.setVaultDir(p.join(vaultDir.path, 'does-not-exist'));
        final project = _project('proj-a');

        final result = await notifier().syncNow(project);

        expect(fakeWriter.calls, isEmpty);
        expect(result, equals(VaultWriteResult.skippedIoError));
      },
    );
  });

  group('soft-fail passthrough (FR-017)', () {
    test('a skippedLocked result does not update vaultLastSyncAt', () async {
      fakeWriter.nextResult = VaultWriteResult.skippedLocked;
      final project = _project('proj-a');

      await notifier().syncIfDue(project);

      expect(await db.getVaultLastSyncAt('proj-a'), isNull);
    });

    test(
      'a skippedLocked result does not throw and allows a retry next tick',
      () async {
        fakeWriter.nextResult = VaultWriteResult.skippedLocked;
        final project = _project('proj-a', progress: 40);

        await notifier().syncIfDue(project);
        expect(fakeWriter.calls.length, equals(1));

        // Same tuple, same tick window — since vaultLastSyncAt was never set,
        // and the tuple was never recorded as "written", the next regular
        // trigger retries independently (no special-cased backoff).
        fakeWriter.nextResult = VaultWriteResult.created;
        await notifier().syncIfDue(project);

        expect(fakeWriter.calls.length, equals(2));
      },
    );
  });

  group('no hub deletion on Archiv move (FR-021)', () {
    test(
      'moving a project into Archiv after a write leaves the hub untouched',
      () async {
        final project = _project('proj-a');
        await notifier().syncNow(project);
        expect(fakeWriter.calls.length, equals(1));

        await db.setProjectGroup('proj-a', kArchiveGroupId);
        await notifier().syncIfDue(project);
        await notifier().syncNow(project);

        // No further writer calls after the move into Archiv.
        expect(fakeWriter.calls.length, equals(1));
      },
    );
  });

  group('auto-create vs. confirmation-pending', () {
    test(
      'no existing hub and no fuzzy candidate: auto-creates using the folderId',
      () async {
        final project = _project('brand-new-project');

        final result = await notifier().syncNow(project);

        expect(result, equals(VaultWriteResult.created));
        expect(fakeWriter.calls.single['hubSlug'], equals('brand-new-project'));
      },
    );

    test('a confirmed hub link is used without re-suggesting', () async {
      await db.setVaultHubSlug('proj-a', 'confirmed-hub-slug');
      final project = _project('proj-a');

      final result = await notifier().syncNow(project);

      expect(result, equals(VaultWriteResult.created));
      expect(fakeWriter.calls.single['hubSlug'], equals('confirmed-hub-slug'));
    });

    test(
      'an unconfirmed fuzzy candidate is NOT auto-written to — no write happens',
      () async {
        final hubDir = Directory(p.join(vaultDir.path, 'project'));
        await hubDir.create(recursive: true);
        await File(
          p.join(hubDir.path, 'proj-a-legacy.md'),
        ).writeAsString('---\n---\n');

        final project = _project('proj-a');
        final result = await notifier().syncNow(project);

        expect(fakeWriter.calls, isEmpty);
        expect(result, isNot(equals(VaultWriteResult.created)));
        expect(result, isNot(equals(VaultWriteResult.written)));
      },
    );
  });
}
