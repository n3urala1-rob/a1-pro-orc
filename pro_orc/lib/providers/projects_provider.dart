import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/project_organization_seed_service.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/groups_provider.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/watcher_provider.dart';

/// Coalesces watcher-triggered rescans so a watcher event that fires while a
/// scan is already in flight does not start a second, concurrent scan.
///
/// Root cause 2 of the 2026-08-20 process storm: `projectsProvider`
/// self-invalidated on every watcher event with no check for whether the
/// previous scan was still running. A scan over ~45 repos took ~9s under
/// load, but the watcher's debounce is only 2s, so 4-5 scans stacked up —
/// each spawning its own wave of git processes on top of the others.
///
/// [markScanStarted]/[markScanFinished] bracket the actual `scanAll()` call.
/// [requestRescan] is called from the watcher listener; it triggers
/// [onRescan] immediately if no scan is in flight, or — if one is — just
/// records that a rescan was requested and defers it. Multiple requests
/// received while a scan is running collapse into exactly one follow-up
/// scan once the current one finishes (checked in [markScanFinished]).
class ScanCoalescer {
  bool _scanning = false;
  bool _rescanRequested = false;

  /// True while a scan is currently in flight (exposed for tests).
  bool get isScanning => _scanning;

  /// True if a rescan has been requested and is waiting for the current
  /// scan to finish (exposed for tests).
  bool get hasPendingRescan => _rescanRequested;

  void markScanStarted() {
    _scanning = true;
  }

  /// Call after the scan completes. If a rescan was requested while this
  /// scan was running, invokes [onRescan] exactly once.
  void markScanFinished(void Function() onRescan) {
    _scanning = false;
    if (_rescanRequested) {
      _rescanRequested = false;
      onRescan();
    }
  }

  /// Requests a rescan. Runs [onRescan] immediately if idle; otherwise
  /// remembers the request for [markScanFinished] to pick up.
  void requestRescan(void Function() onRescan) {
    if (_scanning) {
      _rescanRequested = true;
    } else {
      onRescan();
    }
  }
}

/// Provided so tests can inject a fresh [ScanCoalescer] instance and observe
/// its state; production code shares one instance for the app's lifetime
/// (the provider itself is not `keepAlive` but `projectsProvider`'s own
/// `ref.watch` in this same provider tree keeps it alive in practice — see
/// `watcherProvider` for the established keepAlive pattern this mirrors).
final scanCoalescerProvider = Provider<ScanCoalescer>((ref) => ScanCoalescer());

/// Live project list — rescans on every watcher event.
/// Watcher events trigger invalidation → rescan → UI rebuild.
///
/// Rescans are coalesced via [scanCoalescerProvider]: a watcher event that
/// arrives while a scan is already running does not start a second one —
/// it schedules exactly one follow-up scan after the in-flight scan
/// completes. The provider stays reactive; the UI still refreshes after
/// every change, just without stacking concurrent scans.
final projectsProvider = FutureProvider<List<ProjectModel>>((ref) async {
  final coalescer = ref.watch(scanCoalescerProvider);

  // Listen to watcher events — any change requests a (possibly deferred)
  // rescan via the coalescer instead of invalidating unconditionally.
  ref.listen(watcherProvider, (previous, next) {
    // Only react to actual data events, not loading/error transitions.
    if (next.hasValue) {
      coalescer.requestRescan(() {
        ref.invalidateSelf();
      });
    }
  });

  coalescer.markScanStarted();
  List<ProjectModel> projects;
  try {
    final scanner = ref.read(projectScannerProvider);
    projects = await scanner.scanAll();

    // One-time, idempotent seed (FR-014/015/016) — runs after every scan but
    // the seed-applied flag makes every call after the first a no-op.
    final db = ref.read(appDatabaseProvider);
    final seeded = await ProjectOrganizationSeedService(
      db,
    ).applyIfNeeded(projects);
    if (seeded) {
      // groupsProvider/membershipProvider may have already loaded their
      // state from the DB before the seed wrote to it — refresh so the
      // seeded groups/assignments show up without requiring an app restart.
      ref.invalidate(groupsProvider);
      ref.invalidate(membershipProvider);
    }
  } finally {
    // markScanFinished only invokes this callback if a rescan was actually
    // requested while this scan was in flight. Deliberately deferred to a
    // microtask: invalidating this provider from inside its own
    // still-running build (synchronously in this `finally`) would race
    // Riverpod's own bookkeeping for "is this provider's build still in
    // progress". Scheduling it for right after the build completes avoids
    // that without changing the coalescing decision.
    coalescer.markScanFinished(() {
      scheduleMicrotask(ref.invalidateSelf);
    });
  }

  return projects;
});
