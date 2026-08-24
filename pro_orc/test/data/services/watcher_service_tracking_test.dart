/// Regression tests for process-storm round 3: proves noise directories are
/// never TRACKED by [WatcherService], not merely filtered out of the emitted
/// event stream after the fact.
///
/// The round-2 fix (`isNoiseEvent`) filtered events, but the underlying
/// `watcher` package's `RecursiveDirectoryWatcher` had already `listSync()`-
/// walked and permanently retained an in-memory entry for every file under
/// `node_modules`/`build`/etc. before that filter ever ran — 71% of the
/// tracked filesystem in the real `~/code` root, ~450MB resident, ~10.7s
/// blocking walk (see `2026-08-24-process-storm-round3.md`). This suite
/// asserts at the TRACKING level (via [WatcherService.telemetry]) that noise
/// paths never even reach the raw-event counter meaningfully, AND (the
/// stronger claim for this rewrite) that construction itself performs no
/// upfront walk at all — there is no tree to populate, so noise-dir volume
/// cannot inflate memory or startup time regardless of how many noise files
/// exist on disk.
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:pro_orc/data/services/watcher_service.dart';
import 'package:watcher/watcher.dart';

void main() {
  late Directory tempDir;
  late WatcherService service;
  late List<StreamSubscription> subscriptions;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('watcher_tracking_test_');
    subscriptions = [];
  });

  tearDown(() async {
    for (final sub in subscriptions) {
      await sub.cancel();
    }
    await service.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'construction performs no upfront listing — telemetry shows zero raw '
    'events and near-instant construction even for a root that ALREADY '
    'contains a populated node_modules tree at watch time',
    () async {
      // Populate node_modules BEFORE the watcher is constructed — this is
      // exactly the scenario that cost the pre-round-3 implementation its
      // 10.7s blocking listSync() walk and ~450MB retained tree: existing
      // high-fanout content under a watched root.
      final nodeModules = Directory('${tempDir.path}/node_modules');
      await nodeModules.create(recursive: true);
      for (var i = 0; i < 200; i++) {
        await File('${nodeModules.path}/pkg_$i.js').writeAsString('x');
      }

      service = WatcherService(tempDir.path);
      await service.ready;

      // No upfront walk means no raw events were generated just from
      // construction — the 200 pre-existing node_modules files never had to
      // be seen, tracked, or discarded.
      expect(
        service.telemetry.rawEventCount,
        equals(0),
        reason:
            'Construction must not generate any raw events from pre-existing '
            'files — the old listSync()-based tree walk would have produced '
            'internal tracking entries for all 200 files even though none of '
            'them are real filesystem changes.',
      );
      expect(
        service.telemetry.constructionTime,
        lessThan(const Duration(milliseconds: 500)),
        reason:
            'Construction must stay fast regardless of pre-existing noise-dir '
            'volume — the old implementation scaled with total file count '
            '(measured ~10.7s on the real ~/code root with 1.17M entries).',
      );
    },
  );

  test(
    'a change under node_modules/build/.dart_tool is never emitted downstream '
    '(tracking-level noise exclusion, not just post-hoc event filtering)',
    () async {
      service = WatcherService(tempDir.path);
      final events = <WatchEvent>[];
      final sub = service.events.listen(events.add);
      subscriptions.add(sub);

      await service.ready;

      await Directory('${tempDir.path}/node_modules/react').create(
        recursive: true,
      );
      for (var i = 0; i < 30; i++) {
        await File(
          '${tempDir.path}/node_modules/react/file_$i.js',
        ).writeAsString('x');
      }
      await Directory('${tempDir.path}/build/macos').create(recursive: true);
      await File('${tempDir.path}/build/macos/out.bin').writeAsString('x');
      await Directory('${tempDir.path}/.dart_tool').create(recursive: true);
      await File('${tempDir.path}/.dart_tool/version').writeAsString('1');

      // Give the (guarded) pipeline the same settle window other tests use.
      await Future.delayed(const Duration(seconds: 3));

      expect(
        events,
        isEmpty,
        reason:
            'All noise-dir churn must be dropped before reaching the '
            'debounced stream. Got: ${events.map((e) => e.path).toList()}',
      );
      expect(
        service.telemetry.emittedEventCount,
        equals(0),
        reason:
            'The emitted-event counter must stay at zero for pure noise-dir '
            'churn — it only increments for events that pass isNoiseEvent.',
      );
      expect(
        service.telemetry.rawEventCount,
        greaterThan(0),
        reason:
            'Sanity check: the native watch DID receive raw events for this '
            'churn (proving the filter, not a missing subscription, is what '
            'suppressed them).',
      );
    },
  );

  test(
    'legit paths (.planning/STATE.md change, new project dir) still arrive '
    'as events after the rewrite',
    () async {
      service = WatcherService(tempDir.path);
      final events = <WatchEvent>[];
      final completer = Completer<void>();
      final sub = service.events.listen((event) {
        events.add(event);
        if (!completer.isCompleted) completer.complete();
      });
      subscriptions.add(sub);

      await service.ready;

      final planningDir = Directory('${tempDir.path}/some_project/.planning');
      await planningDir.create(recursive: true);
      await File(
        '${planningDir.path}/STATE.md',
      ).writeAsString('# Status\nbuilding');

      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw TimeoutException(
          'Expected a WatchEvent for a .planning/STATE.md change, but none '
          'arrived — legit signal must still be detected after the rewrite.',
          const Duration(seconds: 6),
        ),
      );

      expect(events, isNotEmpty);
      expect(
        events.any((e) => e.path.endsWith('STATE.md')),
        isTrue,
        reason: 'Expected the STATE.md change to surface as an event.',
      );
    },
  );

  test(
    'a newly created top-level project directory under the watched root is '
    'still detected (recursive watch preserves new-dir discovery)',
    () async {
      service = WatcherService(tempDir.path);
      final events = <WatchEvent>[];
      final completer = Completer<void>();
      final sub = service.events.listen((event) {
        events.add(event);
        if (!completer.isCompleted) completer.complete();
      });
      subscriptions.add(sub);

      await service.ready;

      final newProjectDir = Directory('${tempDir.path}/brand_new_project');
      await newProjectDir.create();
      await File(
        '${newProjectDir.path}/CLAUDE.md',
      ).writeAsString('# New project');

      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => throw TimeoutException(
          'Expected a WatchEvent for a new top-level project directory, but '
          'none arrived.',
          const Duration(seconds: 6),
        ),
      );

      expect(events, isNotEmpty);
    },
  );
}
