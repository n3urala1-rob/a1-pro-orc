import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables/app_config_table.dart';
import 'tables/group_collapse_state_table.dart';
import 'tables/project_groups_table.dart';
import 'tables/project_settings_table.dart';
import 'tables/skill_run_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    AppConfigTable,
    ProjectSettingsTable,
    ProjectGroupsTable,
    GroupCollapseStateTable,
    SkillRunTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _connect());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(projectSettingsTable, projectSettingsTable.isHidden);
      }
      if (from < 3) {
        await m.addColumn(appConfigTable, appConfigTable.themeMode);
      }
      if (from < 4) {
        await m.addColumn(appConfigTable, appConfigTable.vaultDir);
      }
      if (from < 5) {
        await m.createTable(projectGroupsTable);
        await m.addColumn(projectSettingsTable, projectSettingsTable.groupId);
        await m.addColumn(appConfigTable, appConfigTable.viewMode);
        await m.addColumn(
          appConfigTable,
          appConfigTable.projectOrganizationSeedApplied,
        );
        await m.createTable(groupCollapseStateTable);
      }
      if (from < 6) {
        await m.addColumn(appConfigTable, appConfigTable.vaultHubFolder);
        await m.addColumn(
          projectSettingsTable,
          projectSettingsTable.vaultHubSlug,
        );
        await m.addColumn(
          projectSettingsTable,
          projectSettingsTable.vaultLastSyncAt,
        );
      }
      if (from < 7) {
        await m.createTable(skillRunTable);
      }
    },
    beforeOpen: (details) async {
      await ensureSystemGroups();
    },
  );

  static QueryExecutor _connect() {
    return driftDatabase(
      name: 'pro_orc',
      native: DriftNativeOptions(
        databaseDirectory: () async =>
            (await getApplicationSupportDirectory()).path,
      ),
    );
  }

  /// Default scan directory: ~/project_orchestration
  static String get _defaultScanDir {
    final home = Platform.environment['HOME']!;
    return '$home/project_orchestration';
  }

  /// Returns the single app config row (id=1), inserting defaults on first access.
  /// If scanDir is empty, auto-populates with ~/project_orchestration.
  Future<AppConfigTableData> getConfig() async {
    final existing = await (select(
      appConfigTable,
    )..where((t) => t.id.equals(1))).getSingleOrNull();

    if (existing != null) {
      // Auto-populate empty scanDir with default
      if (existing.scanDir.isEmpty) {
        await updateConfig(scanDir: _defaultScanDir);
        return existing.copyWith(scanDir: _defaultScanDir);
      }
      return existing;
    }

    await into(
      appConfigTable,
    ).insert(AppConfigTableCompanion(scanDir: Value(_defaultScanDir)));

    return (select(appConfigTable)..where((t) => t.id.equals(1))).getSingle();
  }

  /// Returns the list of scan directories from scanDir field.
  /// Supports both legacy single-path strings and JSON arrays.
  Future<List<String>> getScanDirs() async {
    final config = await getConfig();
    final raw = config.scanDir;
    if (raw.isEmpty) return [_defaultScanDir];

    // Try JSON array first
    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final dirs = decoded
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toList();
          return dirs.isEmpty ? [_defaultScanDir] : dirs;
        }
      } catch (e) {
        // Fall through to single path
        developer.log(
          'Failed to decode scanDir JSON array: $e',
          name: 'app_database',
        );
      }
    }

    // Legacy single path
    return [raw];
  }

  /// Saves the list of scan directories as a JSON array.
  Future<void> setScanDirs(List<String> dirs) async {
    await updateConfig(scanDir: jsonEncode(dirs));
  }

  /// Updates app config fields on id=1 row.
  Future<void> updateConfig({
    String? scanDir,
    String? ignoreListJson,
    String? gitBinaryPath,
    String? themeMode,
    String? vaultDir,
    String? viewMode,
    bool? projectOrganizationSeedApplied,
    String? vaultHubFolder,
  }) async {
    await (update(appConfigTable)..where((t) => t.id.equals(1))).write(
      AppConfigTableCompanion(
        scanDir: scanDir != null ? Value(scanDir) : const Value.absent(),
        ignoreListJson: ignoreListJson != null
            ? Value(ignoreListJson)
            : const Value.absent(),
        gitBinaryPath: gitBinaryPath != null
            ? Value(gitBinaryPath)
            : const Value.absent(),
        themeMode: themeMode != null ? Value(themeMode) : const Value.absent(),
        vaultDir: vaultDir != null ? Value(vaultDir) : const Value.absent(),
        viewMode: viewMode != null ? Value(viewMode) : const Value.absent(),
        projectOrganizationSeedApplied: projectOrganizationSeedApplied != null
            ? Value(projectOrganizationSeedApplied)
            : const Value.absent(),
        vaultHubFolder: vaultHubFolder != null
            ? Value(vaultHubFolder)
            : const Value.absent(),
      ),
    );
  }

  /// Returns the configured Obsidian vault path, or null when unset (empty).
  /// Null lets the [LearningReader] fall back to its `$HOME/N3URAL-Vault`
  /// default rather than baking a per-machine HOME into the DB.
  Future<String?> getVaultDir() async {
    final config = await getConfig();
    final trimmed = config.vaultDir.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Persists the Obsidian vault path. Pass null or an empty/whitespace string
  /// to clear the override (reader then uses its default).
  Future<void> setVaultDir(String? path) async {
    await getConfig(); // ensure id=1 row exists
    await updateConfig(vaultDir: path?.trim() ?? '');
  }

  /// Returns the persisted theme mode preference: 'light', 'dark', or
  /// 'system'. Defaults to 'dark' (via the column default) if never set.
  Future<String> getThemeMode() async {
    final config = await getConfig();
    return config.themeMode;
  }

  /// Persists the theme mode preference. [mode] must be one of 'light',
  /// 'dark', 'system'.
  Future<void> setThemeMode(String mode) async {
    // Ensure the id=1 config row exists before updating it — updateConfig
    // is a no-op if the row hasn't been created yet (first-ever DB access).
    await getConfig();
    await updateConfig(themeMode: mode);
  }

  /// Adds a pattern to the ignore list (if not already present).
  Future<void> addIgnorePattern(String pattern) async {
    final config = await getConfig();
    List<String> patterns = [];
    try {
      final decoded = jsonDecode(config.ignoreListJson);
      if (decoded is List) {
        patterns = decoded.whereType<String>().toList();
      }
    } catch (e) {
      developer.log(
        'Failed to decode ignoreListJson: $e',
        name: 'app_database',
      );
    }
    if (!patterns.contains(pattern)) {
      patterns.add(pattern);
      await updateConfig(ignoreListJson: jsonEncode(patterns));
    }
  }

  /// Returns the set of folderIds marked as hidden.
  Future<Set<String>> getHiddenProjectIds() async {
    final rows = await (select(
      projectSettingsTable,
    )..where((t) => t.isHidden.equals(true))).get();
    return rows.map((r) => r.folderId).toSet();
  }

  /// Returns project settings for a given folderId, or null if not found.
  Future<ProjectSettingsTableData?> getProjectSettings(String folderId) async {
    return (select(
      projectSettingsTable,
    )..where((t) => t.folderId.equals(folderId))).getSingleOrNull();
  }

  /// Upserts project settings (insert or update on conflict).
  Future<void> upsertProjectSettings(
    ProjectSettingsTableCompanion companion,
  ) async {
    await into(projectSettingsTable).insertOnConflictUpdate(companion);
  }

  /// Sets a custom display name override for a project.
  ///
  /// Pass `null` or an empty/whitespace-only string to clear the override
  /// (the app will then fall back to PROJECT.md H1 or the folder name).
  Future<void> setProjectDisplayName(String folderId, String? name) async {
    final trimmed = name?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    await upsertProjectSettings(
      ProjectSettingsTableCompanion.insert(
        folderId: folderId,
        displayName: Value(value),
      ),
    );
  }

  /// Idempotently ensures the "Archiv" system group and its collapse row
  /// exist. Runs outside the migration (called from `beforeOpen`) so it
  /// covers both fresh installs and upgrades — see
  /// records/2026-07-12-archiv-modeling-adr.md.
  Future<void> ensureSystemGroups() async {
    await into(projectGroupsTable).insertOnConflictUpdate(
      const ProjectGroupsTableCompanion(
        id: Value(kArchiveGroupId),
        name: Value('Archiv'),
        isSystem: Value(true),
      ),
    );

    final existingCollapse = await (select(
      groupCollapseStateTable,
    )..where((t) => t.groupId.equals(kArchiveGroupId))).getSingleOrNull();
    if (existingCollapse == null) {
      await into(groupCollapseStateTable).insert(
        GroupCollapseStateTableCompanion.insert(
          groupId: kArchiveGroupId,
          collapsed: const Value(true),
        ),
      );
    }
  }

  /// Generates a collision-free group id. Never derived from the group
  /// name, and distinct from the reserved [kArchiveGroupId] sentinel — see
  /// ADR "Geprüfte Einwände" §1.
  String _generateGroupId() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return 'grp_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  /// Returns all project groups (including the "Archiv" system group).
  Future<List<ProjectGroupsTableData>> getGroups() async {
    return select(projectGroupsTable).get();
  }

  /// Creates a new user group with the given [name] and returns its
  /// generated id. Does not validate name uniqueness or reserved names —
  /// that guard lives in the provider layer (Wave 2), per the wave plan.
  Future<String> createGroup(String name) async {
    final id = _generateGroupId();
    await into(
      projectGroupsTable,
    ).insert(ProjectGroupsTableCompanion.insert(id: id, name: name));
    return id;
  }

  /// Renames an existing group. Does not guard against renaming a system
  /// group — that guard lives in the provider layer (Wave 2).
  Future<void> renameGroup(String id, String name) async {
    await (update(projectGroupsTable)..where((t) => t.id.equals(id))).write(
      ProjectGroupsTableCompanion(name: Value(name)),
    );
  }

  /// Deletes a group and resets `groupId` to null for all its members
  /// (dissolve behavior). Does not guard against deleting a system group —
  /// that guard lives in the provider layer (Wave 2).
  Future<void> deleteGroup(String id) async {
    await (update(projectSettingsTable)..where((t) => t.groupId.equals(id)))
        .write(const ProjectSettingsTableCompanion(groupId: Value(null)));
    await (delete(projectGroupsTable)..where((t) => t.id.equals(id))).go();
  }

  /// Assigns a project to a group (or `null` for "Ohne Gruppe"), replacing
  /// any previous group assignment (1:1 membership).
  Future<void> setProjectGroup(String folderId, String? groupId) async {
    await upsertProjectSettings(
      ProjectSettingsTableCompanion.insert(
        folderId: folderId,
        groupId: Value(groupId),
      ),
    );
  }

  /// Returns the group id a project is currently assigned to, or null when
  /// it is "Ohne Gruppe" (or has no settings row yet).
  Future<String?> getProjectGroupId(String folderId) async {
    final settings = await getProjectSettings(folderId);
    return settings?.groupId;
  }

  /// Returns every folderId's current group assignment (`folderId ->
  /// groupId`, `null` = "Ohne Gruppe") in one query. Mirrors
  /// [getHiddenProjectIds]'s bulk-read pattern so [membershipProvider] can
  /// eager-load on `build()` instead of only tracking folderIds it has been
  /// explicitly asked about — required for the merged Projekte tab to
  /// render correct group sections right after a fresh app start.
  Future<Map<String, String?>> getAllProjectGroupIds() async {
    final rows = await select(projectSettingsTable).get();
    return {for (final row in rows) row.folderId: row.groupId};
  }

  /// Returns the collapse state for a group, or `false` if no row exists
  /// yet (fresh user-created groups default to expanded).
  Future<bool> getCollapseState(String groupId) async {
    final row = await (select(
      groupCollapseStateTable,
    )..where((t) => t.groupId.equals(groupId))).getSingleOrNull();
    return row?.collapsed ?? false;
  }

  /// Persists the collapse state for a group.
  Future<void> setCollapseState(String groupId, bool collapsed) async {
    await into(groupCollapseStateTable).insertOnConflictUpdate(
      GroupCollapseStateTableCompanion.insert(
        groupId: groupId,
        collapsed: Value(collapsed),
      ),
    );
  }

  /// Returns the persisted global view-mode preference: 'grid' or 'list'.
  /// Defaults to 'grid' (via the column default) if never set.
  Future<String> getViewMode() async {
    final config = await getConfig();
    return config.viewMode;
  }

  /// Persists the global view-mode preference. [mode] must be one of
  /// 'grid', 'list'.
  Future<void> setViewMode(String mode) async {
    await getConfig(); // ensure id=1 row exists
    await updateConfig(viewMode: mode);
  }

  /// Returns whether the one-time Project-Organization example-group seed
  /// (Wave 5) has already run.
  Future<bool> isProjectOrganizationSeedApplied() async {
    final config = await getConfig();
    return config.projectOrganizationSeedApplied;
  }

  /// Marks the one-time Project-Organization example-group seed as applied
  /// so it never runs again.
  Future<void> markProjectOrganizationSeedApplied() async {
    await getConfig(); // ensure id=1 row exists
    await updateConfig(projectOrganizationSeedApplied: true);
  }

  /// Returns the configured vault hub folder convention (e.g. 'project').
  /// Defaults to 'project' (via the column default) if never set.
  Future<String> getVaultHubFolder() async {
    final config = await getConfig();
    return config.vaultHubFolder;
  }

  /// Persists the vault hub folder convention.
  Future<void> setVaultHubFolder(String folder) async {
    await getConfig(); // ensure id=1 row exists
    await updateConfig(vaultHubFolder: folder);
  }

  /// Returns the confirmed vault hub slug for a project, or null when not
  /// yet linked (or the project has no settings row yet).
  Future<String?> getVaultHubSlug(String folderId) async {
    final settings = await getProjectSettings(folderId);
    return settings?.vaultHubSlug;
  }

  /// Persists the confirmed vault hub slug for a project. Pass `null` to
  /// clear the link (falls back to fuzzy-match-or-auto-create).
  Future<void> setVaultHubSlug(String folderId, String? slug) async {
    await upsertProjectSettings(
      ProjectSettingsTableCompanion.insert(
        folderId: folderId,
        vaultHubSlug: Value(slug),
      ),
    );
  }

  /// Returns the timestamp of the last automatic vault write for a project,
  /// or null when it has never been written (or has no settings row yet).
  Future<DateTime?> getVaultLastSyncAt(String folderId) async {
    final settings = await getProjectSettings(folderId);
    return settings?.vaultLastSyncAt;
  }

  /// Persists the timestamp of the last (automatic or manual) vault write
  /// for a project. Pass `null` to clear it.
  Future<void> setVaultLastSyncAt(String folderId, DateTime? at) async {
    await upsertProjectSettings(
      ProjectSettingsTableCompanion.insert(
        folderId: folderId,
        vaultLastSyncAt: Value(at),
      ),
    );
  }

  /// Returns the most recent persisted run record for a given
  /// (folderId, skillId) pair, or null if that skill has never been run for
  /// that project. There is at most one row per pair — see
  /// [upsertSkillRun].
  Future<SkillRunTableData?> getSkillRun(String folderId, String skillId) {
    return (select(skillRunTable)..where(
          (t) => t.folderId.equals(folderId) & t.skillId.equals(skillId),
        ))
        .getSingleOrNull();
  }

  /// Inserts or replaces the run record for [row]'s (folderId, skillId)
  /// pair. A new run for the same pair always replaces the prior row rather
  /// than appending — this feature keeps no multi-run history (spec Out of
  /// Scope), so delete-then-insert is the simplest correct upsert given the
  /// max-one-row-per-pair invariant.
  Future<void> upsertSkillRun(SkillRunTableCompanion row) async {
    final folderId = row.folderId.value;
    final skillId = row.skillId.value;
    await transaction(() async {
      await (delete(skillRunTable)..where(
            (t) => t.folderId.equals(folderId) & t.skillId.equals(skillId),
          ))
          .go();
      await into(skillRunTable).insert(row);
    });
  }

  /// Transitions an existing run record (by its surrogate [id]) to a
  /// terminal (or updated) [status], optionally setting [completedAt].
  /// Leaves the PID/start-time/output-path fields untouched.
  Future<void> updateSkillRunStatus(
    String id, {
    required String status,
    DateTime? completedAt,
  }) async {
    await (update(skillRunTable)..where((t) => t.id.equals(id))).write(
      SkillRunTableCompanion(
        status: Value(status),
        completedAt: completedAt != null
            ? Value(completedAt)
            : const Value.absent(),
      ),
    );
  }

  /// Returns every run record currently persisted as `status = 'running'`,
  /// used by startup reconciliation to avoid scanning every row.
  Future<List<SkillRunTableData>> getAllRunningSkillRuns() {
    return (select(
      skillRunTable,
    )..where((t) => t.status.equals('running'))).get();
  }
}
