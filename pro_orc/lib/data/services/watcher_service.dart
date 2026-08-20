import 'dart:async';
import 'dart:developer' as developer;

import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

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
/// Two different policies apply depending on where [path] lives:
///
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
bool isNoiseEvent(String path) {
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

/// A plain Dart service class that wraps [DirectoryWatcher] with noise
/// filtering (see [isNoiseEvent]), a 2s trailing-edge debounce, and defensive
/// error handling.
///
/// Supports watching multiple directories simultaneously. Each directory
/// gets its own [DirectoryWatcher] and events are merged into a single stream.
class WatcherService {
  final List<String> _dirs;
  final List<DirectoryWatcher> _watchers = [];
  late final StreamController<WatchEvent> _controller;
  final List<StreamSubscription<WatchEvent>> _subs = [];

  WatcherService(String singleDir) : _dirs = [singleDir] {
    _init();
  }

  WatcherService.multi(this._dirs) {
    _init();
  }

  void _init() {
    _controller = StreamController<WatchEvent>.broadcast();

    for (final dir in _dirs) {
      final watcher = DirectoryWatcher(dir);
      _watchers.add(watcher);

      final sub = watcher.events.listen(
        (event) {
          if (!_controller.isClosed && !isNoiseEvent(event.path)) {
            _controller.add(event);
          }
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
      _subs.add(sub);
    }
  }

  /// Returns a debounced stream of [WatchEvent]s from all watched directories.
  Stream<WatchEvent> get events {
    return _controller.stream.debounce(const Duration(seconds: 2));
  }

  /// Returns true once all underlying watchers are ready.
  bool get isReady => _watchers.every((w) => w.isReady);

  /// Returns a [Future] that completes when all watchers are ready.
  Future<void> get ready => Future.wait(_watchers.map((w) => w.ready));

  /// Disposes all watchers.
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
