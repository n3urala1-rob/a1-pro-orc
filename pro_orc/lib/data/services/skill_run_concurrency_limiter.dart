/// In-memory concurrency gate for headless skill runs: at most 1 in-flight
/// run per project (`folderId`), at most 2 in-flight system-wide, at any
/// time (spec 011 FR-007).
///
/// Distinct from `globalProcessSemaphore`/`ProcessSemaphore`
/// (`process_runner.dart`) by design — that semaphore is built for short,
/// bursty spawns (git/vercel calls) and queues callers that exceed its
/// limit; headless `claude -p` runs are long-lived LLM processes where
/// queuing would silently delay a user's explicit click with no feedback.
/// This limiter's whole contract is reject, never queue: [canStart] is a
/// synchronous boolean check with no internal waiting.
///
/// Does not survive an app restart — a restart's reconciliation pass
/// (`SkillRunReconciler`, wired in Wave 4) already re-derives "currently
/// running" from the persisted `SkillRunTable` and can seed this limiter's
/// in-memory state at startup via [markStarted] for each still-live row.
///
/// Every method here is synchronous (no `async`, no internal `await`) by
/// design — this is the direct fix for the concurrency-check race class
/// found in Spec 010's review (M-1: an in-flight marker set only AFTER an
/// `await` let two concurrent callers both observe "not yet marked" and
/// both proceed). A synchronous check-and-claim in [canStart] means there
/// is no `await` between reading and mutating this limiter's state for any
/// single call, so two calls can never interleave mid-check the way two
/// `async` calls sharing a microtask turn could.
class SkillRunConcurrencyLimiter {
  SkillRunConcurrencyLimiter({int maxSystemWide = 2})
    : _maxSystemWide = maxSystemWide;

  final int _maxSystemWide;
  final Set<String> _runningFolderIds = {};

  /// Currently in-flight run count, exposed for tests/diagnostics.
  int get runningCount => _runningFolderIds.length;

  /// Returns `true` if a run may start for [folderId] right now: `false` if
  /// [folderId] already has a run in flight (per-project limit of 1, which
  /// also directly enforces "no two different skills for the same project"
  /// — FR-019 needs no separate mechanism), or if the system-wide count is
  /// already at [_maxSystemWide]. A caller intending to actually start a
  /// run should treat a `true` result as immediately followed by
  /// [markStarted] with no `await` in between, so the check-and-claim stays
  /// atomic from this limiter's perspective (see class doc — the exact
  /// shape of the M-1 race this design closes).
  bool canStart(String folderId) {
    if (_runningFolderIds.contains(folderId)) return false;
    if (_runningFolderIds.length >= _maxSystemWide) return false;
    return true;
  }

  /// Marks [folderId] as having an in-flight run. Callers must have just
  /// checked [canStart] (ideally with no intervening `await`) — this method
  /// itself does not re-check the limits, matching the plan's
  /// check-then-claim contract.
  void markStarted(String folderId) {
    _runningFolderIds.add(folderId);
  }

  /// Marks [folderId]'s run as finished, freeing both its per-project slot
  /// and one system-wide slot.
  void markFinished(String folderId) {
    _runningFolderIds.remove(folderId);
  }
}
