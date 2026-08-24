import 'dart:developer' as developer;
import 'dart:io';

import 'package:pro_orc/data/services/process_runner.dart';

/// Result of a GitHub `delete_repo` OAuth scope pre-flight check.
///
/// Distinguishes "scope present" from three flavors of "cannot delete right
/// now": the scope is explicitly absent, the `gh` CLI itself is unavailable
/// (not installed / not logged in), or the check itself failed (network
/// error, timeout, or unparseable output). Callers that only care about
/// "can I proceed?" should treat every value except [present] as blocking.
enum GhScopeStatus {
  /// `delete_repo` scope confirmed present in the active `gh` session.
  present,

  /// Logged in via `gh`, but `delete_repo` scope is absent.
  missing,

  /// `gh` is not installed or not logged in at all
  /// (`GhDetectionService.isAvailable() == false`). Distinct from [missing]
  /// so the UI layer can show a different popup body and hide the
  /// `gh auth refresh` action, which would be misleading here.
  cliUnavailable,

  /// The pre-flight check itself failed (process error, timeout, or output
  /// that could not be parsed as a `gh auth status` scopes line) —
  /// independent of the actual scope state. Callers must treat this the
  /// same as [missing] (blocked), never as [present].
  checkFailed,
}

/// Runs a shell command and returns its result. Matches the subset of
/// [Process.run] this service depends on, so tests can inject a fake runner
/// that returns canned [ProcessResult] fixtures without a real `gh` binary.
///
/// Named distinctly from `external_deletion_service.dart`'s own
/// `ProcessRunner` typedef (different signature) to avoid an ambiguous
/// import when both services are used together.
typedef GhAuthStatusRunner =
    Future<ProcessResult> Function(
      String command,
      List<String> args, {
      Duration? timeout,
    });

/// Default [GhAuthStatusRunner]: runs the real command via
/// [runProcessWithTimeout] (process-storm round 3, WP2 — routes through the
/// app-wide [ProcessSemaphore] instead of a raw [Process.run], and reaps
/// `gh`'s own credential-helper children via [killProcessTree] if it ever
/// hangs). `runInShell: true` is `runProcessWithTimeout`'s fixed convention
/// (macOS GUI apps don't inherit Homebrew PATH). The [timeout] parameter is
/// accepted for signature compatibility but enforced by the caller via
/// [Future.timeout], not here — passed through so a single hang is bounded
/// at both layers.
Future<ProcessResult> _defaultProcessRunner(
  String command,
  List<String> args, {
  Duration? timeout,
}) {
  return runProcessWithTimeout(
    command,
    args,
    '.',
    timeout: timeout ?? const Duration(seconds: 5),
  );
}

/// Detects whether the GitHub CLI is installed, the user is logged in, and
/// (for destructive operations) whether the active session holds the
/// `delete_repo` OAuth scope.
///
/// Uses `which gh` to check for the binary and `gh auth status` to confirm
/// an active login and inspect granted scopes. All commands use
/// `runInShell: true` (macOS GUI apps don't inherit Homebrew PATH).
///
/// The [whichCommand], [ghCommand], and [authStatusRunner] parameters enable
/// testing with nonexistent/fake binaries or canned text fixtures, to verify
/// error handling and scope parsing without depending on the real CLI's
/// installation, login, or scope state.
class GhDetectionService {
  static const Duration _defaultAuthStatusTimeout = Duration(seconds: 10);

  final String _whichCommand;
  final String _ghCommand;
  final GhAuthStatusRunner _authStatusRunner;
  final Duration _authStatusTimeout;

  const GhDetectionService({
    String whichCommand = 'which',
    String ghCommand = 'gh',
    GhAuthStatusRunner authStatusRunner = _defaultProcessRunner,
    Duration authStatusTimeout = _defaultAuthStatusTimeout,
  }) : _whichCommand = whichCommand,
       _ghCommand = ghCommand,
       _authStatusRunner = authStatusRunner,
       _authStatusTimeout = authStatusTimeout;

  /// Check if the GitHub CLI is installed AND the user is logged in.
  ///
  /// Returns `true` only when both `which gh` and `gh auth status` exit 0.
  /// Returns `false` (never throws) if the binary is missing, the user is
  /// not logged in, or any error occurs.
  Future<bool> isAvailable() async {
    try {
      final whichResult = await runProcessWithTimeout(_whichCommand, [
        _ghCommand,
      ], '.', timeout: _authStatusTimeout);
      if (whichResult.exitCode != 0) return false;

      final authResult = await runProcessWithTimeout(_ghCommand, [
        'auth',
        'status',
      ], '.', timeout: _authStatusTimeout);
      return authResult.exitCode == 0;
    } catch (e) {
      developer.log(
        'Failed to check gh CLI availability: $e',
        name: 'gh_detection_service',
      );
      return false;
    }
  }

  /// Pre-flight check for the `delete_repo` OAuth scope on the active `gh`
  /// session.
  ///
  /// Runs `gh auth status`, captures its text output (`gh` prints the
  /// human-readable status block to stderr, not stdout — both streams are
  /// inspected), and parses the `Token scopes:` line for a `delete_repo`
  /// entry matched on token boundaries (not a naive substring match, so a
  /// scope like `not_delete_repo_related` is never mistaken for
  /// `delete_repo`).
  ///
  /// Never throws. Returns:
  /// - [GhScopeStatus.cliUnavailable] if `gh` is not installed or not logged
  ///   in ([isAvailable] would return `false`).
  /// - [GhScopeStatus.present] if `delete_repo` is found in the scopes line.
  /// - [GhScopeStatus.missing] if logged in but `delete_repo` is absent.
  /// - [GhScopeStatus.checkFailed] if the check itself errors, times out, or
  ///   the output cannot be parsed as a scopes line — a distinct reason code
  ///   that callers must still treat as blocked, same as [missing].
  Future<GhScopeStatus> checkDeleteRepoScope() async {
    if (!await isAvailable()) {
      return GhScopeStatus.cliUnavailable;
    }

    try {
      final result = await _authStatusRunner(_ghCommand, [
        'auth',
        'status',
      ], timeout: _authStatusTimeout).timeout(_authStatusTimeout);

      final combinedOutput = '${result.stdout}\n${result.stderr}';
      return _parseScopeStatus(combinedOutput);
    } catch (e) {
      developer.log(
        'Failed to check gh delete_repo scope: $e',
        name: 'gh_detection_service',
      );
      return GhScopeStatus.checkFailed;
    }
  }

  /// Returns the login name of the currently active `gh` account (the
  /// account `gh auth refresh` would actually operate on), or `null` if it
  /// cannot be determined (`gh` unavailable, output unparseable, no line
  /// marked as active, or the runner throws).
  ///
  /// `gh auth status` can list several accounts per host when multiple are
  /// logged in; only the one followed by `- Active account: true` is the
  /// one `gh auth refresh` would touch. Callers must treat `null`
  /// conservatively — as "cannot determine, assume no mismatch" — never as
  /// evidence of a mismatch (2026-07-22-gh-auth-refresh-wrong-account).
  ///
  /// Never throws.
  Future<String?> getActiveAccountLogin() async {
    if (!await isAvailable()) {
      return null;
    }

    try {
      final result = await _authStatusRunner(_ghCommand, [
        'auth',
        'status',
      ], timeout: _authStatusTimeout).timeout(_authStatusTimeout);

      final combinedOutput = '${result.stdout}\n${result.stderr}';
      return _parseActiveAccountLogin(combinedOutput);
    } catch (e) {
      developer.log(
        'Failed to determine active gh account: $e',
        name: 'gh_detection_service',
      );
      return null;
    }
  }

  /// Parses a `gh auth status` text block for the account block that is
  /// immediately followed by `- Active account: true` and returns its login
  /// name (the token after `account ` and before the trailing `(...)`).
  ///
  /// `gh` prints one block per logged-in account, e.g.:
  /// ```
  ///   ✓ Logged in to github.com account octocat (keyring)
  ///   - Active account: true
  /// ```
  /// and can print several such blocks when multiple accounts are logged in
  /// on the same host. Splits the output at each `account <login> (...)`
  /// login line first, so each candidate's own `Active account:` marker is
  /// only matched within ITS OWN block — never bleeding into the next
  /// account's block, which is what a single non-greedy `[\s\S]*?` regex
  /// across the whole output would do once more than one account is logged
  /// in.
  static String? _parseActiveAccountLogin(String output) {
    final loginLine = RegExp(r'account\s+(\S+)\s*\([^)]*\)');
    final matches = loginLine.allMatches(output).toList();
    if (matches.isEmpty) return null;

    for (var i = 0; i < matches.length; i++) {
      final blockStart = matches[i].end;
      final blockEnd = i + 1 < matches.length
          ? matches[i + 1].start
          : output.length;
      final block = output.substring(blockStart, blockEnd);
      if (RegExp(r'-\s*Active account:\s*true').hasMatch(block)) {
        return matches[i].group(1);
      }
    }
    return null;
  }

  /// Parses a `gh auth status` text block for the `Token scopes:` line and
  /// checks whether `delete_repo` appears as a whole scope token.
  static GhScopeStatus _parseScopeStatus(String output) {
    final scopesLineMatch = RegExp(r'Token scopes:\s*(.+)').firstMatch(output);
    if (scopesLineMatch == null) {
      // No scopes line at all — unparseable output, treat as a failed check
      // rather than silently reporting "missing" (distinct failure reason).
      return GhScopeStatus.checkFailed;
    }

    final scopesList = scopesLineMatch.group(1)!;
    // Scopes are single-quoted and comma-separated, e.g.
    // "'gist', 'read:org', 'repo', 'delete_repo'". Extract each quoted
    // token individually so 'not_delete_repo_related' can never match as
    // 'delete_repo' via substring search.
    final scopeTokens = RegExp(
      r"'([^']+)'",
    ).allMatches(scopesList).map((m) => m.group(1)).toSet();

    return scopeTokens.contains('delete_repo')
        ? GhScopeStatus.present
        : GhScopeStatus.missing;
  }
}
