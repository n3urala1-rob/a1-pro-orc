import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';

void main() {
  group('AppDatabase vault sync settings', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('fresh install opens at schemaVersion 7', () async {
      expect(db.schemaVersion, equals(7));
    });

    test('fresh install has an empty skillRunTable', () async {
      final rows = await db.select(db.skillRunTable).get();
      expect(rows, isEmpty);
    });

    test('vaultHubFolder defaults to "project" when never set', () async {
      expect(await db.getVaultHubFolder(), equals('project'));
    });

    test(
      'vaultHubSlug and vaultLastSyncAt default to null for a new project',
      () async {
        expect(await db.getVaultHubSlug('never-seen'), isNull);
        expect(await db.getVaultLastSyncAt('never-seen'), isNull);
      },
    );

    test('setVaultHubFolder persists and round-trips via getConfig', () async {
      await db.setVaultHubFolder('research');
      expect(await db.getVaultHubFolder(), equals('research'));

      final config = await db.getConfig();
      expect(config.vaultHubFolder, equals('research'));
    });

    test('setVaultHubSlug persists and round-trips', () async {
      await db.setVaultHubSlug('my-proj', 'my-proj-hub');
      expect(await db.getVaultHubSlug('my-proj'), equals('my-proj-hub'));
    });

    test('setVaultHubSlug(folderId, null) clears the link', () async {
      await db.setVaultHubSlug('my-proj', 'my-proj-hub');
      await db.setVaultHubSlug('my-proj', null);
      expect(await db.getVaultHubSlug('my-proj'), isNull);
    });

    test('setVaultLastSyncAt round-trips a DateTime', () async {
      // Truncate to second precision: Drift's DateTimeColumn stores as a
      // unix timestamp (seconds), so sub-second precision does not survive
      // the round-trip — compare at the precision that is actually stored.
      final now = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
      ).toUtc();
      await db.setVaultLastSyncAt('my-proj', now);

      final stored = await db.getVaultLastSyncAt('my-proj');
      expect(stored, isNotNull);
      expect(stored!.toUtc().isAtSameMomentAs(now), isTrue);
    });

    test('setVaultLastSyncAt(folderId, null) clears the timestamp', () async {
      await db.setVaultLastSyncAt('my-proj', DateTime.now());
      await db.setVaultLastSyncAt('my-proj', null);
      expect(await db.getVaultLastSyncAt('my-proj'), isNull);
    });

    test(
      'vaultHubSlug/vaultLastSyncAt do not disturb other project settings',
      () async {
        await db.setProjectDisplayName('my-proj', 'My Project');
        await db.setVaultHubSlug('my-proj', 'my-proj-hub');
        await db.setVaultLastSyncAt('my-proj', DateTime.now());

        final settings = await db.getProjectSettings('my-proj');
        expect(settings, isNotNull);
        expect(settings!.displayName, equals('My Project'));
        expect(settings.vaultHubSlug, equals('my-proj-hub'));
        expect(settings.vaultLastSyncAt, isNotNull);
      },
    );
  });

  group('AppDatabase skill run persistence (schema v7)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    SkillRunTableCompanion buildRow({
      String id = 'run-1',
      String folderId = 'proj-a',
      String skillId = 'a1-progress',
      int pid = 12345,
      DateTime? processStartTime,
      DateTime? startedAt,
      String status = 'running',
      String outputFilePath = '/tmp/proj-a-a1-progress.log',
    }) {
      final now = DateTime.now();
      return SkillRunTableCompanion.insert(
        id: id,
        folderId: folderId,
        skillId: skillId,
        pid: pid,
        processStartTime: processStartTime ?? now,
        startedAt: startedAt ?? now,
        status: status,
        outputFilePath: outputFilePath,
      );
    }

    test('getSkillRun returns null when no run exists for the pair', () async {
      expect(await db.getSkillRun('proj-a', 'a1-progress'), isNull);
    });

    test('upsertSkillRun persists every field, round-tripped', () async {
      final processStartTime = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
      ).toUtc();
      final startedAt = processStartTime;

      await db.upsertSkillRun(
        buildRow(processStartTime: processStartTime, startedAt: startedAt),
      );

      final row = await db.getSkillRun('proj-a', 'a1-progress');
      expect(row, isNotNull);
      expect(row!.id, equals('run-1'));
      expect(row.folderId, equals('proj-a'));
      expect(row.skillId, equals('a1-progress'));
      expect(row.pid, equals(12345));
      expect(
        row.processStartTime.toUtc().isAtSameMomentAs(processStartTime),
        isTrue,
      );
      expect(row.startedAt.toUtc().isAtSameMomentAs(startedAt), isTrue);
      expect(row.status, equals('running'));
      expect(row.completedAt, isNull);
      expect(row.outputFilePath, equals('/tmp/proj-a-a1-progress.log'));
    });

    test(
      'upsertSkillRun replaces (never appends) the row for the same pair',
      () async {
        await db.upsertSkillRun(buildRow(id: 'run-1', pid: 111));
        await db.upsertSkillRun(buildRow(id: 'run-2', pid: 222));

        final row = await db.getSkillRun('proj-a', 'a1-progress');
        expect(row, isNotNull);
        expect(row!.id, equals('run-2'));
        expect(row.pid, equals(222));

        final allRows = await db.select(db.skillRunTable).get();
        expect(
          allRows.where(
            (r) => r.folderId == 'proj-a' && r.skillId == 'a1-progress',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'getAllRunningSkillRuns never returns two rows for the same pair',
      () async {
        await db.upsertSkillRun(buildRow(id: 'run-1', pid: 111));
        await db.upsertSkillRun(buildRow(id: 'run-2', pid: 222));

        final running = await db.getAllRunningSkillRuns();
        expect(
          running.where(
            (r) => r.folderId == 'proj-a' && r.skillId == 'a1-progress',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'getAllRunningSkillRuns only returns rows with status running',
      () async {
        await db.upsertSkillRun(
          buildRow(
            id: 'run-a',
            folderId: 'proj-a',
            skillId: 'a1-progress',
            status: 'running',
          ),
        );
        await db.upsertSkillRun(
          buildRow(
            id: 'run-b',
            folderId: 'proj-b',
            skillId: 'a1-checklist',
            status: 'success',
          ),
        );

        final running = await db.getAllRunningSkillRuns();
        expect(running, hasLength(1));
        expect(running.single.folderId, equals('proj-a'));
      },
    );

    test('updateSkillRunStatus transitions status/completedAt, leaving '
        'pid/start-time fields unchanged', () async {
      final processStartTime = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
      ).toUtc();
      await db.upsertSkillRun(
        buildRow(id: 'run-1', pid: 999, processStartTime: processStartTime),
      );

      final completedAt = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
      ).toUtc();
      await db.updateSkillRunStatus(
        'run-1',
        status: 'success',
        completedAt: completedAt,
      );

      final row = await db.getSkillRun('proj-a', 'a1-progress');
      expect(row, isNotNull);
      expect(row!.status, equals('success'));
      expect(row.completedAt?.toUtc().isAtSameMomentAs(completedAt), isTrue);
      // PID / start-time fields untouched by the status transition.
      expect(row.pid, equals(999));
      expect(
        row.processStartTime.toUtc().isAtSameMomentAs(processStartTime),
        isTrue,
      );
    });
  });

  group('AppDatabase v5→v6 migration', () {
    test('upgrades a v5 database without data loss', () async {
      final dir = await Directory.systemTemp.createTemp(
        'pro_orc_migration_v6_test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final dbFile = File(p.join(dir.path, 'test.sqlite'));

      // Build a real v5-shaped database on disk via raw SQL: the exact
      // schema pre-Wave-1 (schemaVersion 5, after the v5 groups/view-mode/
      // seed-flag columns, no vaultHubFolder/vaultHubSlug/vaultLastSyncAt).
      // `user_version` is what Drift reads as `from` when it reopens this
      // file — see onUpgrade's `if (from < 6)` block.
      final seedDb = NativeDatabase(dbFile);
      final rawSeed = DatabaseConnection(seedDb);
      await rawSeed.executor.ensureOpen(_NoopUser());
      await rawSeed.executor.runCustom('''
        CREATE TABLE app_config_table (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          scan_dir TEXT NOT NULL DEFAULT '',
          ignore_list_json TEXT NOT NULL DEFAULT '[".*","node_modules","build",".dart_tool"]',
          git_binary_path TEXT NOT NULL DEFAULT 'git',
          theme_mode TEXT NOT NULL DEFAULT 'dark',
          vault_dir TEXT NOT NULL DEFAULT '',
          view_mode TEXT NOT NULL DEFAULT 'grid',
          project_organization_seed_applied INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await rawSeed.executor.runCustom('''
        CREATE TABLE project_settings_table (
          folder_id TEXT NOT NULL PRIMARY KEY,
          project_type TEXT NULL,
          display_name TEXT NULL,
          type_set_at INTEGER NULL,
          is_hidden INTEGER NOT NULL DEFAULT 0,
          group_id TEXT NULL
        );
      ''');
      await rawSeed.executor.runCustom('''
        CREATE TABLE project_groups_table (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          is_system INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await rawSeed.executor.runCustom('''
        CREATE TABLE group_collapse_state_table (
          group_id TEXT NOT NULL PRIMARY KEY,
          collapsed INTEGER NOT NULL DEFAULT 0
        );
      ''');
      await rawSeed.executor.runInsert(
        "INSERT INTO app_config_table (id, theme_mode, view_mode) VALUES (1, 'light', 'list')",
        const [],
      );
      await rawSeed.executor.runInsert(
        "INSERT INTO project_settings_table (folder_id, is_hidden, display_name) VALUES ('wtv', 1, 'WTV Project')",
        const [],
      );
      await rawSeed.executor.runInsert(
        "INSERT INTO project_groups_table (id, name, is_system) VALUES ('grp_1', 'Kunden', 0)",
        const [],
      );
      await rawSeed.executor.runCustom('PRAGMA user_version = 5;');
      await seedDb.close();

      // Reopen the same file via the real v6 AppDatabase — Drift reads
      // `user_version` (5) and runs onUpgrade(from: 5, to: 6).
      final v6Db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(v6Db.close);

      // Pre-existing v5 data survived the migration untouched.
      final settings = await v6Db.getProjectSettings('wtv');
      expect(settings, isNotNull);
      expect(settings!.isHidden, isTrue);
      expect(settings.displayName, equals('WTV Project'));
      expect(await v6Db.getThemeMode(), equals('light'));
      expect(await v6Db.getViewMode(), equals('list'));

      final groups = await v6Db.getGroups();
      expect(groups.where((g) => g.id == 'grp_1'), isNotEmpty);

      // New v6 schema surface is present, correctly defaulted, and usable.
      expect(await v6Db.getVaultHubFolder(), equals('project'));
      expect(await v6Db.getVaultHubSlug('wtv'), isNull);
      expect(await v6Db.getVaultLastSyncAt('wtv'), isNull);

      await v6Db.setVaultHubSlug('wtv', 'wtv-hub');
      expect(await v6Db.getVaultHubSlug('wtv'), equals('wtv-hub'));

      // Pre-existing member survives alongside the new columns.
      final updatedSettings = await v6Db.getProjectSettings('wtv');
      expect(updatedSettings!.isHidden, isTrue);
      expect(updatedSettings.displayName, equals('WTV Project'));
    });
  });

  group('AppDatabase v6→v7 migration', () {
    test('upgrades a v6 database without data loss, adds skillRunTable', () async {
      final dir = await Directory.systemTemp.createTemp(
        'pro_orc_migration_v7_test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final dbFile = File(p.join(dir.path, 'test.sqlite'));

      // Build a real v6-shaped database on disk via raw SQL: the exact
      // schema pre-Wave-1 (schemaVersion 6, after the v6 vault-hub
      // columns, no skill_run_table). `user_version` is what Drift reads
      // as `from` when it reopens this file — see onUpgrade's
      // `if (from < 7)` block.
      final seedDb = NativeDatabase(dbFile);
      final rawSeed = DatabaseConnection(seedDb);
      await rawSeed.executor.ensureOpen(_NoopV6User());
      await rawSeed.executor.runCustom('''
          CREATE TABLE app_config_table (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            scan_dir TEXT NOT NULL DEFAULT '',
            ignore_list_json TEXT NOT NULL DEFAULT '[".*","node_modules","build",".dart_tool"]',
            git_binary_path TEXT NOT NULL DEFAULT 'git',
            theme_mode TEXT NOT NULL DEFAULT 'dark',
            vault_dir TEXT NOT NULL DEFAULT '',
            view_mode TEXT NOT NULL DEFAULT 'grid',
            project_organization_seed_applied INTEGER NOT NULL DEFAULT 0,
            vault_hub_folder TEXT NOT NULL DEFAULT 'project'
          );
        ''');
      await rawSeed.executor.runCustom('''
          CREATE TABLE project_settings_table (
            folder_id TEXT NOT NULL PRIMARY KEY,
            project_type TEXT NULL,
            display_name TEXT NULL,
            type_set_at INTEGER NULL,
            is_hidden INTEGER NOT NULL DEFAULT 0,
            group_id TEXT NULL,
            vault_hub_slug TEXT NULL,
            vault_last_sync_at INTEGER NULL
          );
        ''');
      await rawSeed.executor.runCustom('''
          CREATE TABLE project_groups_table (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            is_system INTEGER NOT NULL DEFAULT 0
          );
        ''');
      await rawSeed.executor.runCustom('''
          CREATE TABLE group_collapse_state_table (
            group_id TEXT NOT NULL PRIMARY KEY,
            collapsed INTEGER NOT NULL DEFAULT 0
          );
        ''');
      await rawSeed.executor.runInsert(
        "INSERT INTO app_config_table (id, theme_mode, view_mode, vault_hub_folder) VALUES (1, 'dark', 'grid', 'project')",
        const [],
      );
      await rawSeed.executor.runInsert(
        "INSERT INTO project_settings_table (folder_id, is_hidden, display_name, vault_hub_slug) VALUES ('wtv', 1, 'WTV Project', 'wtv-hub')",
        const [],
      );
      await rawSeed.executor.runInsert(
        "INSERT INTO project_groups_table (id, name, is_system) VALUES ('grp_1', 'Kunden', 0)",
        const [],
      );
      await rawSeed.executor.runCustom('PRAGMA user_version = 6;');
      await seedDb.close();

      // Reopen the same file via the real v7 AppDatabase — Drift reads
      // `user_version` (6) and runs onUpgrade(from: 6, to: 7).
      final v7Db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(v7Db.close);

      // Pre-existing v6 data survived the migration untouched.
      final settings = await v7Db.getProjectSettings('wtv');
      expect(settings, isNotNull);
      expect(settings!.isHidden, isTrue);
      expect(settings.displayName, equals('WTV Project'));
      expect(settings.vaultHubSlug, equals('wtv-hub'));
      expect(await v7Db.getVaultHubFolder(), equals('project'));

      final groups = await v7Db.getGroups();
      expect(groups.where((g) => g.id == 'grp_1'), isNotEmpty);

      // New v7 schema surface (skillRunTable) is present, empty, usable.
      final runRows = await v7Db.select(v7Db.skillRunTable).get();
      expect(runRows, isEmpty);
      expect(await v7Db.getSkillRun('wtv', 'a1-progress'), isNull);

      final now = DateTime.now();
      await v7Db.upsertSkillRun(
        SkillRunTableCompanion.insert(
          id: 'run-1',
          folderId: 'wtv',
          skillId: 'a1-progress',
          pid: 4242,
          processStartTime: now,
          startedAt: now,
          status: 'running',
          outputFilePath: '/tmp/wtv-a1-progress.log',
        ),
      );
      final newRow = await v7Db.getSkillRun('wtv', 'a1-progress');
      expect(newRow, isNotNull);
      expect(newRow!.pid, equals(4242));

      // Pre-existing member survives alongside the new table.
      final updatedSettings = await v7Db.getProjectSettings('wtv');
      expect(updatedSettings!.isHidden, isTrue);
      expect(updatedSettings.displayName, equals('WTV Project'));
    });
  });
}

class _NoopUser extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  @override
  int get schemaVersion => 5;
}

class _NoopV6User extends QueryExecutorUser {
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}

  @override
  int get schemaVersion => 6;
}
