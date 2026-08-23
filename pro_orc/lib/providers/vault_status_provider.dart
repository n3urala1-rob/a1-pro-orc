import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/data/services/vault_hub_matcher.dart';
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

/// Resolves the configured vault root the same way project_scanner.dart and
/// watcher_provider.dart do: an unset/empty DB value falls back to
/// `$HOME/N3URAL-Vault`.
Future<String> _resolveVaultRoot(dynamic db) async {
  final raw = await db.getVaultDir();
  if (raw != null && (raw as String).isNotEmpty) return raw;
  final home = Platform.environment['HOME'] ?? '/tmp';
  return p.join(home, 'N3URAL-Vault');
}

/// Public read of the same resolution, for UI providers (Wave 4's vault-
/// unreachable settings indicator) that need it without going through the
/// notifier's private helper.
final resolvedVaultRootProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return _resolveVaultRoot(db);
});

/// True when the resolved vault root exists on disk — backs the settings
/// screen's "Vault-Pfad nicht erreichbar" indicator (FR-016's UI half).
/// Mirrors the same existence check [VaultStatusNotifier._writeAndRecord]
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
  Future<void> syncIfDue(ProjectModel project) async {
    if (await _isArchived(project.folderId)) return;
    if (isSyncing(project.folderId)) return;

    final db = ref.read(appDatabaseProvider);
    final tuple = _computeTuple(project);
    final lastTuple = _lastWrittenTuple[project.folderId];
    if (lastTuple == tuple) return; // FR-012 value-equality gate

    final lastSyncAt = await db.getVaultLastSyncAt(project.folderId);
    final now = ref.read(vaultClockProvider)();
    if (lastSyncAt != null && now.difference(lastSyncAt) < vaultSyncDebounce) {
      return; // debounce interval not yet elapsed
    }

    await _writeAndRecord(project, tuple, isManual: false);
  }

  /// Manual path (Wave 4's "Jetzt synchronisieren" button): bypasses the
  /// 15-minute debounce (FR-014), but still respects Archiv exclusion
  /// (FR-013) and per-project serialization. Returns the writer's result,
  /// or [VaultWriteResult.skippedLocked] as an "already in flight, no-op"
  /// sentinel when a write for this project is already running — the
  /// caller's UI treats both as "nothing to show the user", per FR-014's
  /// "disabled/ignored" wording.
  Future<VaultWriteResult> syncNow(ProjectModel project) async {
    if (await _isArchived(project.folderId)) {
      return VaultWriteResult.skippedLocked;
    }
    if (isSyncing(project.folderId)) {
      return VaultWriteResult.skippedLocked;
    }

    final tuple = _computeTuple(project);
    return _writeAndRecord(project, tuple, isManual: true);
  }

  Future<VaultWriteResult> _writeAndRecord(
    ProjectModel project,
    _StatusTuple tuple, {
    required bool isManual,
  }) async {
    _markInFlight(project.folderId);
    try {
      final db = ref.read(appDatabaseProvider);
      final vaultRoot = await _resolveVaultRoot(db);
      if (!await Directory(vaultRoot).exists()) {
        return VaultWriteResult.skippedIoError;
      }

      final hubFolder = await db.getVaultHubFolder();
      final hubSlug = await _resolveHubSlug(db, project, vaultRoot, hubFolder);
      if (hubSlug == null) {
        // Has a fuzzy candidate but no confirmed link yet — Wave 4's
        // confirmation UI owns turning that into a confirmed link; this
        // wave never auto-writes to a merely-suggested (unconfirmed) hub.
        return VaultWriteResult.skippedLocked;
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

      return result;
    } finally {
      _clearInFlight(project.folderId);
    }
  }

  /// Resolves which hub slug to write to: the confirmed link if one exists,
  /// otherwise a fuzzy-match candidate held back for Wave 4's confirmation
  /// UI (returns null — "needs confirmation, do not auto-write"), otherwise
  /// (no candidate at all) the project's own folderId as the auto-create
  /// slug (FR-006).
  Future<String?> _resolveHubSlug(
    dynamic db,
    ProjectModel project,
    String vaultRoot,
    String hubFolder,
  ) async {
    final confirmed = await db.getVaultHubSlug(project.folderId) as String?;
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
    final vaultRoot = await _resolveVaultRoot(db);
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
