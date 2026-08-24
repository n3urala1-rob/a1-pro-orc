/// Command builders, URL parsers, and the execution layer for active
/// external-resource deletion (Vercel projects, GitHub repositories, Claude
/// memory directories).
///
/// The builders never spawn a process — they only compute the exact
/// argument list that the execution functions below pass to
/// `Process.run(command, args, runInShell: true)`. Dynamic values (project
/// names, owner/repo, paths) are ALWAYS returned as discrete list elements,
/// never interpolated into a single command string, so shell metacharacters
/// in a resource identifier cannot break out of the intended argument
/// boundary. This mirrors the escaping discipline established in
/// `deletion_service.dart` (`_appleScriptEscape` / `buildFinderDeleteScript`)
/// per the project's 2026-07-13 command-injection lesson.
library;

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:pro_orc/data/models/deletion_result.dart';
import 'package:pro_orc/data/models/external_resource.dart';
import 'package:pro_orc/data/services/process_runner.dart';

/// Builds the argument list for `vercel project remove <name>`.
///
/// [projectName] is passed as a single, discrete argument — it is never
/// concatenated into a shell string, so metacharacters (`;`, `"`, `` ` ``,
/// `$()`) in the name cannot escape the argument boundary or chain an
/// additional command.
///
/// NOTE (FR-014 deviation, 2026-07-20): the spec's `--yes` flag does not
/// exist on the locally verified `vercel` CLI (51.8.0) — `vercel project
/// remove --help` lists no `--yes`/`--force`/`--confirm` flag, and
/// `--non-interactive` does not suppress the "Are you sure? (y/N)" prompt
/// either. [deleteVercel] answers that interactive prompt itself by
/// writing `"y\n"` to the child process's stdin (verified: piping `y`
/// answers it and the command then completes and exits). The orchestrator
/// approved this workaround as consistent with FR-013 (CLI-auth-only, no
/// new token) since the destructive action was already double-confirmed
/// in the dialog before this command ever runs.
List<String> buildVercelDeleteArgs(String projectName) {
  return ['project', 'remove', projectName];
}

/// Builds the argument list for `gh repo delete <owner>/<repo> --yes`.
///
/// [ownerRepo] (already in `<owner>/<repo>` form) is passed as a single,
/// discrete argument for the same reason as [buildVercelDeleteArgs].
List<String> buildGhDeleteArgs(String ownerRepo) {
  return ['repo', 'delete', ownerRepo, '--yes'];
}

/// Path segments that are known Vercel routes rather than `<scope>/<project>`
/// dashboard paths — e.g. `vercel.com/new` is the "create a new project"
/// boilerplate link that every `create-next-app` README ships by default
/// (`utm_campaign=create-next-app-readme`), and `vercel.com/blog/<slug>` is
/// a marketing blog post that legitimately gets linked from research/notes
/// files (e.g. `vercel.com/blog/common-mistakes-with-the-next-js-app-router-
/// and-how-to-fix-them`), not a dashboard project
/// (2026-07-23-vercel-blog-url-classified-as-project-2). A URL whose first
/// segment matches one of these is never a real, deletable project — mirrors
/// the `firebase.google.com` docs-vs-console distinction in
/// `resource_detector.dart`'s `_classifyUrl`, applied to Vercel's own set of
/// well-known non-project top-level marketing/docs routes.
const _nonProjectVercelSegments = {
  'new',
  'dashboard',
  'login',
  'signup',
  'blog',
  'docs',
  'templates',
  'guides',
  'changelog',
  'pricing',
  'contact',
  'help',
  'solutions',
  'resources',
  'about',
  'legal',
  'careers',
  'partners',
  'home',
  'security',
  'enterprise',
};

/// Validates that [uri] (already confirmed to be a `vercel.com` /
/// `*.vercel.com` host) points at a real `<scope>/<project>` dashboard page
/// rather than a generic/boilerplate Vercel link, and returns the derived
/// project name when it does.
///
/// This is the single source of truth for "is this a real Vercel project
/// URL" — used by both [deriveVercelProjectName] (deletion-command
/// generation) and `resource_detector.dart`'s classification, so the
/// dialog's display and the generated deletion command can never diverge
/// (2026-07-20-delete-dialog-resource-over-detection).
///
/// Returns `null` unless ALL of the following hold:
/// - no query parameters (a real dashboard project URL never carries one;
///   boilerplate/marketing links like `vercel.com/new?utm_...` do)
/// - at least two non-empty path segments (`<scope>/<project>` — a single
///   segment like `vercel.com/my-scope` names a scope, not a project)
/// - the first segment is not a known non-project route (see
///   [_nonProjectVercelSegments])
///
/// Deeper paths (e.g. `<scope>/<project>/deployments`) still validate — the
/// last segment is returned, preserving the pre-existing behavior for
/// nested dashboard pages (not part of this fix's scope).
String? _validateVercelProjectPath(Uri uri) {
  if (uri.query.isNotEmpty) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) return null;

  if (_nonProjectVercelSegments.contains(segments.first.toLowerCase())) {
    return null;
  }

  return segments.last;
}

/// Derives the Vercel project name from a stored dashboard URL of the form
/// `https://vercel.com/<scope>/<project-name>`.
///
/// Returns `null` when the name cannot be reliably derived — for deployment
/// URLs of the form `<project>-<hash>.vercel.app` (project name fused with a
/// hash in the hostname), and for any URL that does not validate as a real
/// dashboard project path per [_validateVercelProjectPath] (e.g. the
/// `vercel.com/new?utm_...` boilerplate link every `create-next-app` README
/// ships by default). Callers MUST fall back to hint-only display when this
/// returns `null`.
String? deriveVercelProjectName(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();

  // Deployment URLs (*.vercel.app) do not carry a derivable dashboard
  // project name in their path — the project name is fused with a hash in
  // the hostname (e.g. "my-app-abc123.vercel.app").
  if (host.endsWith('.vercel.app') || host == 'vercel.app') {
    return null;
  }

  if (host != 'vercel.com' && !host.endsWith('.vercel.com')) {
    return null;
  }

  return _validateVercelProjectPath(uri);
}

/// Returns `true` if [url] is a `vercel.com`/`*.vercel.com` URL that
/// validates as a real `<scope>/<project>` dashboard project path (see
/// [_validateVercelProjectPath]). Used by `resource_detector.dart` to
/// classify URLs consistently with [deriveVercelProjectName] so a URL is
/// never displayed as an active-delete "Vercel-Projekt" entry unless a
/// deletion command can actually be derived from it.
bool isVercelDashboardProjectUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  final host = uri.host.toLowerCase();
  if (host != 'vercel.com' && !host.endsWith('.vercel.com')) return false;

  return _validateVercelProjectPath(uri) != null;
}

/// Derives the `<owner>/<repo>` argument from a stored GitHub URL such as
/// `https://github.com/<owner>/<repo>`.
///
/// Returns `null` when fewer than two path segments are present (owner and
/// repo cannot both be determined).
String? deriveGhOwnerRepo(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();
  if (host != 'github.com' && !host.endsWith('.github.com')) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) return null;

  return '${segments[0]}/${segments[1]}';
}

/// Signature matching `Process.run` — injectable so tests can simulate CLI
/// exit codes/stderr without spawning real processes or depending on the
/// machine's actual `gh`/`vercel` login state.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

/// Routed through [runProcessWithTimeout] (process-storm round 3, WP2) —
/// closes a semaphore bypass AND adds a real timeout this call previously
/// lacked entirely (a bare `Process.run` never returns until the child
/// exits on its own). `gh repo delete` can legitimately take longer than
/// the git-read timeout elsewhere in the app, so a generous 30s budget is
/// used here rather than [runProcessWithTimeout]'s 5s default. [runInShell]
/// is accepted for signature compatibility with [ProcessRunner] but
/// `runProcessWithTimeout` always runs in shell (project convention), so a
/// caller passing `false` would only differ if such a caller existed —
/// none currently does.
Future<ProcessResult> defaultProcessRunner(
  String executable,
  List<String> arguments, {
  bool runInShell = true,
}) {
  return runProcessWithTimeout(
    executable,
    arguments,
    '.',
    timeout: const Duration(seconds: 30),
  );
}

/// Deletes the GitHub repository at [ownerRepo] (`<owner>/<repo>`) via
/// `gh repo delete <owner>/<repo> --yes`.
///
/// [ownerRepo] is passed as a single discrete argument (see
/// [buildGhDeleteArgs]) — never interpolated into a shell string. [runner]
/// defaults to real `Process.run` and is overridable for tests.
///
/// Maps `gh`'s exit code/stderr to a [DeletionResult]:
/// - exit 0 → [DeletionResult.success]
/// - stderr mentions the missing `delete_repo` scope →
///   [DeletionResult.missingScope] (checked BEFORE the not-found check —
///   `gh` can return a 404 message on repos it cannot even see due to
///   missing scope, so a scope error must not be misread as
///   already-deleted; verified against the real locally installed `gh` CLI,
///   which emits both signals together for an unscoped token).
/// - stderr indicates the repo doesn't exist ("not found" / "404") →
///   [DeletionResult.alreadyDeleted] (FR-017 — idempotent success)
/// - stderr indicates no valid login ("not logged in" / "authentication") →
///   [DeletionResult.notAuthenticated]
/// - anything else → [DeletionResult.genericFailure] with a stderr gist
Future<DeletionResult> deleteGh(
  String uri,
  String ownerRepo, {
  ProcessRunner runner = defaultProcessRunner,
}) async {
  try {
    final result = await runner(
      'gh',
      buildGhDeleteArgs(ownerRepo),
      runInShell: true,
    );

    if (result.exitCode == 0) {
      return DeletionResult.success(uri, ExternalResourceType.github);
    }

    final stderrText = result.stderr.toString();
    final stderrLower = stderrText.toLowerCase();

    if (stderrLower.contains('delete_repo')) {
      return DeletionResult.missingScope(uri, ExternalResourceType.github);
    }
    if (stderrLower.contains('not found') || stderrLower.contains('404')) {
      return DeletionResult.alreadyDeleted(uri, ExternalResourceType.github);
    }
    if (stderrLower.contains('not logged in') ||
        stderrLower.contains('authentication') ||
        stderrLower.contains('unauthorized')) {
      return DeletionResult.notAuthenticated(uri, ExternalResourceType.github);
    }

    return DeletionResult.genericFailure(
      uri,
      ExternalResourceType.github,
      stderrText,
    );
  } catch (e) {
    developer.log(
      'Failed to delete GitHub repo $ownerRepo: $e',
      name: 'external_deletion_service',
    );
    return DeletionResult.genericFailure(
      uri,
      ExternalResourceType.github,
      e.toString(),
    );
  }
}

/// The outcome of running a Vercel deletion child process to completion —
/// mirrors the fields of [ProcessResult] that [deleteVercel] needs.
class VercelProcessOutcome {
  final int exitCode;
  final String stderr;

  /// True if the process was killed after not finishing within the
  /// timeout — a distinct condition from a normal non-zero exit, since it
  /// means the CLI's interactive prompt behavior changed and the "y\n"
  /// answer no longer worked.
  final bool timedOut;

  const VercelProcessOutcome({
    required this.exitCode,
    required this.stderr,
    this.timedOut = false,
  });
}

/// Runs `vercel <arguments>`, answering its interactive "Are you sure?"
/// confirmation prompt by writing `"y\n"` to stdin (see the doc comment on
/// [buildVercelDeleteArgs] for why this is needed instead of a flag).
/// Injectable so tests can simulate CLI outcomes — including a timeout —
/// without spawning a real process or depending on the machine's actual
/// `vercel` login state.
typedef VercelProcessRunner =
    Future<VercelProcessOutcome> Function(List<String> arguments);

/// Default [VercelProcessRunner]: starts the real `vercel` CLI, writes
/// `"y\n"` to its stdin once, and waits up to [timeout] for it to exit.
/// If it has not exited by then (e.g. a future CLI version prompts
/// differently and "y\n" doesn't answer it), the process is killed and
/// [VercelProcessOutcome.timedOut] is true — this function never blocks
/// indefinitely.
///
/// Runs under `runInShell: true` (required so the spawned process inherits
/// Homebrew's PATH — see the project's `Process.run` convention), which
/// means the PID `Process.start` returns is the intermediate shell, not
/// `vercel` itself. A plain SIGTERM/SIGKILL `process.kill()` on that PID
/// only reaches the shell, not any grandchild it forked (`vercel`'s own
/// Node process) — the round-2 postmortem's claim that SIGKILL "also
/// reaches the shell's child on `sh -c` termination in practice" was
/// disproven empirically by process-storm round 3's `kill_probe.dart`
/// (a real orphaned grandchild survived). On timeout this now kills the
/// WHOLE process tree via [killProcessTree] (see process_runner.dart for
/// why a tree walk was chosen over POSIX process groups) and then always
/// awaits [Process.exitCode] — with its own short guard timeout — so the
/// process is reaped rather than left as a zombie either way.
Future<VercelProcessOutcome> defaultVercelProcessRunner(
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final process = await Process.start('vercel', arguments, runInShell: true);

  final stderrBuffer = StringBuffer();
  final stderrSub = process.stderr
      .transform(const SystemEncoding().decoder)
      .listen(stderrBuffer.write);
  // vercel also prints the confirmation prompt to stdout in some
  // versions; drain it so the process is never blocked on a full pipe.
  final stdoutSub = process.stdout.listen((_) {});

  try {
    try {
      process.stdin.writeln('y');
      await process.stdin.close();
    } catch (_) {
      // The process may have already exited (e.g. an immediate auth
      // failure) before we could write/close stdin — a broken pipe here
      // is not a runner failure, the exit-code/stderr read below still
      // determines the real outcome.
    }

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return VercelProcessOutcome(
        exitCode: exitCode,
        stderr: stderrBuffer.toString(),
      );
    } on TimeoutException {
      await killProcessTree(process.pid);
      // Always reap after kill so the child never lingers as a zombie —
      // bounded by its own short guard in case even SIGKILL doesn't land
      // (e.g. a wedged shell wrapper).
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      return VercelProcessOutcome(
        exitCode: -1,
        stderr: stderrBuffer.toString(),
        timedOut: true,
      );
    }
  } finally {
    await stderrSub.cancel();
    await stdoutSub.cancel();
  }
}

/// Deletes the Vercel project [projectName] via
/// `vercel project remove <name>` (see [buildVercelDeleteArgs] for the
/// FR-014 `--yes` deviation). [runner] defaults to
/// [defaultVercelProcessRunner] and is overridable for tests.
///
/// Maps the CLI's exit code/stderr to a [DeletionResult]:
/// - [VercelProcessOutcome.timedOut] → [DeletionResult.genericFailure]
///   with the reason "Vercel-CLI hat nicht wie erwartet reagiert" (the
///   CLI's prompt behavior changed and the "y\n" answer no longer works —
///   never blocks the flow indefinitely).
/// - exit 0 → [DeletionResult.success]
/// - stderr indicates no valid login/token ("not valid" / "not
///   authorized" / "not logged in") → [DeletionResult.notAuthenticated]
///   (checked BEFORE the not-found check, mirroring [deleteGh]'s ordering
///   discipline — an auth failure must never be misread as
///   already-deleted just because the CLI also can't confirm the project
///   exists).
/// - stderr indicates the project doesn't exist ("no such project
///   exists") → [DeletionResult.alreadyDeleted] (FR-017 — idempotent
///   success)
/// - anything else → [DeletionResult.genericFailure] with a stderr gist
Future<DeletionResult> deleteVercel(
  String uri,
  String projectName, {
  VercelProcessRunner runner = defaultVercelProcessRunner,
}) async {
  try {
    final outcome = await runner(buildVercelDeleteArgs(projectName));

    if (outcome.timedOut) {
      return DeletionResult.genericFailure(
        uri,
        ExternalResourceType.vercel,
        'Vercel-CLI hat nicht wie erwartet reagiert',
      );
    }

    if (outcome.exitCode == 0) {
      return DeletionResult.success(uri, ExternalResourceType.vercel);
    }

    final stderrLower = outcome.stderr.toLowerCase();

    if (stderrLower.contains('not logged in') ||
        stderrLower.contains('not authorized') ||
        stderrLower.contains('token provided') ||
        stderrLower.contains('credentials')) {
      return DeletionResult.notAuthenticated(uri, ExternalResourceType.vercel);
    }
    if (stderrLower.contains('no such project exists') ||
        stderrLower.contains('project not found') ||
        stderrLower.contains('does not exist')) {
      return DeletionResult.alreadyDeleted(uri, ExternalResourceType.vercel);
    }

    return DeletionResult.genericFailure(
      uri,
      ExternalResourceType.vercel,
      outcome.stderr,
    );
  } catch (e) {
    developer.log(
      'Failed to delete Vercel project $projectName: $e',
      name: 'external_deletion_service',
    );
    return DeletionResult.genericFailure(
      uri,
      ExternalResourceType.vercel,
      e.toString(),
    );
  }
}

/// Deletes the Claude memory directory at [dir] from the filesystem.
///
/// Filesystem-only — no CLI/login dependency, matching
/// `delete_project_dialog.dart`'s `_isActivelyDeletable` treatment of
/// `claudeMemory` as always eligible (FR-005). A directory that no longer
/// exists is reported as [DeletionResult.alreadyDeleted] (FR-017), not a
/// failure.
Future<DeletionResult> deleteClaudeMemory(String uri, String dir) async {
  try {
    final directory = Directory(dir);
    if (!await directory.exists()) {
      return DeletionResult.alreadyDeleted(
        uri,
        ExternalResourceType.claudeMemory,
      );
    }

    await directory.delete(recursive: true);
    return DeletionResult.success(uri, ExternalResourceType.claudeMemory);
  } catch (e) {
    developer.log(
      'Failed to delete Claude memory dir $dir: $e',
      name: 'external_deletion_service',
    );
    return DeletionResult.genericFailure(
      uri,
      ExternalResourceType.claudeMemory,
      e.toString(),
    );
  }
}
