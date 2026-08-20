import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:meta/meta.dart';

import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/services/process_runner.dart';

/// Reads git metadata (last commit + GitHub remote URL) for a project directory.
///
/// All [Process.run] calls use [runInShell: true] because macOS GUI apps do not
/// have Homebrew in PATH. The [gitBinary] parameter allows overriding the git
/// binary path (default: 'git').
///
/// Convention (applies to every `Process.run` call in this codebase): when
/// `runInShell: true`, never pass a single interpolated command string —
/// always pass a fixed executable with list-form arguments. A shell-interpolated
/// string would let a crafted project path/argument break out into arbitrary
/// shell syntax; list-form args are passed directly to the process, not
/// re-parsed by a shell.
///
/// Returns [GitData.empty] on any error: not a git repo, timeout, no commits,
/// nonexistent directory.
Future<GitData> readGitData(
  String projectPath, {
  String gitBinary = 'git',
}) async {
  try {
    // --- Last commit ---
    final logResult = await _runWithTimeout(gitBinary, [
      'log',
      '--format=%H%n%aI%n%s',
      '-1',
    ], projectPath);

    if (logResult.exitCode != 0 ||
        (logResult.stdout as String).trim().isEmpty) {
      return GitData.empty;
    }

    final lines = (logResult.stdout as String).trim().split('\n');
    if (lines.length < 3) return GitData.empty;

    final fullHash = lines[0].trim();
    final isoDate = lines[1].trim();
    final subject = lines.sublist(2).join('\n').trim();

    if (fullHash.isEmpty) return GitData.empty;

    final shortHash = fullHash.length >= 7
        ? fullHash.substring(0, 7)
        : fullHash;
    final commitDate = DateTime.tryParse(isoDate);

    // --- Remote URL ---
    final remoteResult = await _runWithTimeout(gitBinary, [
      'remote',
      'get-url',
      'origin',
    ], projectPath);

    String? githubUrl;
    if (remoteResult.exitCode == 0) {
      final remoteUrl = (remoteResult.stdout as String).trim();
      githubUrl = _remoteToGithubUrl(remoteUrl);
    }

    return GitData(
      lastCommitHash: shortHash,
      lastCommitDate: commitDate,
      lastCommitMessage: subject.isNotEmpty ? subject : null,
      githubUrl: githubUrl,
    );
  } catch (e) {
    developer.log(
      'Failed to read git data for $projectPath: $e',
      name: 'git_reader',
    );
    return GitData.empty;
  }
}

/// Normalizes a git remote URL to a GitHub HTTPS URL, or returns null if the
/// remote is not a GitHub remote.
///
/// Supported formats:
/// - SSH:   `git@github.com:owner/repo.git` → `https://github.com/owner/repo`
/// - HTTPS: `https://github.com/owner/repo.git` → `https://github.com/owner/repo`
@visibleForTesting
String? remoteToGithubUrl(String remoteUrl) => _remoteToGithubUrl(remoteUrl);

String? _remoteToGithubUrl(String remoteUrl) {
  // SSH format: git@github.com:owner/repo.git
  final sshMatch = RegExp(
    r'^git@github\.com:(.+?)(?:\.git)?$',
  ).firstMatch(remoteUrl.trim());
  if (sshMatch != null) {
    return 'https://github.com/${sshMatch.group(1)}';
  }

  // HTTPS format: https://github.com/owner/repo.git
  // Also matches userinfo-prefixed remotes, e.g. https://x-access-token:TOKEN@github.com/owner/repo.git
  final httpsMatch = RegExp(
    r'^https://(?:[^@/]+@)?github\.com/(.+?)(?:\.git)?/?$',
  ).firstMatch(remoteUrl.trim());
  if (httpsMatch != null) {
    return 'https://github.com/${httpsMatch.group(1)}';
  }

  return null;
}

/// Runs a process with a 5-second timeout that kills the child on expiry
/// (see [runProcessWithTimeout] for the leak this prevents).
Future<ProcessResult> _runWithTimeout(
  String executable,
  List<String> arguments,
  String workingDirectory,
) {
  return runProcessWithTimeout(executable, arguments, workingDirectory);
}
