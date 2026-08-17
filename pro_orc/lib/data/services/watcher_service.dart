import 'dart:async';
import 'dart:developer' as developer;

import 'package:stream_transform/stream_transform.dart';
import 'package:watcher/watcher.dart';

/// Directory names whose contents never change what the dashboard displays,
/// but which produce extremely high event volume (package installs, build
/// output, Python venvs). Events under these are dropped before debouncing.
const Set<String> _noiseDirNames = {
  'node_modules',
  '.dart_tool',
  '.next',
  '.turbo',
  '.cache',
  '.venv',
  '__pycache__',
};

/// Returns true for filesystem events that must not trigger a rescan.
///
/// Background: the watcher also covers `~/.claude/projects`, where every
/// running Claude session appends to its `*.jsonl` transcript on every
/// message. Without this filter the dashboard rescanned all projects (2 git
/// spawns each) continuously while any session was active — the process
/// storm behind the 2026-08-15/16 EAGAIN incidents.
///
/// `.git` internals are noise too (object/pack churn), with one exception:
/// `HEAD` and `refs` paths, which change exactly on commit/branch switch and
/// are what keeps the "last commit" display fresh.
bool isNoiseEvent(String path) {
  final segments = path.split('/');

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
