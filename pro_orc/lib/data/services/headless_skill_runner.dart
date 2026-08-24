import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pro_orc/data/services/claude_detection_service.dart';

/// Terminal (or in-flight) outcome of a headless skill run. Mirrors the
/// `status` text column in `SkillRunTable` (schema v7) — stored as text
/// there for forward-compatible migrations, this enum is the canonical,
/// type-safe representation the rest of the app works with.
enum SkillRunStatus { running, success, failure, timeout, cancelled }

/// Thrown by [HeadlessSkillRunner.start] when the `claude` CLI is not
/// installed (or not on PATH) — detected via [ClaudeDetectionService]
/// BEFORE any process is spawned, so no watchdog/claude process exists on
/// this path.
class ClaudeNotAvailableException implements Exception {
  const ClaudeNotAvailableException();

  @override
  String toString() =>
      'ClaudeNotAvailableException: claude CLI is not installed or not on PATH';
}

/// Result of a successful [HeadlessSkillRunner.start] call — the run has
/// been spawned (detached) and is now in flight. Does not indicate
/// completion; later waves poll the output file / persisted DB row, or
/// reconcile against these values after an app restart.
class SpawnResult {
  const SpawnResult({
    required this.pid,
    required this.processStartTime,
    required this.outputFilePath,
  });

  /// PID of the `claude -p` child (NOT the watchdog wrapper) — this is the
  /// value persisted to `SkillRunTable.pid` and what later reconciliation
  /// compares against real OS process state.
  final int pid;

  /// OS-reported process start time of [pid] at spawn time, read via `ps -o
  /// lstart=`. Persisted alongside [pid] so a later PID-reuse cannot be
  /// mistaken for the same run — see [readProcessStartTime].
  final DateTime processStartTime;

  /// Path to the file the watchdog redirects the `claude -p` child's
  /// stdout+stderr into. The process is detached, so this file — not a
  /// live stream — is how any output is ever observed.
  final String outputFilePath;
}

/// Spawns a headless `claude -p` skill run, fully detached from the Pro Orc
/// process, wrapped by `scripts/skill_watchdog.sh` so a hard timeout is
/// enforced at the process level (survives Pro Orc quitting — see FR-008/
/// FR-009 of spec 011).
///
/// Arguments are always passed as a discrete list, never interpolated into
/// a shell string — this class does not set `runInShell: true` for the
/// watchdog spawn, unlike [ClaudeDetectionService]/`process_runner.dart`'s
/// git/vercel spawns, which need shell PATH inheritance for a *visible*
/// Terminal window. There is no visible terminal here, so that rationale
/// does not apply, and avoiding a shell removes an entire class of
/// injection risk (2026-07-13 osascript command-injection lesson) even
/// though today's callers only ever pass code-curated, non-user-controlled
/// skill identifiers (FR-004 defense-in-depth).
class HeadlessSkillRunner {
  /// [claudeExecutable] and [watchdogScriptPath] are injectable test seams
  /// (mirrors [ClaudeDetectionService]'s `whichCommand` injection
  /// precedent) — production callers use the defaults. [timeout] defaults
  /// to the spec's 10-minute hard bound; tests override with a short
  /// duration so a broken watchdog fails fast instead of hanging CI.
  /// [claudeDetectionService] defaults to a real, unconfigured instance;
  /// tests inject one pointed at a nonexistent binary to exercise the
  /// CLI-missing path without needing the real CLI absent from the host.
  /// [outputDirectory] is where per-run output files are written; defaults
  /// to lazily resolving the app support directory at call time (never at
  /// construction, since that call requires the Flutter binding to be
  /// initialized) so tests can inject a temp directory instead.
  const HeadlessSkillRunner({
    this.claudeExecutable = 'claude',
    this.timeout = const Duration(minutes: 10),
    String? watchdogScriptPath,
    ClaudeDetectionService? claudeDetectionService,
    String? outputDirectory,
  }) : _watchdogScriptPath = watchdogScriptPath,
       _claudeDetectionService =
           claudeDetectionService ?? const ClaudeDetectionService(),
       _outputDirectory = outputDirectory;

  final String claudeExecutable;
  final Duration timeout;
  final String? _watchdogScriptPath;
  final ClaudeDetectionService _claudeDetectionService;
  final String? _outputDirectory;

  /// Resolves the watchdog script's absolute path. Dev/test mode (this
  /// repo's checkout) resolves relative to `scripts/skill_watchdog.sh` from
  /// the package root; a release-mode bundled app resolves it inside the
  /// `.app` bundle's `Contents/Resources/` directory instead — there is no
  /// pre-existing bundled-script precedent in this codebase to follow, so
  /// this mirrors Flutter's own documented pattern for bundling extra
  /// files next to `Platform.resolvedExecutable` (`Contents/MacOS/pro_orc`
  /// -> sibling `../Resources/`).
  String _resolveWatchdogScriptPath() {
    if (_watchdogScriptPath != null) return _watchdogScriptPath;

    final exeDir = p.dirname(Platform.resolvedExecutable);
    final bundledPath = p.normalize(
      p.join(exeDir, '..', 'Resources', 'skill_watchdog.sh'),
    );
    if (File(bundledPath).existsSync()) return bundledPath;

    // Dev-mode fallback: repo checkout run via `flutter run`, where
    // resolvedExecutable points somewhere under `build/`, not a real
    // bundle with a Resources/ dir containing this script yet.
    return p.join(Directory.current.path, 'scripts', 'skill_watchdog.sh');
  }

  Future<String> _resolveOutputDirectory() async {
    if (_outputDirectory != null) return _outputDirectory;
    final dir = await getApplicationSupportDirectory();
    final runsDir = Directory(p.join(dir.path, 'skill_runs'));
    if (!await runsDir.exists()) {
      await runsDir.create(recursive: true);
    }
    return runsDir.path;
  }

  /// Spawns the watchdog+`claude -p` pair fully detached. Checks
  /// [ClaudeDetectionService.isClaudeInstalled] first — if `false`, throws
  /// [ClaudeNotAvailableException] before any process is spawned.
  ///
  /// [skillPrompt] is passed to `claude -p` as a single discrete argument
  /// (`['-p', skillPrompt]`), never interpolated into a shell string.
  Future<SpawnResult> start({
    required String projectPath,
    required String skillId,
    required String skillPrompt,
  }) async {
    final installed = await _claudeDetectionService.isClaudeInstalled();
    if (!installed) {
      throw const ClaudeNotAvailableException();
    }

    final outputDir = await _resolveOutputDirectory();
    final safeSkillId = _sanitizeForFilename(skillId);
    final safeProjectSlug = _sanitizeForFilename(p.basename(projectPath));
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final runToken = '$safeProjectSlug-$safeSkillId-$timestamp';
    final outputFilePath = p.join(outputDir, '$runToken.log');
    final pidFilePath = p.join(outputDir, '$runToken.pid');

    final watchdogScript = _resolveWatchdogScriptPath();
    if (!File(watchdogScript).existsSync()) {
      // Loud, specific failure rather than a silent no-op: BLOCKER-3
      // (2026-08-24 review) found this script simply missing from every
      // release build for a while — if that ever regresses again (a
      // future bundling change, a broken CI artifact, ...), this must
      // fail immediately and visibly instead of Process.start silently
      // erroring in a way that looks identical to a hung watchdog. The
      // caller (SkillRunNotifier.start, after BLOCKER-2's fix) already
      // catches any spawn-path exception, releases the concurrency slot,
      // and surfaces StartSkillOutcome.spawnFailed to the UI.
      developer.log(
        'skill_watchdog.sh not found at resolved path: $watchdogScript — '
        'the headless skill run cannot be started.',
        name: 'headless_skill_runner',
      );
      throw StateError(
        'skill_watchdog.sh not found at $watchdogScript — check that it is '
        'bundled into Contents/Resources for a release build, or present '
        'at scripts/skill_watchdog.sh in a dev checkout.',
      );
    }
    final watchdogArgs = [
      timeout.inSeconds.toString(),
      outputFilePath,
      pidFilePath,
      claudeExecutable,
      '-p',
      skillPrompt,
    ];

    await Process.start(
      watchdogScript,
      watchdogArgs,
      workingDirectory: projectPath,
      mode: ProcessStartMode.detached,
    );

    final claudePid = await _resolveClaudeChildPid(pidFilePath);
    final processStartTime = await readProcessStartTime(claudePid);

    return SpawnResult(
      pid: claudePid,
      processStartTime: processStartTime ?? DateTime.now(),
      outputFilePath: outputFilePath,
    );
  }

  /// Reads the `claude -p` child's real PID from [pidFilePath], written by
  /// the watchdog script immediately after backgrounding it (see
  /// `scripts/skill_watchdog.sh`). Polls for the file's appearance at a
  /// short, fixed interval — deterministic and fast (typically sub-10ms on
  /// a local disk) rather than the unreliable `pgrep -P <watchdogPid>`
  /// polling this replaced, which could itself outlast a short
  /// (test-injected) watchdog timeout before ever resolving a PID.
  Future<int> _resolveClaudeChildPid(String pidFilePath) async {
    final pidFile = File(pidFilePath);
    for (var attempt = 0; attempt < 200; attempt++) {
      if (await pidFile.exists()) {
        final content = (await pidFile.readAsString()).trim();
        final parsedPid = int.tryParse(content);
        if (parsedPid != null) return parsedPid;
      }
      await Future.delayed(const Duration(milliseconds: 5));
    }
    throw StateError(
      'Watchdog did not write a PID file at $pidFilePath within the poll '
      'window — the watchdog script may have failed to start.',
    );
  }

  static String _sanitizeForFilename(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }
}

/// Reads the OS-reported start time of [pid] via `ps -o lstart=`, run with
/// `LC_ALL=C` so the output is a fixed, locale-independent format
/// (`"<Weekday> <Month> <Day> <HH:MM:SS> <Year>"`, e.g. `"Mon Aug 24
/// 08:21:11 2026"`) regardless of the host's locale settings — the app's
/// own locale (`de_DE.UTF-8` on this machine) would otherwise produce
/// abbreviations `DateTime` cannot parse. Returns null if the PID does not
/// exist or the output could not be parsed (e.g. the process already
/// exited between spawn and this read).
Future<DateTime?> readProcessStartTime(int pid) async {
  try {
    final result = await Process.run(
      'ps',
      ['-o', 'lstart=', '-p', pid.toString()],
      environment: {'LC_ALL': 'C'},
    );
    if (result.exitCode != 0) return null;
    final raw = (result.stdout as String).trim();
    if (raw.isEmpty) return null;
    return _parseLstart(raw);
  } catch (e) {
    developer.log(
      'Failed to read process start time for pid $pid: $e',
      name: 'headless_skill_runner',
    );
    return null;
  }
}

const _monthAbbreviations = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

/// Parses `ps -o lstart=`'s fixed `LC_ALL=C` output format: weekday, month,
/// day, HH:MM:SS, year (e.g. `"Mon Aug 24 08:21:11 2026"`). Returns null if
/// the string does not match the expected shape.
DateTime? _parseLstart(String raw) {
  final parts = raw.split(RegExp(r'\s+'));
  if (parts.length != 5) return null;
  final month = _monthAbbreviations[parts[1]];
  final day = int.tryParse(parts[2]);
  final timeParts = parts[3].split(':');
  final year = int.tryParse(parts[4]);
  if (month == null || day == null || year == null || timeParts.length != 3) {
    return null;
  }
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  final second = int.tryParse(timeParts[2]);
  if (hour == null || minute == null || second == null) return null;
  return DateTime(year, month, day, hour, minute, second);
}
