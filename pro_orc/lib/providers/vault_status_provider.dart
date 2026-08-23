import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/data/services/vault_hub_matcher.dart';
import 'package:pro_orc/data/services/vault_root_resolver.dart';
import 'package:pro_orc/data/services/vault_status_writer.dart';
import 'package:pro_orc/providers/database_provider.dart';

/// Minimum interval between two AUTOMATIC vault writes for the same project
/// (FR-012). Manual "Jetzt synchronisieren" writes (via [syncNow]) bypass
/// this — see FR-014.
const Duration vaultSyncDebounce = Duration(minutes: 15);

/// The six status fields computed for a project, compared by value against
/// the last-written tuple to decide whether an automatic write is due
/// (FR-012) — mirrors the [ProjectModel] value-equality pattern from the
/// 2026-08-20 process-storm fix, applied here to just the fields that
/// matter for the vault write instead of the whole model.
class _StatusTuple {
  final String status;
  final int progress;
  final String phase;
  final String milestone;
  final String? lastCommit;

  const _StatusTuple({
    required this.status,
    required this.progress,
    required this.phase,
    required this.milestone,
    required this.lastCommit,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _StatusTuple &&
          status == other.status &&
          progress == other.progress &&
          phase == other.phase &&
          milestone == other.milestone &&
          lastCommit == other.lastCommit);

  @override
  int get hashCode =>
      Object.hash(status, progress, phase, milestone, lastCommit);
}

/// Injectable so tests can substitute a fake writer without touching disk —
/// production code gets a real [VaultStatusWriter].
final vaultStatusWriterProvider = Provider<VaultStatusWriter>(
  (ref) => VaultStatusWriter(),
);

/// Injectable clock so debounce tests can simulate elapsed time without a
/// real 15-minute sleep — production code gets `DateTime.now`.
final vaultClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Public read of the shared [resolveVaultRoot] resolution, for UI
/// providers (Wave 4's vault-unreachable settings indicator) that need it
/// reactively.
final resolvedVaultRootProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return resolveVaultRoot(db);
});

/// True when the resolved vault root exists on disk — backs the settings
/// screen's "Vault-Pfad nicht erreichbar" indicator (FR-016's UI half).
/// Mirrors the same existence check [VaultStatusNotifier._performWrite]
/// performs before attempting a write.
final vaultReachableProvider = FutureProvider<bool>((ref) async {
  final root = await ref.watch(resolvedVaultRootProvider.future);
  return Directory(root).exists();
});

/// Derives the `proorc_status` vocabulary word from a project's [A1Data],
/// reusing the same word set `deriveDisplayStatus`/`DisplayStatus` already
/// establish elsewhere in the app (spec Dependencies: "no new status
/// vocabulary") rather than inventing new status strings for the vault.
///
/// `ProjectModel` carries no single project-level status field of its own
/// (only per-milestone/per-phase status text) — an active phase means the
/// project is currently being worked (`'building'`); phases/milestones exist
/// and none are active means the tracked work is finished (`'done'`); no
/// phases/milestones at all means there is nothing yet to report progress
/// on (`'planning'`), the same fallback the roadmap tab uses for an
/// unclassified project.
String _deriveStatus(A1Data? a1) {
  if (a1 == null || a1.isEmpty) return 'planning';
  if (a1.activePhase != null) return 'building';

  final anyMilestoneActive = a1.milestones.any((m) => m.isActive);
  if (anyMilestoneActive) return 'building';

  final allDone =
      a1.phases.every((ph) => !ph.isActive) &&
      (a1.milestones.isEmpty || a1.milestones.every((m) => m.isDone));
  return allDone ? 'done' : 'planning';
}

/// Computes the six-field status tuple for [project] — the source-mapping
/// from spec Dependencies: status/progress/phase from `ProjectModel.a1`
/// (already loaded by the scan, no extra I/O), milestone also from
/// `ProjectModel.a1` (the active milestone's name, or the first milestone
/// as a fallback when none is marked active — `roadmapProvider`'s
/// multi-tier fallback chain is deliberately NOT used here: it can perform
/// real I/O, including an MCP call, and running it per-project on every
/// `projectsProvider` tick would reintroduce the kind of unbounded fan-out
/// the 2026-08-20 process storm postmortem warns against), and
/// `lastCommit` from `ProjectModel.git`.
_StatusTuple _computeTuple(ProjectModel project) {
  final a1 = project.a1;
  final status = _deriveStatus(a1);
  final progress = a1?.overallProgress ?? 0;
  final phase = a1?.activePhase?.name ?? '';
  final milestone = _deriveMilestone(a1);
  final lastCommit = project.git?.lastCommitDate?.toUtc().toIso8601String();

  return _StatusTuple(
    status: status,
    progress: progress,
    phase: phase,
    milestone: milestone,
    lastCommit: lastCommit,
  );
}

String _deriveMilestone(A1Data? a1) {
  if (a1 == null || a1.milestones.isEmpty) return '';
  for (final m in a1.milestones) {
    if (m.isActive) return m.name;
  }
  return a1.milestones.first.name;
}

/// Outcome of a [VaultStatusNotifier.syncNow]/[VaultStatusNotifier.syncIfDue]
/// call — a sealed-ish class (not a real `sealed` since it needs a `const`
/// literal API for the fixed non-write sentinels) so callers can pattern-
/// match on distinct states instead of overloading [VaultWriteResult] with
/// meanings it was never designed for.
///
/// M-5 fix (review round 1): previously an unconfirmed fuzzy-match
/// candidate reused [VaultWriteResult.skippedLocked] as a sentinel,
/// indistinguishable from a real I/O failure — the project silently never
/// synced and the manual "Jetzt synchronisieren" button gave the user zero
/// feedback about why. [needsConfirmation] is now a distinct, UI-visible
/// state.
class VaultStatusSyncOutcome {
  final VaultWriteResult? writeResult;
  final bool isNeedsConfirmation;
  final bool isArchived;
  final bool isAlreadyInFlight;

  const VaultStatusSyncOutcome.result(VaultWriteResult result)
    : writeResult = result,
      isNeedsConfirmation = false,
      isArchived = false,
      isAlreadyInFlight = false;

  const VaultStatusSyncOutcome.needsConfirmation()
    : writeResult = null,
      isNeedsConfirmation = true,
      isArchived = false,
      isAlreadyInFlight = false;

  const VaultStatusSyncOutcome.archived()
    : writeResult = null,
      isNeedsConfirmation = false,
      isArchived = true,
      isAlreadyInFlight = false;

  const VaultStatusSyncOutcome.alreadyInFlight()
    : writeResult = null,
      isNeedsConfirmation = false,
      isArchived = false,
      isAlreadyInFlight = true;

  /// True when a hub was actually written to (created or updated).
  bool get didWrite =>
      writeResult == VaultWriteResult.written ||
      writeResult == VaultWriteResult.created;
}

/// Orchestrates the vault-write pipeline: value-equality change detection
/// (FR-012), the 15-minute automatic-write debounce, Archiv-group exclusion
/// (FR-013), hub resolution (confirmed link, or fuzzy-match-candidate vs.
/// auto-create), and per-project write serialization so an automatic and a
/// manual write for the same project never overlap (FR-014).
///
/// Deliberately NOT a [FutureProvider]/[AsyncNotifier] over the project list
/// itself — this notifier is invoked per-project (`syncIfDue`/`syncNow`) by
/// its caller (Wave 5 wires the actual `projectsProvider` trigger), so it
/// stays a plain [Notifier] with `void` state and side-effecting methods,
/// mirroring [ProjectGroupMembershipNotifier]'s `ref.read` discipline: never
/// `ref.watch`s another provider from inside a method that runs on every
/// tick, to avoid the exact re-subscribe/flicker class of bug the
/// 2026-07-13 groups-flicker postmortem describes.
class VaultStatusNotifier extends Notifier<Set<String>> {
  /// In-memory record of the last tuple actually written per project this
  /// session — the "avoid a new DB column beyond Wave 1's two" approach the
  /// wave plan recommends. Cleared on app restart, which is fine: a restart
  /// then re-writes on the first eligible tick (no due debounce interval
  /// blocks that, since restart also loses no persisted vaultLastSyncAt).
  final Map<String, _StatusTuple> _lastWrittenTuple = {};

  @override
  Set<String> build() => const {};

  /// True while a write (automatic or manual) is in flight for [folderId].
  /// Exposed for the UI's disabled-while-syncing button state (Wave 4) —
  /// [state] itself IS the in-flight set (not a side field), so
  /// `ref.watch(vaultStatusProvider)` rebuilds a widget exactly when a
  /// project's in-flight status changes, per the Notifier-state-drives-
  /// rebuilds convention the rest of this codebase's providers use.
  bool isSyncing(String folderId) => state.contains(folderId);

  void _markInFlight(String folderId) {
    state = {...state, folderId};
  }

  void _clearInFlight(String folderId) {
    state = {...state}..remove(folderId);
  }

  /// Automatic path: writes only when due — the tuple changed AND the
  /// 15-minute debounce interval has elapsed (or no automatic write has
  /// ever happened) — and only for a project not in the Archiv group.
  /// Silently no-ops otherwise; never throws.
  ///
  /// [isArchived]: N-5 fix (review re-round nit) — when the caller already
  /// knows whether [project] is in the Archiv group (e.g. shell_screen.dart
  /// iterating a batch of projects with `membershipProvider`'s map already
  /// in hand), pass it here to skip this method's own DB round-trip
  /// entirely. Left `null` (the default), it falls back to the internal
  /// [_isArchived] query — callers that don't already have the answer (e.g.
  /// direct unit-test calls) keep working unchanged.
  ///
  /// M-1 fix (review round 1): the in-flight guard is claimed
  /// SYNCHRONOUSLY as the very first statement — before any `await`, not
  /// after the archived/debounce checks that used to precede it. Two
  /// `syncIfDue` calls for the same project entering in the same
  /// microtask turn previously both observed an empty in-flight set and
  /// both proceeded to write (the checks happened, then two `await`s ran,
  /// THEN both marked in-flight — too late). Claiming the guard first and
  /// releasing it in every early-return path (via `finally`) closes that
  /// window entirely; every exit — archived, unchanged tuple, debounce not
  /// elapsed, or an actual write — goes through the same `try/finally`.
  Future<void> syncIfDue(ProjectModel project, {bool? isArchived}) async {
    if (!_tryClaimInFlight(project.folderId)) return;
    try {
      final archived = isArchived ?? await _isArchived(project.folderId);
      if (archived) return;

      final db = ref.read(appDatabaseProvider);
      final tuple = _computeTuple(project);
      final lastTuple = _lastWrittenTuple[project.folderId];
      if (lastTuple == tuple) return; // FR-012 value-equality gate

      final lastSyncAt = await db.getVaultLastSyncAt(project.folderId);
      final now = ref.read(vaultClockProvider)();
      if (lastSyncAt != null &&
          now.difference(lastSyncAt) < vaultSyncDebounce) {
        return; // debounce interval not yet elapsed
      }

      await _performWrite(project, tuple);
    } finally {
      _clearInFlight(project.folderId);
    }
  }

  /// Manual path (Wave 4's "Jetzt synchronisieren" button): bypasses the
  /// 15-minute debounce (FR-014), but still respects Archiv exclusion
  /// (FR-013) and per-project serialization. Returns the writer's result,
  /// a [VaultStatusSyncOutcome.needsConfirmation] sentinel when a fuzzy
  /// suggestion exists but is unconfirmed (M-5 — distinct from a real
  /// failure so the UI can tell the user why nothing happened instead of
  /// silently doing nothing), or [VaultStatusSyncOutcome.alreadyInFlight]
  /// when a write for this project is already running.
  ///
  /// M-1 fix: same synchronous-claim-first discipline as [syncIfDue] — see
  /// its doc comment.
  Future<VaultStatusSyncOutcome> syncNow(ProjectModel project) async {
    if (!_tryClaimInFlight(project.folderId)) {
      return const VaultStatusSyncOutcome.alreadyInFlight();
    }
    try {
      if (await _isArchived(project.folderId)) {
        return const VaultStatusSyncOutcome.archived();
      }

      final tuple = _computeTuple(project);
      return await _performWrite(project, tuple);
    } finally {
      _clearInFlight(project.folderId);
    }
  }

  /// Atomically checks-and-claims the in-flight guard for [folderId] in one
  /// synchronous step (no `await` between the check and the claim) — the
  /// actual fix for M-1. Returns true (claimed) if [folderId] was not
  /// already in the set; false (not claimed, caller must not proceed) if
  /// it was.
  bool _tryClaimInFlight(String folderId) {
    if (state.contains(folderId)) return false;
    _markInFlight(folderId);
    return true;
  }

  Future<VaultStatusSyncOutcome> _performWrite(
    ProjectModel project,
    _StatusTuple tuple,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final vaultRoot = await resolveVaultRoot(db);
    if (!await Directory(vaultRoot).exists()) {
      return const VaultStatusSyncOutcome.result(
        VaultWriteResult.skippedIoError,
      );
    }

    final hubFolder = await db.getVaultHubFolder();
    final hubSlug = await _resolveHubSlug(db, project, vaultRoot, hubFolder);
    if (hubSlug == null) {
      // M-5 fix (review round 1): a fuzzy candidate exists but is
      // unconfirmed — Wave 4's confirmation UI owns turning that into a
      // confirmed link. Previously this reused VaultWriteResult.skippedLocked
      // as a sentinel, which is indistinguishable from a real I/O failure
      // and meant the project deadlocked (never synced, no error, no
      // explanation) until the user happened to open the settings dialog.
      // A distinct outcome lets the UI surface "Zuordnung bestätigen"
      // instead of silently doing nothing.
      return const VaultStatusSyncOutcome.needsConfirmation();
    }

    final now = ref.read(vaultClockProvider)();
    final writer = ref.read(vaultStatusWriterProvider);
    final result = await writer.write(
      vaultRoot: vaultRoot,
      hubFolder: hubFolder,
      hubSlug: hubSlug,
      displayName: project.displayName,
      fields: VaultStatusFields(
        status: tuple.status,
        progress: tuple.progress,
        phase: tuple.phase,
        milestone: tuple.milestone,
        lastCommit: tuple.lastCommit,
        lastSync: now,
      ),
    );

    if (result == VaultWriteResult.written ||
        result == VaultWriteResult.created) {
      _lastWrittenTuple[project.folderId] = tuple;
      await db.setVaultLastSyncAt(project.folderId, now);
      if (hubSlug != await db.getVaultHubSlug(project.folderId)) {
        await db.setVaultHubSlug(project.folderId, hubSlug);
      }
    }
    // Soft-fail results (skippedLocked/skippedIoError/skippedOutsideRoot)
    // deliberately do NOT update vaultLastSyncAt (FR-017) — the next
    // regular trigger (automatic tick or manual click) retries
    // independently, with no special-cased retry logic here.

    return VaultStatusSyncOutcome.result(result);
  }

  /// Resolves which hub slug to write to: the confirmed link if one exists,
  /// otherwise a fuzzy-match candidate held back for Wave 4's confirmation
  /// UI (returns null — "needs confirmation, do not auto-write"), otherwise
  /// (no candidate at all) the project's own folderId as the auto-create
  /// slug (FR-006).
  Future<String?> _resolveHubSlug(
    AppDatabase db,
    ProjectModel project,
    String vaultRoot,
    String hubFolder,
  ) async {
    final confirmed = await db.getVaultHubSlug(project.folderId);
    if (confirmed != null && confirmed.isNotEmpty) return confirmed;

    final candidateStems = await _existingHubStems(vaultRoot, hubFolder);
    final suggestion = suggestHub(project.folderId, candidateStems);
    if (suggestion != null) {
      // A fuzzy candidate exists but is unconfirmed — Wave 4 owns turning
      // this into a confirmed link via the batch dialog. Do not auto-write.
      return null;
    }

    // No candidate at all → auto-create using the project's own folderId.
    return project.folderId;
  }

  Future<List<String>> _existingHubStems(
    String vaultRoot,
    String hubFolder,
  ) async {
    final dir = Directory(p.join(vaultRoot, hubFolder));
    if (!await dir.exists()) return const [];
    final stems = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      stems.add(p.basenameWithoutExtension(entity.path));
    }
    return stems;
  }

  Future<bool> _isArchived(String folderId) async {
    final db = ref.read(appDatabaseProvider);
    final groupId = await db.getProjectGroupId(folderId);
    return groupId == kArchiveGroupId;
  }

  /// Computes [project]'s current vault-link status for the Wave 4 UI
  /// (settings card + batch confirmation dialog) — reuses the exact same
  /// confirmed-link / fuzzy-match / auto-create resolution [syncNow] and
  /// [syncIfDue] use internally, so the UI never disagrees with what an
  /// actual write would do. Caller is responsible for excluding Archiv-group
  /// projects beforehand (this method does not check — it is also used to
  /// preview the state a manual unarchive would restore).
  Future<VaultLinkStatus> linkStatusFor(ProjectModel project) async {
    final db = ref.read(appDatabaseProvider);
    final vaultRoot = await resolveVaultRoot(db);
    final hubFolder = await db.getVaultHubFolder();

    final confirmed = await db.getVaultHubSlug(project.folderId);
    if (confirmed != null && confirmed.isNotEmpty) {
      return VaultLinkStatus(
        folderId: project.folderId,
        displayName: project.displayName,
        kind: VaultLinkKind.linked,
        hubSlug: confirmed,
      );
    }

    final candidateStems = await _existingHubStems(vaultRoot, hubFolder);
    final suggestion = suggestHub(project.folderId, candidateStems);
    if (suggestion != null) {
      return VaultLinkStatus(
        folderId: project.folderId,
        displayName: project.displayName,
        kind: VaultLinkKind.pendingSuggestion,
        hubSlug: suggestion,
        confidence: hubSimilarity(project.folderId, suggestion),
      );
    }

    return VaultLinkStatus(
      folderId: project.folderId,
      displayName: project.displayName,
      kind: VaultLinkKind.willAutoCreate,
    );
  }
}

final vaultStatusProvider = NotifierProvider<VaultStatusNotifier, Set<String>>(
  VaultStatusNotifier.new,
);
