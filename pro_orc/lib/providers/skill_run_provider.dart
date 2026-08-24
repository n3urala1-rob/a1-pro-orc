import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/headless_skill_runner.dart';
import 'package:pro_orc/data/services/skill_notification_service.dart';
import 'package:pro_orc/data/services/skill_run_concurrency_limiter.dart';
import 'package:pro_orc/data/services/skill_run_reconciler.dart';
import 'package:pro_orc/data/services/vault_record_writer.dart';
import 'package:pro_orc/data/services/vault_root_resolver.dart';
import 'package:pro_orc/providers/database_provider.dart';

/// Composite key into [SkillRunState.lastRunByKey]/[SkillRunState.inFlightKeys]
/// — `'<folderId>:<skillId>'`.
String skillRunKey(String folderId, String skillId) => '$folderId:$skillId';

/// Outcome of [SkillRunNotifier.start].
enum StartSkillOutcome { started, rejectedConcurrencyLimit, claudeNotAvailable }

class StartSkillResult {
  const StartSkillResult(this.outcome);

  final StartSkillOutcome outcome;

  bool get started => outcome == StartSkillOutcome.started;
}

/// State exposed to the UI: the most recent (persisted) run per
/// `folderId:skillId` key, and the set of keys currently in flight.
class SkillRunState {
  const SkillRunState({
    this.lastRunByKey = const {},
    this.inFlightKeys = const {},
  });

  final Map<String, SkillRunTableData?> lastRunByKey;
  final Set<String> inFlightKeys;

  SkillRunState copyWith({
    Map<String, SkillRunTableData?>? lastRunByKey,
    Set<String>? inFlightKeys,
  }) {
    return SkillRunState(
      lastRunByKey: lastRunByKey ?? this.lastRunByKey,
      inFlightKeys: inFlightKeys ?? this.inFlightKeys,
    );
  }
}

/// Injectable seams — production code gets the real implementations;
/// tests inject fakes. Mirrors this codebase's `whichCommand`/
/// `ClaudeDetectionService` constructor-injection precedent, applied at
/// the provider-override level (Riverpod's own seam) rather than through
/// each service's own constructor, since this notifier composes several
/// services together.
final headlessSkillRunnerProvider = Provider<HeadlessSkillRunner>(
  (ref) => const HeadlessSkillRunner(),
);

final skillRunReconcilerProvider = Provider<SkillRunReconciler>(
  (ref) => const SkillRunReconciler(),
);

final skillRunConcurrencyLimiterProvider = Provider<SkillRunConcurrencyLimiter>(
  (ref) => SkillRunConcurrencyLimiter(),
);

final vaultRecordWriterProvider = Provider<VaultRecordWriter>(
  (ref) => VaultRecordWriter(),
);

final skillNotificationServiceProvider = Provider<SkillNotificationService>(
  (ref) => SkillNotificationService(),
);

/// Orchestrates headless skill runs end-to-end: concurrency-gated start,
/// detached-process spawn (Wave 2), DB persistence (Wave 1), completion
/// handling (vault write + notification, Wave 3), cancel, and startup
/// reconciliation (Wave 3) — the single integration surface Wave 5's UI
/// calls into.
///
/// Mirrors [ProjectGroupMembershipNotifier]'s `ref.read` discipline: never
/// `ref.watch`s another provider from inside a method that runs per-call,
/// only reads the services it needs at the point of use.
class SkillRunNotifier extends Notifier<SkillRunState> {
  @override
  SkillRunState build() {
    unawaited(_reconcileOnStartup());
    return const SkillRunState();
  }

  Future<void> _reconcileOnStartup() async {
    final db = ref.read(appDatabaseProvider);
    final reconciler = ref.read(skillRunReconcilerProvider);
    final limiter = ref.read(skillRunConcurrencyLimiterProvider);

    final runningRows = await db.getAllRunningSkillRuns();
    var lastRunByKey = <String, SkillRunTableData?>{};
    var inFlightKeys = <String>{};

    for (final row in runningRows) {
      final key = skillRunKey(row.folderId, row.skillId);
      final outcome = await reconciler.reconcile(row);

      if (outcome.stillRunning) {
        lastRunByKey[key] = row;
        inFlightKeys.add(key);
        limiter.markStarted(row.folderId);
        continue;
      }

      // Terminal outcome first observed by this reconcile pass — persist
      // the resolved status and notify exactly once (the row was still
      // 'running' before this pass flipped it; a row already terminal in
      // the DB is never revisited here since getAllRunningSkillRuns only
      // returns status = 'running' rows in the first place, so no
      // re-notify path is even reachable).
      final terminalStatus = outcome.resolvedTerminalStatus!;
      final completedAt = DateTime.now();
      await db.updateSkillRunStatus(
        row.id,
        status: terminalStatus.name,
        completedAt: completedAt,
      );
      final updatedRow = SkillRunTableData(
        id: row.id,
        folderId: row.folderId,
        skillId: row.skillId,
        pid: row.pid,
        processStartTime: row.processStartTime,
        startedAt: row.startedAt,
        status: terminalStatus.name,
        completedAt: completedAt,
        outputFilePath: row.outputFilePath,
      );
      lastRunByKey[key] = updatedRow;

      await _writeVaultRecordAndNotify(
        folderId: row.folderId,
        skillId: row.skillId,
        row: updatedRow,
        status: terminalStatus,
      );
    }

    if (!ref.mounted) return;
    state = state.copyWith(
      lastRunByKey: {...state.lastRunByKey, ...lastRunByKey},
      inFlightKeys: {...state.inFlightKeys, ...inFlightKeys},
    );
  }

  /// Attempts to start [skillId] for [project]. Checks the concurrency
  /// limiter FIRST (synchronous, no `await` before the claim — see
  /// [SkillRunConcurrencyLimiter]'s own doc comment for why this ordering
  /// matters), then spawns the detached process, persists the run record
  /// BEFORE returning, and continues the run to completion in the
  /// background (unawaited).
  Future<StartSkillResult> start(
    ProjectModel project,
    String skillId,
    String skillPrompt,
  ) async {
    final limiter = ref.read(skillRunConcurrencyLimiterProvider);
    if (!limiter.canStart(project.folderId)) {
      return const StartSkillResult(StartSkillOutcome.rejectedConcurrencyLimit);
    }
    // Claim immediately — no `await` between the check above and this
    // claim, closing the same check-then-claim race window the limiter's
    // own design (and the spec 010 M-1 lesson) targets.
    limiter.markStarted(project.folderId);

    final key = skillRunKey(project.folderId, skillId);
    final runner = ref.read(headlessSkillRunnerProvider);
    final db = ref.read(appDatabaseProvider);

    final SpawnResult spawnResult;
    try {
      spawnResult = await runner.start(
        projectPath: project.path,
        skillId: skillId,
        skillPrompt: skillPrompt,
      );
    } on ClaudeNotAvailableException {
      limiter.markFinished(project.folderId);
      return const StartSkillResult(StartSkillOutcome.claudeNotAvailable);
    }

    final runId =
        '${project.folderId}-$skillId-${DateTime.now().microsecondsSinceEpoch}';
    final row = SkillRunTableCompanion.insert(
      id: runId,
      folderId: project.folderId,
      skillId: skillId,
      pid: spawnResult.pid,
      processStartTime: spawnResult.processStartTime,
      startedAt: DateTime.now(),
      status: SkillRunStatus.running.name,
      outputFilePath: spawnResult.outputFilePath,
    );
    await db.upsertSkillRun(row);

    final rowData = SkillRunTableData(
      id: runId,
      folderId: project.folderId,
      skillId: skillId,
      pid: spawnResult.pid,
      processStartTime: spawnResult.processStartTime,
      startedAt: DateTime.now(),
      status: SkillRunStatus.running.name,
      completedAt: null,
      outputFilePath: spawnResult.outputFilePath,
    );

    state = state.copyWith(
      lastRunByKey: {...state.lastRunByKey, key: rowData},
      inFlightKeys: {...state.inFlightKeys, key},
    );

    unawaited(
      _awaitCompletionAndFinalize(
        project: project,
        skillId: skillId,
        runId: runId,
        pid: spawnResult.pid,
        outputFilePath: spawnResult.outputFilePath,
      ),
    );

    return const StartSkillResult(StartSkillOutcome.started);
  }

  /// Polls [pid] until it exits (the process is detached — there is no
  /// `Process` handle to await directly), then determines the terminal
  /// status from the watchdog-captured output file and finalizes state.
  Future<void> _awaitCompletionAndFinalize({
    required ProjectModel project,
    required String skillId,
    required String runId,
    required int pid,
    required String outputFilePath,
  }) async {
    while (await isProcessAlive(pid)) {
      await Future.delayed(const Duration(milliseconds: 500));
      // The provider (and its Ref) may have been disposed while this
      // background poll was sleeping — e.g. the app quit, or (in tests) the
      // ProviderContainer was torn down. There is nothing left to finalize
      // against; the underlying process itself is unaffected (it is
      // detached, per FR-009) — only this bookkeeping continuation stops.
      if (!ref.mounted) return;
    }
    if (!ref.mounted) return;

    final db = ref.read(appDatabaseProvider);
    final exitedCleanly = await _readWatchdogSuccess(outputFilePath);
    final status = exitedCleanly
        ? SkillRunStatus.success
        : SkillRunStatus.failure;
    final completedAt = DateTime.now();

    await db.updateSkillRunStatus(
      runId,
      status: status.name,
      completedAt: completedAt,
    );
    if (!ref.mounted) return;

    final key = skillRunKey(project.folderId, skillId);
    final existing = state.lastRunByKey[key];
    if (existing != null && existing.id == runId) {
      final updatedRow = SkillRunTableData(
        id: existing.id,
        folderId: existing.folderId,
        skillId: existing.skillId,
        pid: existing.pid,
        processStartTime: existing.processStartTime,
        startedAt: existing.startedAt,
        status: status.name,
        completedAt: completedAt,
        outputFilePath: existing.outputFilePath,
      );
      state = state.copyWith(
        lastRunByKey: {...state.lastRunByKey, key: updatedRow},
        inFlightKeys: {...state.inFlightKeys}..remove(key),
      );

      await _writeVaultRecordAndNotify(
        folderId: project.folderId,
        skillId: skillId,
        row: updatedRow,
        status: status,
        project: project,
      );
    }

    if (!ref.mounted) return;
    ref.read(skillRunConcurrencyLimiterProvider).markFinished(project.folderId);
  }

  /// Best-effort read of whether the watchdog-wrapped process exited
  /// cleanly — this simple heuristic (does the output file exist and is it
  /// non-empty) is a placeholder for exit-code plumbing a later iteration
  /// could add to the watchdog script; sufficient for this wave's terminal-
  /// state classification (success vs. failure) without over-scoping.
  Future<bool> _readWatchdogSuccess(String outputFilePath) async {
    try {
      final file = File(outputFilePath);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      return content.isNotEmpty;
    } catch (e) {
      developer.log(
        'Failed to read output file $outputFilePath: $e',
        name: 'skill_run_provider',
      );
      return false;
    }
  }

  /// Terminates a running skill by SIGKILLing the persisted PID's process
  /// group — reuses the same process-group-kill approach as Wave 2's
  /// watchdog (negative PID targets the whole group, which also takes down
  /// the watchdog wrapper itself since `claude -p` is the group leader).
  Future<void> cancel(String folderId, String skillId) async {
    final key = skillRunKey(folderId, skillId);
    final row = state.lastRunByKey[key];
    if (row == null) return;

    // Negative PID = signal the whole process group (matches
    // scripts/skill_watchdog.sh's own kill mechanism).
    await Process.run('kill', ['-KILL', '--', '-${row.pid}']);

    final db = ref.read(appDatabaseProvider);
    final completedAt = DateTime.now();
    await db.updateSkillRunStatus(
      row.id,
      status: SkillRunStatus.cancelled.name,
      completedAt: completedAt,
    );

    final updatedRow = SkillRunTableData(
      id: row.id,
      folderId: row.folderId,
      skillId: row.skillId,
      pid: row.pid,
      processStartTime: row.processStartTime,
      startedAt: row.startedAt,
      status: SkillRunStatus.cancelled.name,
      completedAt: completedAt,
      outputFilePath: row.outputFilePath,
    );

    state = state.copyWith(
      lastRunByKey: {...state.lastRunByKey, key: updatedRow},
      inFlightKeys: {...state.inFlightKeys}..remove(key),
    );

    await _writeVaultRecordAndNotify(
      folderId: folderId,
      skillId: skillId,
      row: updatedRow,
      status: SkillRunStatus.cancelled,
    );

    ref.read(skillRunConcurrencyLimiterProvider).markFinished(folderId);
  }

  /// Writes the vault `record/`-note and fires the completion notification
  /// for a terminal run. [project] is used for the notification's display
  /// name when available (reconciliation-on-startup does not have a
  /// [ProjectModel] handy — [folderId] is used as a fallback display name
  /// in that case, which is acceptable since the notification's primary
  /// content is the skill name and outcome, not the project's pretty name).
  Future<void> _writeVaultRecordAndNotify({
    required String folderId,
    required String skillId,
    required SkillRunTableData row,
    required SkillRunStatus status,
    ProjectModel? project,
  }) async {
    final db = ref.read(appDatabaseProvider);
    final projectDisplayName = project?.displayName ?? folderId;

    try {
      final vaultRoot = await resolveVaultRoot(db);
      if (await Directory(vaultRoot).exists()) {
        final confirmedSlug = await db.getVaultHubSlug(folderId);
        final hubSlug = (confirmedSlug != null && confirmedSlug.isNotEmpty)
            ? confirmedSlug
            : folderId;

        String bodyContent = '';
        try {
          final outputFile = File(row.outputFilePath);
          if (await outputFile.exists()) {
            bodyContent = await outputFile.readAsString();
          }
        } catch (e) {
          developer.log(
            'Failed to read run output for vault record: $e',
            name: 'skill_run_provider',
          );
        }

        if (!ref.mounted) return;
        final writer = ref.read(vaultRecordWriterProvider);
        await writer.write(
          vaultRoot: vaultRoot,
          projectHubSlug: hubSlug,
          skillSlug: skillId,
          skillDisplayName: skillId,
          outcome: _germanOutcome(status),
          bodyContent: bodyContent,
          completedAt: row.completedAt ?? DateTime.now(),
        );
      }
    } catch (e) {
      developer.log(
        'Failed to write vault record for $folderId/$skillId: $e',
        name: 'skill_run_provider',
      );
    }

    if (!ref.mounted) return;
    final notificationService = ref.read(skillNotificationServiceProvider);
    await notificationService.notifyRunCompleted(
      skillDisplayName: skillId,
      projectDisplayName: projectDisplayName,
      status: status,
    );
  }

  String _germanOutcome(SkillRunStatus status) {
    switch (status) {
      case SkillRunStatus.success:
        return 'erfolgreich';
      case SkillRunStatus.failure:
        return 'fehlgeschlagen';
      case SkillRunStatus.timeout:
        return 'abgebrochen';
      case SkillRunStatus.cancelled:
        return 'abgebrochen';
      case SkillRunStatus.running:
        return 'läuft';
    }
  }
}

final skillRunProvider = NotifierProvider<SkillRunNotifier, SkillRunState>(
  SkillRunNotifier.new,
);
