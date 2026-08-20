import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:pro_orc/data/services/process_runner.dart';

/// Runs a shell command and returns its result. Matches the subset of
/// [Process.run] this service depends on, so tests can inject a fake runner
/// that returns canned [ProcessResult] fixtures without a real `vercel`
/// binary — mirrors `gh_detection_service.dart`'s `GhAuthStatusRunner`.
typedef VercelTeamsRunner =
    Future<ProcessResult> Function(
      String command,
      List<String> args, {
      Duration? timeout,
    });

/// Default [VercelTeamsRunner]: runs the real command via
/// [runProcessWithTimeout] — gated by [globalProcessSemaphore] like every
/// other spawn in the app, and, unlike the old raw [Process.run] call, able
/// to actually SIGKILL the child if it hangs rather than merely stop
/// awaiting it. Root cause 4 of the 2026-08-20 process storm: the previous
/// `.timeout()` wrapper around a bare `Process.run` stopped Dart from
/// waiting but left the process running.
Future<ProcessResult> _defaultTeamsRunner(
  String command,
  List<String> args, {
  Duration? timeout,
}) {
  return runProcessWithTimeout(
    command,
    args,
    '.',
    timeout: timeout ?? const Duration(seconds: 10),
  );
}

/// Detects whether the Vercel CLI is installed and the user is logged in.
///
/// Uses `which vercel` to check for the binary and `vercel whoami` to
/// confirm an active login. Both commands use `runInShell: true` (macOS
/// GUI apps don't inherit Homebrew PATH).
///
/// The [whichCommand] and [vercelCommand] parameters enable testing with
/// nonexistent/fake binaries to verify error handling without depending on
/// the real CLI's installation or auth state.
class VercelDetectionService {
  static const Duration _defaultTeamsTimeout = Duration(seconds: 10);

  final String _whichCommand;
  final String _vercelCommand;
  final VercelTeamsRunner _teamsRunner;
  final Duration _teamsTimeout;

  const VercelDetectionService({
    String whichCommand = 'which',
    String vercelCommand = 'vercel',
    VercelTeamsRunner teamsRunner = _defaultTeamsRunner,
    Duration teamsTimeout = _defaultTeamsTimeout,
  }) : _whichCommand = whichCommand,
       _vercelCommand = vercelCommand,
       _teamsRunner = teamsRunner,
       _teamsTimeout = teamsTimeout;

  /// Check if the Vercel CLI is installed AND the user is logged in.
  ///
  /// Returns `true` only when both `which vercel` and `vercel whoami` exit
  /// 0. Returns `false` (never throws) if the binary is missing, the user
  /// is not logged in, or any error occurs.
  Future<bool> isAvailable() async {
    try {
      final whichResult = await runProcessWithTimeout(
        _whichCommand,
        [_vercelCommand],
        '.',
        timeout: _teamsTimeout,
      );
      if (whichResult.exitCode != 0) return false;

      final whoamiResult = await runProcessWithTimeout(
        _vercelCommand,
        ['whoami'],
        '.',
        timeout: _teamsTimeout,
      );
      return whoamiResult.exitCode == 0;
    } catch (e) {
      developer.log(
        'Failed to check Vercel CLI availability: $e',
        name: 'vercel_detection_service',
      );
      return false;
    }
  }

  /// Resolves Vercel's opaque team [orgId] (e.g. `team_yABWsykG53iYgFAWXpvnYn7m`)
  /// to its human-readable dashboard URL slug (e.g.
  /// `roberts-projects-fb13711c`) via `vercel teams list --format json`.
  ///
  /// Vercel dashboard URLs (`vercel.com/<slug>/<project>`) require the team
  /// slug, not the opaque id — see
  /// `2026-07-23-vercel-url-uses-orgid-not-slug.md`. This is the only place
  /// that resolution happens; callers (`resource_detector.dart`) are
  /// responsible for caching the result across calls within a session so
  /// this CLI call isn't repeated per project.
  ///
  /// Never throws. Returns `null` (never a broken/half-built value) when:
  /// - the CLI is unavailable ([isAvailable] is `false`)
  /// - the process errors, times out, or its output cannot be parsed as
  ///   `{"teams": [{"id": ..., "slug": ...}, ...]}`
  /// - no listed team matches [orgId]
  ///
  /// Callers must treat `null` as "resolution failed" and fall back
  /// gracefully — never block or crash on it.
  Future<String?> resolveTeamSlug(String orgId) async {
    if (!await isAvailable()) return null;

    try {
      final result = await _teamsRunner(_vercelCommand, [
        'teams',
        'list',
        '--format',
        'json',
      ], timeout: _teamsTimeout).timeout(_teamsTimeout);

      if (result.exitCode != 0) return null;

      return _parseTeamSlug(result.stdout.toString(), orgId);
    } catch (e) {
      developer.log(
        'Failed to resolve Vercel team slug for $orgId: $e',
        name: 'vercel_detection_service',
      );
      return null;
    }
  }

  /// Parses `vercel teams list --format json` stdout for the team whose
  /// `id` matches [orgId] and returns its `slug`. Returns `null` on any
  /// unparseable/unexpected shape rather than throwing.
  static String? _parseTeamSlug(String stdout, String orgId) {
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map<String, dynamic>) return null;

      final teams = decoded['teams'];
      if (teams is! List) return null;

      for (final team in teams) {
        if (team is! Map) continue;
        if (team['id'] == orgId) {
          final slug = team['slug'];
          if (slug is String && slug.isNotEmpty) return slug;
        }
      }
      return null;
    } catch (e) {
      developer.log(
        'Failed to parse `vercel teams list` output: $e',
        name: 'vercel_detection_service',
      );
      return null;
    }
  }
}
