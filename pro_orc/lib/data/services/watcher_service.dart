import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart' show WatchEvent, ChangeType;

import 'package:pro_orc/data/services/watcher_telemetry.dart';

/// Directory names whose contents never change what the dashboard displays,
/// but which produce extremely high event volume (package installs, build
/// output, Python venvs). Events under these are dropped before debouncing.
/// Applies to project scan-dir paths (see [isNoiseEvent]) — NOT to
/// `~/.claude/` paths, which use allowlist semantics instead (see
/// [_isAllowedClaudeHomePath]).
const Set<String> _noiseDirNames = {
  'node_modules',
  '.dart_tool',
  '.next',
  '.turbo',
  '.cache',
  '.venv',
  '__pycache__',
  'build',
};

/// Path segments (relative to `~/.claude/`) whose contents are shown by the
/// dashboard's Claude Tools tab or memory indicator, and must therefore
/// still trigger a rescan.
///
/// Only paths under one of these are allowed through for `~/.claude/`
/// events — see [_isAllowedClaudeHomePath]. Everything else under
/// `~/.claude/` is dropped (allowlist, not blacklist): background noise
/// there is high-volume and unbounded (new subdirectories keep appearing,
/// e.g. `plugins/cache/<hash>/...`), so enumerating "what to drop" chases
/// an ever-growing list — root cause 3 of the 2026-08-20 process storm.
/// `~/.claude/projects/**/memory/` is included so the memory indicator
/// (rem-sleep consolidation) keeps working.
const List<String> _allowedClaudeHomeSegmentPrefixes = [
  'skills',
  'agents',
  'plugins/installed_plugins.json',
  'plugins/known_marketplaces.json',
  'settings.json',
  'settings.local.json',
];

/// Returns true if [pathAfterClaudeHome] (the path segments after `.claude`)
/// is something the dashboard actually displays and must rescan for.
bool _isAllowedClaudeHomePath(List<String> pathAfterClaudeHome) {
  if (pathAfterClaudeHome.isEmpty) return false;
  final rest = pathAfterClaudeHome.join('/');

  // Memory indicator: ~/.claude/projects/<encoded>/memory/**
  if (pathAfterClaudeHome.first == 'projects' &&
      pathAfterClaudeHome.contains('memory')) {
    return true;
  }

  for (final prefix in _allowedClaudeHomeSegmentPrefixes) {
    if (rest == prefix || rest.startsWith('$prefix/')) return true;
  }

  return false;
}

/// Returns true for filesystem events that must not trigger a rescan.
///
/// Three different policies apply depending on where [path] lives:
///
/// - Under the configured Obsidian vault root ([vaultRoot], when it is
///   non-null and overlaps a scan dir): **always noise** — no partial
///   allowlist, unlike `~/.claude/`. Vault content is never displayed by
///   this dashboard (unlike `~/.claude/`, which the Claude Tools tab and
///   memory indicator partially read), so there is no legitimate reason for
///   a change under the vault root to trigger a project rescan. This closes
///   the vault-write → watcher → rescan → vault-write self-trigger loop
///   (010-vault-status-writer FR-022a) — without it, `VaultStatusWriter`
///   writing a hub file inside a scan dir would itself fire a new watcher
///   event, which would trigger another sync cycle, which would write
///   again, indefinitely, mirroring the exact "missing_wiring" root-cause
///   class the 2026-08-20 process-storm postmortem flagged.
/// - Under `~/.claude/`: **allowlist**. Only paths the dashboard actually
///   reads (skills/, agents/, plugins/installed_plugins.json,
///   plugins/known_marketplaces.json, settings.json,
///   projects/**/memory/**) pass through; everything else is noise —
///   including `plugins/cache/`, `tool-results/`, `subagents/`,
///   `file-history/`, `shell-snapshots/`, `todos/`, and any `.jsonl`
///   session transcript. A blacklist here chases an unbounded, ever-growing
///   set of high-churn directories (root cause 3 of the 2026-08-20 process
///   storm — 483 changes under `plugins/cache/` alone were observed in 2h).
/// - Everywhere else (project scan dirs): **blacklist**, as before —
///   `node_modules`, `.dart_tool`, build output, etc. are dropped, but
///   ordinary project files, `.planning/`, `.a1/`, and `.git/HEAD`/`refs`
///   (commit signal) always pass through.
///
/// [vaultRoot] is optional (defaults to `null`, meaning "no vault exclusion
/// configured/known") so every existing call site and test keeps working
/// unchanged; only [WatcherService] (via [WatcherService.multi]'s
/// `vaultRootOverride`) passes a resolved value.
bool isNoiseEvent(String path, {String? vaultRoot}) {
  if (vaultRoot != null && vaultRoot.isNotEmpty) {
    final normalizedRoot = vaultRoot.endsWith('/') ? vaultRoot : '$vaultRoot/';
    if (path == vaultRoot || path.startsWith(normalizedRoot)) {
      return true;
    }
  }

  final segments = path.split('/');

  final claudeIndex = segments.indexOf('.claude');
  if (claudeIndex != -1) {
    final rest = segments.sublist(claudeIndex + 1);
    return !_isAllowedClaudeHomePath(rest);
  }

  final gitIndex = segments.indexOf('.git');
  if (gitIndex != -1) {
    final rest = segments.sublist(gitIndex + 1);
    final isCommitSignal =
        rest.isNotEmpty && (rest.last == 'HEAD' || rest.contains('refs'));
    return !isCommitSignal;
  }

  if (segments.any(_noiseDirNames.contains)) return true;
  if (path.endsWith('.jsonl')) return true;

  return false;
}

/// Removes a single trailing `/` for stable comparison against native event
/// paths, which never carry one.
String _stripTrailingSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

/// Maps a native [FileSystemEvent] to the [ChangeType] the rest of the app
/// (and the existing test suite) expects from the `watcher` package's
/// [WatchEvent]. Consumers of [WatcherService.events] never branch on
/// [ChangeType] today (verified across projects_provider.dart,
/// claude_tools_watcher_provider.dart, automation_provider.dart,
/// session_provider.dart, learning_provider.dart, harness_provider.dart — all
/// treat any event as "something changed, rescan"), but the type is kept
/// accurate to preserve the public contract and the existing
/// ADD/MODIFY-asserting tests.
ChangeType _changeTypeOf(FileSystemEvent event) {
  if (event is FileSystemCreateEvent) return ChangeType.ADD;
  if (event is FileSystemDeleteEvent) return ChangeType.REMOVE;
  if (event is FileSystemMoveEvent) return ChangeType.REMOVE;
  return ChangeType.MODIFY;
}

/// A plain Dart service class that watches directories for changes, applies
/// noise filtering (see [isNoiseEvent]), a 2s trailing-edge debounce, and
/// defensive error handling.
///
/// Root cause of the 2026-08-20/24 process-storm round 3: the previous
/// implementation handed each watched root to the `watcher` package's
/// `DirectoryWatcher`, which on macOS resolves to `RecursiveDirectoryWatcher`
/// — this synchronously `listSync()`-walks the ENTIRE subtree on
/// construction and permanently retains one entry per file/directory in a
/// `DirectoryTree`, with no exclusion hook. `isNoiseEvent` only filtered
/// events AFTER that walk had already paid for and retained them. Measured
/// on the real watch roots: ~10.7s blocking main-isolate walk and ~450MB
/// permanently retained, 71% of it `node_modules`.
///
/// This implementation instead subscribes directly to the platform's native
/// recursive filesystem-change notifications via `Directory.watch(recursive:
/// true)` (the same underlying macOS FSEvents API the `watcher` package
/// itself uses) and applies [isNoiseEvent] filtering to each raw event AS IT
/// ARRIVES, before anything is buffered, counted, or retained. There is no
/// upfront directory listing and no in-memory tree — noise directories are
/// never tracked, not filtered post-hoc. Measured: ~8ms construction and no
/// growth in resident memory over idle time on the same real roots (see
/// `2026-08-24-process-storm-round3.md` Fix Plan for before/after numbers).
///
/// Supports watching multiple directories simultaneously. Each directory
/// gets its own native watch subscription and events are merged into a
/// single stream.
class WatcherService {
  final List<String> _dirs;
  final String? _vaultRoot;
  final List<StreamSubscription<FileSystemEvent>> _nativeSubs = [];
  late final StreamController<WatchEvent> _controller;
  final _readyCompleter = Completer<void>();

  /// Diagnostics for this instance (WP3, process-storm round 3). Populated
  /// during [_init] and updated as events are observed.
  final WatcherTelemetry telemetry = WatcherTelemetry();

  WatcherService(String singleDir, {String? vaultRoot})
    : _dirs = [singleDir],
      _vaultRoot = vaultRoot {
    _init();
  }

  /// [vaultRoot]: resolved absolute path to the configured Obsidian vault
  /// root, or `null`/empty when no vault is configured. When it overlaps one
  /// of [dirs], events under it are dropped as noise (see [isNoiseEvent]) so
  /// a vault write never triggers a rescan of the scan dir that contains it.
  WatcherService.multi(this._dirs, {String? vaultRoot})
    : _vaultRoot = vaultRoot {
    _init();
  }

  void _init() {
    _controller = StreamController<WatchEvent>.broadcast();

    final sw = Stopwatch()..start();

    for (final dir in _dirs) {
      final normalizedRootPath = _stripTrailingSlash(dir);
      try {
        final stream = Directory(dir).watch(recursive: true);
        final sub = stream.listen(
          (event) {
            telemetry.rawEventCount++;
            if (_controller.isClosed) return;
            // A native event whose path IS the watched root itself carries
            // no actionable information (which file changed?) and is a
            // known macOS FSEvents artifact: when the watch is established
            // right after the subtree was created/populated, the OS can
            // coalesce that recent history into a single "root changed"
            // notification rather than reporting the actual child paths.
            // Reproduced deterministically by the vault self-trigger-guard
            // test's setUp (synchronously creates the whole vault subtree,
            // then constructs the watcher) — without this guard the
            // coalesced root event bypasses the vault-root path check below
            // (it doesn't start with the vault path) and would incorrectly
            // surface as a real change, defeating FR-022a.
            if (_stripTrailingSlash(event.path) == normalizedRootPath) return;
            if (isNoiseEvent(event.path, vaultRoot: _vaultRoot)) return;
            telemetry.emittedEventCount++;
            _controller.add(WatchEvent(_changeTypeOf(event), event.path));
          },
          onError: (Object error, StackTrace stackTrace) {
            developer.log(
              'Suppressed watcher error: $error',
              name: 'watcher_service',
            );
          },
          onDone: () {
            // Individual watcher done — don't close controller
            // (other watchers may still be active)
          },
          cancelOnError: false,
        );
        _nativeSubs.add(sub);
      } catch (e) {
        // Root does not exist / not watchable — log and skip, matching the
        // defensive "never crash on a bad root" posture of the rest of the
        // service.
        developer.log(
          'Failed to watch $dir: $e',
          name: 'watcher_service',
        );
      }
    }

    // Native watch subscriptions above are synchronous — no listSync() walk,
    // no upfront directory read — so readiness is immediate. Kept as a
    // Future/Completer to preserve the existing `ready`/`isReady` API that
    // callers and tests already use.
    telemetry.constructionTime = sw.elapsed;
    telemetry.watchedRootCount = _nativeSubs.length;
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  /// Returns a debounced stream of [WatchEvent]s from all watched directories.
  Stream<WatchEvent> get events {
    return _controller.stream.debounce(const Duration(seconds: 2));
  }

  /// Returns true once all underlying watchers are ready. Construction is
  /// synchronous (see [_init]), so this is true immediately after the
  /// constructor returns.
  bool get isReady => _readyCompleter.isCompleted;

  /// Returns a [Future] that completes when all watchers are ready.
  Future<void> get ready => _readyCompleter.future;

  /// Disposes all watchers.
  Future<void> dispose() async {
    for (final sub in _nativeSubs) {
      await sub.cancel();
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
