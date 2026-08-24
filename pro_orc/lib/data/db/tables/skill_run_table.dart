import 'package:drift/drift.dart';

/// Terminal (or in-flight) outcome of a headless skill run, persisted before
/// the process is spawned so an app restart can reconcile against real OS
/// process state (re-attach on match, "no longer live" on mismatch).
class SkillRunTable extends Table {
  // folderId + skillId is the natural key (only the most recent run per
  // pair is kept — no history, per spec Out of Scope) but a surrogate id
  // keeps insert/update simple and consistent with this codebase's other
  // tables (e.g. ProjectGroupsTable's generated id).
  TextColumn get id => text()();
  TextColumn get folderId => text()();
  TextColumn get skillId => text()();

  /// PID of the `claude -p` child (NOT the watchdog wrapper) — this is the
  /// process reconciliation compares against on app restart.
  IntColumn get pid => integer()();

  /// OS-reported process start time of [pid] at spawn time (e.g. `ps -o
  /// lstart= -p PID`), stored so a later PID-reuse cannot be mistaken for
  /// the same run.
  DateTimeColumn get processStartTime => dateTime()();

  DateTimeColumn get startedAt => dateTime()();

  /// running | success | failure | timeout | cancelled — see
  /// [SkillRunStatus] in headless_skill_runner.dart (Wave 2) for the
  /// canonical enum; stored as text for forward-compatible migrations.
  TextColumn get status => text()();

  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Path to the captured stdout/stderr output file for this run (Wave 2's
  /// watchdog redirects output to a file since the process is detached and
  /// Pro Orc cannot stream a detached process's stdout).
  TextColumn get outputFilePath => text()();

  @override
  Set<Column> get primaryKey => {id};
}
