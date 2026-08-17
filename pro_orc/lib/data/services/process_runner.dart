import 'dart:async';
import 'dart:io';

/// Runs a process with a hard timeout that actually terminates the child.
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
}) async {
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
    process.kill(ProcessSignal.sigkill);
    // Drain the streams so the OS pipes are released even on the error path.
    unawaited(stdoutFuture.catchError((_) => ''));
    unawaited(stderrFuture.catchError((_) => ''));
    throw TimeoutException('Git-Befehl hat zu lange gedauert', timeout);
  }

  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;
  return ProcessResult(process.pid, exitCode, stdout, stderr);
}
