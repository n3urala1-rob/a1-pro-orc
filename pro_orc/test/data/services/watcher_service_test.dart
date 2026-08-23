/// Integration tests for [WatcherService] using real temp directories.
///
/// These tests verify:
/// - File create/modify events are emitted
/// - 2s trailing-edge debounce collapses rapid file writes (LIVE-01 requirement)
/// - Directory events from macOS FSEvents do not crash the service (watcher#79)
///
/// Tests use real temp directories (no mocking) — same pattern as Phase 7
/// git_reader tests. File watcher tests are inherently timing-sensitive;
/// generous timeouts are used to absorb OS-level delays.
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
    tempDir = Directory.systemTemp.createTempSync('watcher_test_');
    service = WatcherService(tempDir.path);
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

  // ---------------------------------------------------------------------------
  // Test 1: emits event when file is created
  // ---------------------------------------------------------------------------

  test('emits event when file is created in watched directory', () async {
    final events = <WatchEvent>[];
    final completer = Completer<void>();

    // Subscribe before awaiting ready — stream must be consumed to drive
    // the watcher's internal event loop
    final sub = service.events.listen((event) {
      events.add(event);
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    subscriptions.add(sub);

    // Wait for watcher to be ready before writing files
    await service.ready;

    // Write a new file into the temp dir
    final newFile = File('${tempDir.path}/test_create.txt');
    await newFile.writeAsString('hello watcher');

    // Expect a WatchEvent to arrive within 6 seconds (accounts for the
    // 2s trailing-edge debounce plus FSEvents latency)
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException(
        'Expected WatchEvent for file create, but none arrived within 6s',
        const Duration(seconds: 6),
      ),
    );

    expect(events, isNotEmpty);
    // macOS may report ADD or MODIFY depending on FSEvents timing
    final types = events.map((e) => e.type).toSet();
    expect(
      types.intersection({ChangeType.ADD, ChangeType.MODIFY}),
      isNotEmpty,
      reason: 'Expected ADD or MODIFY event for file creation, got $types',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 2: emits event when file is modified
  // ---------------------------------------------------------------------------

  test('emits event when file is modified', () async {
    // Create an existing file before subscribing
    final existingFile = File('${tempDir.path}/existing.txt');
    await existingFile.writeAsString('original content');

    final events = <WatchEvent>[];
    final completer = Completer<void>();

    // Subscribe before awaiting ready — required for watcher event loop
    final sub = service.events.listen((event) {
      // Filter to only events for our specific file
      if (event.path.endsWith('existing.txt')) {
        events.add(event);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    subscriptions.add(sub);

    // Wait for initial scan to complete, then let initial events settle
    await service.ready;
    await Future.delayed(const Duration(milliseconds: 500));

    // Modify the existing file content
    await existingFile.writeAsString('modified content');

    // Expect a WatchEvent with MODIFY within 6 seconds (2s debounce + slack)
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => throw TimeoutException(
        'Expected MODIFY WatchEvent, but none arrived within 6s',
        const Duration(seconds: 6),
      ),
    );

    expect(events, isNotEmpty);
    expect(
      events.map((e) => e.type),
      anyElement(equals(ChangeType.MODIFY)),
      reason: 'Expected a MODIFY event for existing.txt',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 3: debounces rapid changes into fewer events
  // ---------------------------------------------------------------------------

  test('debounces rapid changes into single event (LIVE-01)', () async {
    final events = <WatchEvent>[];

    // Subscribe before awaiting ready
    final sub = service.events.listen((event) {
      events.add(event);
    });
    subscriptions.add(sub);

    await service.ready;

    // Write 5 files rapidly (within ~50ms total) to trigger debounce
    for (int i = 0; i < 5; i++) {
      final file = File('${tempDir.path}/rapid_$i.txt');
      await file.writeAsString('content $i');
      // Minimal gap between writes — intentionally fast to trigger debounce
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // Collect events over a 5 second window after the rapid writes
    // (debounce window is 2s, so all rapid events should be batched)
    await Future.delayed(const Duration(seconds: 5));

    // Assert that fewer events arrived than files written.
    // The 2s trailing-edge debounce should batch the rapid writes.
    expect(
      events.length,
      lessThan(5),
      reason:
          'Expected debounce to collapse 5 rapid writes into fewer events, '
          'but got ${events.length} events. 2s debounce should batch rapid writes.',
    );

    // At least one event should have arrived (confirming the batch fired)
    expect(
      events,
      isNotEmpty,
      reason: 'Expected at least one debounced event after 5 rapid writes',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 4: no crash on directory events (watcher#79 defense)
  // ---------------------------------------------------------------------------

  test('does not crash on directory events (watcher#79 defense)', () async {
    // Track errors — there should be none
    final errors = <Object>[];

    // Subscribe before awaiting ready
    final sub = service.events.listen(
      (_) {}, // ignore events
      onError: (Object error) {
        errors.add(error);
      },
    );
    subscriptions.add(sub);

    await service.ready;

    // Create a subdirectory — this triggers directory-level events on macOS
    // which historically caused assertion crashes (watcher#79)
    final subDir = Directory('${tempDir.path}/sub_directory');
    await subDir.create();

    // Also create a file in the subdirectory to trigger recursive events
    final fileInSubDir = File('${tempDir.path}/sub_directory/nested.txt');
    await fileInSubDir.writeAsString('nested content');

    // Wait 1 second — if no crash, the defensive error handling works
    await Future.delayed(const Duration(seconds: 1));

    // No errors should have reached the stream listener
    expect(
      errors,
      isEmpty,
      reason:
          'Expected no errors from directory events (watcher#79 defense), '
          'but got: $errors',
    );
  });

  // ---------------------------------------------------------------------------
  // Test 5: vault self-trigger loop proof (010-vault-status-writer FR-022a)
  // ---------------------------------------------------------------------------
  //
  // This is the end-to-end proof that the vault-write -> watcher -> rescan
  // -> vault-write loop cannot happen: a real WatcherService (not just the
  // pure isNoiseEvent function) watches a scan dir that CONTAINS the vault
  // root as a subdirectory — the exact "vault root overlaps a scan dir"
  // configuration FR-022a describes. A file write simulating
  // VaultStatusWriter's own hub write lands inside that vault subdirectory.
  // If the guard were missing/broken, this write would surface as a
  // WatchEvent (the same event projects_provider.dart's ref.listen uses to
  // call coalescer.requestRescan -> ref.invalidateSelf -> a second scan ->
  // a second vault write, unboundedly). Asserting zero events proves no
  // rescan is triggered, which transitively proves no second write follows
  // (this service never even surfaces the first write as an event for a
  // rescan to react to).
  group('vault self-trigger loop guard (FR-022a)', () {
    late Directory scanDir;
    late Directory vaultSubDir;
    late WatcherService vaultAwareService;
    late List<StreamSubscription> vaultAwareSubs;

    setUp(() {
      scanDir = Directory.systemTemp.createTempSync('watcher_vault_scan_');
      vaultSubDir = Directory('${scanDir.path}/N3URAL-Vault')
        ..createSync(recursive: true);
      Directory('${vaultSubDir.path}/project').createSync(recursive: true);
      vaultAwareSubs = [];
    });

    tearDown(() async {
      for (final sub in vaultAwareSubs) {
        await sub.cancel();
      }
      await vaultAwareService.dispose();
      if (scanDir.existsSync()) {
        scanDir.deleteSync(recursive: true);
      }
    });

    test(
      'a hub write inside the vault root never surfaces as a WatchEvent, '
      'even though the vault root is nested inside a watched scan dir',
      () async {
        vaultAwareService = WatcherService.multi([
          scanDir.path,
        ], vaultRoot: vaultSubDir.path);

        final events = <WatchEvent>[];
        final sub = vaultAwareService.events.listen(events.add);
        vaultAwareSubs.add(sub);

        await vaultAwareService.ready;

        // Simulate VaultStatusWriter writing a hub file inside the vault
        // root — the exact operation that, without the guard, would
        // trigger projects_provider's watcher-driven rescan.
        final hub = File('${vaultSubDir.path}/project/pro-orc.md');
        await hub.writeAsString('---\ntype: project\n---\n');

        // Give the (guarded) event pipeline the same window the other tests
        // use to prove absence, not just late arrival.
        await Future.delayed(const Duration(seconds: 4));

        expect(
          events,
          isEmpty,
          reason:
              'A write inside the vault root must never surface as a '
              'WatchEvent — otherwise projects_provider would coalesce a '
              'rescan from it, closing the loop this guard exists to break. '
              'Got: ${events.map((e) => e.path).toList()}',
        );
      },
    );

    test(
      'a write OUTSIDE the vault root (but inside the same scan dir) still '
      'surfaces normally — the guard only excludes the vault subtree',
      () async {
        vaultAwareService = WatcherService.multi([
          scanDir.path,
        ], vaultRoot: vaultSubDir.path);

        final events = <WatchEvent>[];
        final completer = Completer<void>();
        final sub = vaultAwareService.events.listen((event) {
          events.add(event);
          if (!completer.isCompleted) completer.complete();
        });
        vaultAwareSubs.add(sub);

        await vaultAwareService.ready;

        final ordinaryFile = File('${scanDir.path}/some_project/README.md');
        await ordinaryFile.parent.create(recursive: true);
        await ordinaryFile.writeAsString('# hello');

        await completer.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () => throw TimeoutException(
            'Expected a WatchEvent for a write outside the vault root, but '
            'none arrived — the vault guard must not over-exclude the rest '
            'of the scan dir.',
            const Duration(seconds: 6),
          ),
        );

        expect(events, isNotEmpty);
      },
    );
  });
}
