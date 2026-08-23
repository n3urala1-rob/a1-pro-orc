import 'package:drift/drift.dart';

class AppConfigTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get scanDir => text().withDefault(const Constant(''))();
  TextColumn get ignoreListJson => text().withDefault(
    const Constant('[".*","node_modules","build",".dart_tool"]'),
  )();
  TextColumn get gitBinaryPath => text().withDefault(const Constant('git'))();

  /// One of 'light', 'dark', 'system'. Default 'dark' preserves the existing
  /// look for current users (v2.2 Design-Refresh).
  TextColumn get themeMode => text().withDefault(const Constant('dark'))();

  /// Absolute path to the Obsidian vault root used for the a1 learning-loop
  /// view (M6). Empty string means "use the default" (`$HOME/N3URAL-Vault`),
  /// resolved by the reader — kept empty by default so per-machine HOME is not
  /// baked into the DB.
  TextColumn get vaultDir => text().withDefault(const Constant(''))();

  /// Global grid/list view-mode preference for the Projekte tab: 'grid' or
  /// 'list'. Default 'grid' preserves the current look for existing users.
  TextColumn get viewMode => text().withDefault(const Constant('grid'))();

  /// One-time idempotency flag for the Project-Organization example-group
  /// seed (Wave 5). Independent of `ensureSystemGroups` — the Archiv system
  /// group exists regardless of this flag.
  BoolColumn get projectOrganizationSeedApplied =>
      boolean().withDefault(const Constant(false))();

  /// Folder convention within [vaultDir] for project hubs (7-type-IA style),
  /// e.g. 'project' for `project/<slug>.md`. Empty/default resolves to
  /// 'project' — kept as an explicit column (not hardcoded) so the folder
  /// name is user-configurable if their vault uses a different convention.
  TextColumn get vaultHubFolder =>
      text().withDefault(const Constant('project'))();
}
