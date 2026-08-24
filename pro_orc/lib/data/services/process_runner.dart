import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Caps how many child processes spawned via [runProcessWithTimeout] may run
/// concurrently across the whole app.
///
/// Every call site (git, vercel, ...) routes through the same [_semaphore]
/// instance, so no individual service can independently reintroduce an
/// unbounded `Future.wait` burst — the cap is structural, not a convention
/// each call site has to remember. Root cause 1 of the 2026-08-20 process
/// storm: `ProjectScanner.scanAll` fired up to 90 concurrent git spawns for
/// 45 repos, each with its own 5s timeout; under load that saturated
/// `kern.maxprocperuid` and produced `fork: EAGAIN` in every shell/Claude
/// session on the machine.
///
/// Overridable via [globalProcessSemaphore] (tests inject a fresh instance
/// with a small limit to make saturation observable without spawning
/// hundreds of real processes).
class ProcessSemaphore {
  ProcessSemaphore({int maxConcurrent = 6}) : _maxConcurrent = maxConcurrent;

  final int _maxConcurrent;
  int _running = 0;
  int _peakRunning = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Current number of processes running under this semaphore. Exposed for
  /// tests that assert the observed concurrency never exceeds the limit.
  int get running => _running;

  /// Highest [running] value ever observed since this instance was created
  /// (process-storm round 3, WP3 — team-lead follow-up). Round 2's
  /// verification never captured whether the cap the semaphore imposes was
  /// ever actually approached at runtime; this is the missing signal —
  /// alongside the watcher's tracked-entity count and construction time
  /// (see watcher_telemetry.dart), the Settings telemetry section shows
  /// whether the process ceiling itself was ever the bottleneck during a
  /// future incident, not just whether it structurally exists.
  int get peakRunning => _peakRunning;

  int get maxConcurrent => _maxConcurrent;

  Future<T> run<T>(Future<T> Function() body) async {
    if (_running < _maxConcurrent) {
      // Slot free — claim it synchronously so no other concurrent caller
      // can also see a free slot before this one is accounted for.
      _running++;
      if (_running > _peakRunning) _peakRunning = _running;
    } else {
      // No free slot: queue and wait. The slot is reserved (i.e. `_running`
      // is incremented) by whoever wakes this waiter — see the `finally`
      // block below — NOT here, otherwise a released slot could be
      // observed as free by both a new `run()` call and the woken waiter
      // (the waiter's continuation resumes asynchronously as a microtask,
      // leaving a window where `_running` had already been decremented but
      // not yet re-incremented). That race let 7 processes run under a
      // limit of 6 — caught by project_scanner_concurrency_test.dart.
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    try {
      return await body();
    } finally {
      if (_waiters.isNotEmpty) {
        // Hand this slot directly to the next waiter — `_running` stays
        // unchanged (one holder's slot becomes the next holder's slot).
        _waiters.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}

/// The app-wide default semaphore instance. All production call sites use
/// this; tests may construct their own [ProcessSemaphore] and pass it via
/// [runProcessWithTimeout]'s `semaphore` parameter instead of mutating this
/// global.
final ProcessSemaphore globalProcessSemaphore = ProcessSemaphore();

/// Runs a process with a hard timeout that actually terminates the child,
/// gated by [semaphore] (defaults to [globalProcessSemaphore]) so no more
/// than [ProcessSemaphore.maxConcurrent] processes run at once app-wide.
///
/// The previous per-service `Future.any` pattern raced `Process.run` against a
/// delayed [TimeoutException] but left the spawned process running when the
/// race was lost. Under system load git calls exceed the timeout, every
/// timed-out call leaked a live process, and the leaked processes increased
/// load further — a feedback loop that exhausted the per-user process limit
/// (EAGAIN in every Claude session, incident 2026-08-15/16).
///
/// This helper uses [Process.start] so the child can be killed with SIGKILL
/// when the timeout elapses. It still throws [TimeoutException] afterwards,
/// preserving the error contract callers already handle.
///
/// `runInShell: true` matches the codebase convention (macOS GUI apps do not
/// inherit Homebrew's PATH); arguments stay in list form, never interpolated
/// into a shell string.
Future<ProcessResult> runProcessWithTimeout(
  String executable,
  List<String> arguments,
  String workingDirectory, {
  Duration timeout = const Duration(seconds: 5),
  ProcessSemaphore? semaphore,
}) {
  final gate = semaphore ?? globalProcessSemaphore;
  return gate.run(
    () => _runProcess(executable, arguments, workingDirectory, timeout),
  );
}

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
  String workingDirectory,
  Duration timeout,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: true,
  );

  const encoding = SystemEncoding();
  final stdoutFuture = process.stdout.transform(encoding.decoder).join();
  final stderrFuture = process.stderr.transform(encoding.decoder).join();

  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    await killProcessTree(process.pid);
    // Drain the streams so the OS pipes are released even on the error path.
    unawaited(stdoutFuture.catchError((_) => ''));
    unawaited(stderrFuture.catchError((_) => ''));
    throw TimeoutException('$executable hat zu lange gedauert', timeout);
  }

  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;
  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

/// Kills [rootPid] and every descendant process, not just the direct child.
///
/// `runInShell: true` (this project's convention — macOS GUI apps don't
/// inherit Homebrew's PATH) means [rootPid] is the intermediate `sh -c`
/// process, not necessarily the real payload. A plain `process.kill()`
/// (SIGKILL on just that pid) only terminates that shell; any grandchild it
/// forked internally — a `gh` credential helper, a `vercel` Node process, or
/// any command that itself backgrounds work — survives as an orphan.
/// Demonstrated by the round-3 report's `kill_probe.dart`: after
/// `process.kill(SIGKILL)`, the direct child was dead but a grandchild
/// remained alive, plus a leftover `sleep 300`. This corrects the round-2
/// postmortem's "no intermediate shell" claim, which held only for commands
/// that never fork their own children (e.g. plain `git`), not for `gh`/`vercel`.
///
/// Walks the process tree via `pgrep -P <pid>` (list direct children),
/// recursively, collecting every pid found before killing any of them —
/// avoids missing a child whose parent already exited by the time it's
/// checked. Chosen over POSIX process groups (`setsid` + negative-pid
/// `kill(-pgid, ...)`) because macOS has no `setsid` CLI binary (Linux-only)
/// and `Process.start` does not put children in their own process group by
/// default — confirmed empirically: a spawned shell's pgid matched the
/// parent Dart process's own session group, not its own pid, so a
/// negative-pid kill would have targeted the wrong (much larger) group.
/// `pgrep -P` needs no such setup and is available on macOS by default.
///
/// Best-effort: if `pgrep` itself is unavailable, errors, or hangs (bounded
/// by a 2s timeout per call so a stuck `pgrep` can never block the reap
/// loop indefinitely), still kills whatever pids were already discovered
/// (never throws).
///
/// KNOWN LIMITATION (review round 1, Reinhard probe 1c-2): a grandchild
/// that gets reparented to `launchd` (pid 1) BEFORE this walk reaches it
/// survives, because `pgrep -P <pid>` can no longer find it under its
/// original (now-vanished) intermediate parent — the process tree this
/// function walks has already changed shape by the time it's read.
/// Demonstrated with a detached background job (`( sleep 300 & )`) that
/// completes its reparent before the timeout fires. Deliberately NOT
/// addressed with a second, name-based kill pass (e.g. matching on the
/// original command line under launchd): the risk of a false-positive
/// match killing an unrelated process the user is running is judged worse
/// than the narrow window this leaves open. Accepted as a residual risk,
/// not a silent gap — documented here so it isn't rediscovered as "new"
/// in a future incident.
Future<void> killProcessTree(int rootPid) async {
  final toKill = <int>[rootPid];
  final frontier = <int>[rootPid];

  while (frontier.isNotEmpty) {
    final pid = frontier.removeLast();
    try {
      final result = await Process.run('pgrep', ['-P', '$pid']).timeout(
        const Duration(seconds: 2),
        onTimeout: () => ProcessResult(0, 1, '', ''),
      );
      if (result.exitCode == 0) {
        final childPids = (result.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(int.parse);
        toKill.addAll(childPids);
        frontier.addAll(childPids);
      }
    } catch (_) {
      // pgrep unavailable/errored — proceed with whatever was found so far.
    }
  }

  for (final pid in toKill) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}
