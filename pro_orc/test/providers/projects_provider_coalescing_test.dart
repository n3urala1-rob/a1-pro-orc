import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:watcher/watcher.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/projects_provider.dart';
import 'package:pro_orc/providers/watcher_provider.dart';

Future<Directory> _createGitProject(Directory parent, String name) async {
  final dir = Directory(p.join(parent.path, name));
  await dir.create();
  await Process.run(
    'git',
    ['init'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  await Process.run(
    'git',
    ['config', 'user.email', 'test@test.com'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  await Process.run(
    'git',
    ['config', 'user.name', 'Test'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  await File(p.join(dir.path, 'README.md')).writeAsString('# $name');
  await Process.run(
    'git',
    ['add', '.'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  await Process.run(
    'git',
    ['commit', '-m', 'Initial commit'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  return dir;
}

void main() {
  group(
    'projectsProvider re-entrancy guard (2026-08-20 process-storm-burst wave 2)',
    () {
      late Directory tempDir;
      late AppDatabase db;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp(
          'coalescing_provider_test_',
        );
        db = AppDatabase(NativeDatabase.memory());
        await db.setScanDirs([tempDir.path]);

        // A handful of real git repos so scanAll() takes long enough (real
        // subprocess spawns) for concurrent watcher events fired during the
        // scan to be a meaningful test, without being slow.
        for (var i = 0; i < 6; i++) {
          await _createGitProject(tempDir, 'repo_$i');
        }
      });

      tearDown(() async {
        await db.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test(
        'watcher events that fire while a scan is in flight do not start '
        'a second concurrent scan — they coalesce into one follow-up',
        () async {
          final watcherController = StreamController<WatchEvent>.broadcast();
          addTearDown(watcherController.close);

          final container = ProviderContainer(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              watcherProvider.overrideWith((ref) => watcherController.stream),
            ],
          );
          addTearDown(container.dispose);

          // Wrap the real scanner call via a listener on projectsProvider's
          // own scanCoalescer state transitions instead of mocking
          // ProjectScanner (which is a concrete class, not an interface) —
          // markScanStarted/markScanFinished bracket every real scanAll()
          // call, so counting those transitions IS counting concurrent
          // scans.
          final coalescer = container.read(scanCoalescerProvider);

          // Keep the provider alive across the awaits below, the same way a
          // mounted widget's `ref.watch` would (FutureProvider without
          // keepAlive can otherwise be disposed between reads).
          final sub = container.listen(projectsProvider, (previous, next) {});
          addTearDown(sub.close);

          // Kick off the first scan.
          final firstScanFuture = container.read(projectsProvider.future);

          // Fire multiple watcher events while the first scan is still in
          // flight (it hasn't awaited yet — the repos are real, so
          // scanAll() takes a few dozen ms minimum for 6 repos x 2 git
          // calls each).
          expect(coalescer.isScanning, isTrue);
          for (var i = 0; i < 5; i++) {
            watcherController.add(WatchEvent(ChangeType.MODIFY, tempDir.path));
          }
          // Let the coalescer observe the events synchronously via
          // ref.listen's callback (StreamController broadcasts
          // synchronously to listeners already subscribed).
          await Future<void>.delayed(Duration.zero);

          expect(
            coalescer.hasPendingRescan,
            isTrue,
            reason:
                'events fired during the in-flight scan must be recorded as '
                'exactly one pending rescan, not trigger scanAll again '
                'immediately',
          );

          await firstScanFuture;
          // The pending rescan is invalidated via a microtask after the
          // first scan's build completes — let that settle, then let the
          // resulting second scan finish too.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await container.read(projectsProvider.future);

          expect(
            coalescer.isScanning,
            isFalse,
            reason: 'no scan should still be in flight once everything settles',
          );
          expect(
            coalescer.hasPendingRescan,
            isFalse,
            reason: 'the single coalesced follow-up should have been consumed',
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    },
  );
}
