import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/services/process_runner.dart';
import 'package:pro_orc/data/services/project_scanner.dart';

/// Creates a real git repo project directory (`.git/` present, one commit) —
/// mirrors the fixture shape in `project_scanner_test.dart`.
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
  group('ProjectScanner.scanAll process concurrency', () {
    late Directory tempDir;
    late AppDatabase db;
    late ProjectScanner scanner;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('scan_concurrency_test_');
      db = AppDatabase(NativeDatabase.memory());
      scanner = ProjectScanner(db);

      // Regression-report evidence: 45 git repos → up to 90 concurrent git
      // spawns (2 sequential calls per repo run unbounded via Future.wait).
      // 20 repos is enough to prove the semaphore caps concurrency without
      // making the test suite slow.
      for (var i = 0; i < 20; i++) {
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
      'never exceeds the global process semaphore limit during a full scan',
      () async {
        // ProcessSemaphore.peakRunning (process-storm round 3, WP3) tracks
        // the true high-water mark internally, at the exact moment `running`
        // increments — race-free, unlike polling `.running` on a timer,
        // which can miss a peak that occurs between poll ticks.
        final peakBefore = globalProcessSemaphore.peakRunning;

        await scanner.scanAll(scanDirOverride: tempDir.path);

        final peakDuringScan = globalProcessSemaphore.peakRunning;

        expect(
          peakDuringScan,
          lessThanOrEqualTo(globalProcessSemaphore.maxConcurrent),
          reason:
              'Peak observed concurrency was $peakDuringScan, but the global '
              'semaphore caps at ${globalProcessSemaphore.maxConcurrent}. A '
              'scan over 20 git repos must never spawn more concurrent '
              'processes than the semaphore allows.',
        );
        expect(
          peakDuringScan,
          greaterThanOrEqualTo(peakBefore),
          reason: 'peakRunning must never decrease — it is a running maximum.',
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
