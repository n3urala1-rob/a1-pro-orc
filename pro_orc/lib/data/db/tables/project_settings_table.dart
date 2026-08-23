import 'package:drift/drift.dart';

class ProjectSettingsTable extends Table {
  TextColumn get folderId => text()(); // folder name = canonical ID
  TextColumn get projectType =>
      text().nullable()(); // 'code'|'research'|custom|null
  TextColumn get displayName =>
      text().nullable()(); // override for PROJECT.md name
  DateTimeColumn get typeSetAt =>
      dateTime().nullable()(); // for conflict resolution
  BoolColumn get isHidden => boolean().withDefault(const Constant(false))();

  // Nullable group membership: null = "Ohne Gruppe". 1:1 membership is
  // enforced by this being a single column, not a junction table.
  TextColumn get groupId => text().nullable()();

  /// Confirmed vault hub filename stem this project is linked to (e.g.
  /// 'pro-orc' for project/pro-orc.md), relative to vaultDir/vaultHubFolder.
  /// Null = not yet linked (fuzzy-match-or-auto-create path still applies).
  TextColumn get vaultHubSlug => text().nullable()();

  /// Timestamp of the last AUTOMATIC vault write for this project (the
  /// automatic-write debounce interval enforced in Wave 3 reads this).
  /// Manual "Jetzt synchronisieren" writes (added in Wave 4) also update
  /// this column so a manual write resets the debounce window, preventing
  /// an automatic write from firing immediately after.
  DateTimeColumn get vaultLastSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {folderId};
}
