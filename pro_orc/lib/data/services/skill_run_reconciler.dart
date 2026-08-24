import 'dart:io';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/services/headless_skill_runner.dart';

/// Result of reconciling one persisted [SkillRunTableData] row against real
/// OS process state.
class ReconcileOutcome {
  const ReconcileOutcome({
    required this.stillRunning,
    this.resolvedTerminalStatus,
  });

  final bool stillRunning;

  /// Set iff [stillRunning] is false — the terminal status this run should
  /// be persisted as. Null when [stillRunning] is true.
  final SkillRunStatus? resolvedTerminalStatus;
}

/// Reconciles a persisted `SkillRunTable` row against real OS process
/// state on app startup — the PID-reuse guard this feature exists for (see
/// spec 011 FR-011).
///
/// A process with [SkillRunTableData.pid] must exist AND its OS-reported
/// start time (re-read the same way as at spawn time — via
/// [readProcessStartTime], reusing Wave 2's helper rather than duplicating
/// the `ps` invocation logic) must match [SkillRunTableData.processStartTime]
/// before this is treated as the same live run. A PID that exists but whose
/// start time does not match is treated as "not the same run" — terminal,
/// unknown outcome — NEVER killed, NEVER assumed live. This is the explicit
/// defense against the OS reusing a PID after the original process exited.
class SkillRunReconciler {
  const SkillRunReconciler({
    this.startTimeTolerance = const Duration(seconds: 1),
  });

  /// Small tolerance for the [SkillRunTableData.processStartTime] vs.
  /// freshly-read `ps -o lstart=` comparison — `lstart=` truncates to whole
  /// seconds, and the DB's own `DateTimeColumn` storage (unix timestamp,
  /// second precision, see `app_database_test.dart`'s round-trip tests) can
  /// independently truncate sub-second precision on write. An exact-second
  /// tolerance absorbs both without weakening the PID-reuse guard: an
  /// unrelated process from a different spawn is virtually never within
  /// this tolerance AND sharing the same reused PID.
  final Duration startTimeTolerance;

  Future<ReconcileOutcome> reconcile(SkillRunTableData row) async {
    final currentStartTime = await readProcessStartTime(row.pid);

    if (currentStartTime == null) {
      // PID no longer exists — the process is gone. Its outcome (success vs.
      // failure vs. timeout) cannot be determined post-hoc from process
      // state alone; callers may refine this by inspecting the output file,
      // but from this reconciler's perspective the run is simply no longer
      // live.
      return const ReconcileOutcome(
        stillRunning: false,
        resolvedTerminalStatus: SkillRunStatus.failure,
      );
    }

    final matches =
        currentStartTime.difference(row.processStartTime.toLocal()).abs() <=
        startTimeTolerance;

    if (!matches) {
      // A PID exists but belongs to a different process than the one this
      // row recorded (PID reuse) — never treated as live, never signaled.
      return const ReconcileOutcome(
        stillRunning: false,
        resolvedTerminalStatus: SkillRunStatus.failure,
      );
    }

    return const ReconcileOutcome(stillRunning: true);
  }
}

/// Returns true if a process with [pid] currently exists — used by tests
/// and callers that only need a liveness check without the full PID-reuse
/// safety [SkillRunReconciler.reconcile] provides.
Future<bool> isProcessAlive(int pid) async {
  final result = await Process.run('ps', ['-p', pid.toString()]);
  return result.exitCode == 0;
}
