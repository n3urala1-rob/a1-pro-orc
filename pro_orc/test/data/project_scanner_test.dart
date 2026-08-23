import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_type.dart';
import 'package:pro_orc/data/services/project_scanner.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Creates a temporary directory containing a `.planning/` project structure
/// (PROJECT.md with H1 + description) — still a recognized project marker
/// even though its contents are no longer parsed into a structured model.
Future<Directory> createPlanningProject(
  Directory parent,
  String name, {
  bool withGit = false,
}) async {
  final dir = Directory(p.join(parent.path, name));
  await dir.create();

  final planningDir = Directory(p.join(dir.path, '.planning'));
  await planningDir.create();

  // Write PROJECT.md
  final projectContent =
      '''# $name

## Core Value

Test project description for $name.
''';
  await File(
    p.join(planningDir.path, 'PROJECT.md'),
  ).writeAsString(projectContent);

  if (withGit) {
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
  }

  return dir;
}

/// Creates a plain project directory with a git repo
/// so the scanner's `_isProjectDir` recognises it.
Future<Directory> createPlainProject(Directory parent, String name) async {
  final dir = Directory(p.join(parent.path, name));
  await dir.create();
  await File(p.join(dir.path, 'README.md')).writeAsString('# $name');
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
  await Process.run(
    'git',
    ['add', '.'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  await Process.run(
    'git',
    ['commit', '-m', 'init'],
    workingDirectory: dir.path,
    runInShell: true,
  );
  return dir;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProjectScanner', () {
    late AppDatabase db;
    late Directory scanRoot;
    late ProjectScanner scanner;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      scanRoot = await Directory.systemTemp.createTemp('scanner_test_');
      scanner = ProjectScanner(db);
    });

    tearDown(() async {
      await db.close();
      await scanRoot.delete(recursive: true);
    });

    // -----------------------------------------------------------------------
    // ScanDirectoryNotFoundError
    // -----------------------------------------------------------------------

    group('ScanDirectoryNotFoundError', () {
      test('thrown when scan dir does not exist', () async {
        final nonExistent = p.join(scanRoot.path, 'does_not_exist');
        expect(
          () => scanner.scanAll(scanDirOverride: nonExistent),
          throwsA(isA<ScanDirectoryNotFoundError>()),
        );
      });

      test('error has path and message fields', () async {
        const badPath = '/tmp/definitely_not_a_real_path_xyz987';
        try {
          await scanner.scanAll(scanDirOverride: badPath);
          fail('Expected ScanDirectoryNotFoundError');
        } on ScanDirectoryNotFoundError catch (e) {
          expect(e.path, equals(badPath));
          expect(e.message, isNotEmpty);
        }
      });

      test('thrown for single non-existent override dir', () async {
        // When using scanDirOverride with a non-existent path,
        // the error propagates instead of being silently caught.
        expect(
          () => scanner.scanAll(scanDirOverride: '/tmp/no_such_dir_xyz_999'),
          throwsA(isA<ScanDirectoryNotFoundError>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Directory listing / filtering
    // -----------------------------------------------------------------------

    group('directory listing', () {
      test('returns empty list for empty scan dir', () async {
        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results, isEmpty);
      });

      test('ignores files at scan root level', () async {
        await File(
          p.join(scanRoot.path, 'some_file.txt'),
        ).writeAsString('hello');
        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results, isEmpty);
      });

      test('lists only direct child directories', () async {
        await createPlainProject(scanRoot, 'project-a');
        await createPlainProject(scanRoot, 'project-b');
        // Nested dir should not be listed directly
        final nested = Directory(p.join(scanRoot.path, 'project-a', 'subdir'));
        await nested.create(recursive: true);

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.length, equals(2));
        final ids = results.map((r) => r.folderId).toSet();
        expect(ids, containsAll(['project-a', 'project-b']));
        expect(ids, isNot(contains('subdir')));
      });

      test('skips hidden directories (starting with .)', () async {
        await createPlainProject(scanRoot, 'visible-project');
        final hiddenDir = Directory(p.join(scanRoot.path, '.hidden'));
        await hiddenDir.create();

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.length, equals(1));
        expect(results.first.folderId, equals('visible-project'));
      });

      test(
        'skips directories matching ignore patterns (exact match)',
        () async {
          await createPlainProject(scanRoot, 'my-app');
          await createPlainProject(scanRoot, 'node_modules');

          // Ensure config row exists, then override ignore list
          await db.getConfig();
          await db.updateConfig(ignoreListJson: '["node_modules"]');

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
          expect(results.length, equals(1));
          expect(results.first.folderId, equals('my-app'));
        },
      );

      test(
        'skips directories matching ignore patterns (wildcard prefix *)',
        () async {
          await createPlainProject(scanRoot, 'my-app');
          await createPlainProject(scanRoot, 'build');
          await createPlainProject(scanRoot, 'build-cache');

          // Ensure config row exists, then override ignore list
          await db.getConfig();
          await db.updateConfig(ignoreListJson: '["build*"]');

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
          expect(results.length, equals(1));
          expect(results.first.folderId, equals('my-app'));
        },
      );

      test('results are sorted by displayName', () async {
        await createPlainProject(scanRoot, 'zebra-project');
        await createPlainProject(scanRoot, 'alpha-project');
        await createPlainProject(scanRoot, 'mango-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        final names = results.map((r) => r.displayName).toList();
        // Plain projects use folder name as displayName
        expect(
          names,
          equals(['alpha-project', 'mango-project', 'zebra-project']),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Project metadata (displayName/description) assembly
    // -----------------------------------------------------------------------

    group('project metadata assembly', () {
      test('displayName comes from PROJECT.md H1', () async {
        await createPlanningProject(scanRoot, 'my-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.displayName, equals('my-project'));
      });

      test(
        'displayName falls back to folder name when no PROJECT.md/CLAUDE.md',
        () async {
          await createPlainProject(scanRoot, 'folder-name');

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
          expect(results.first.displayName, equals('folder-name'));
        },
      );

      test('description comes from PROJECT.md Core Value section', () async {
        await createPlanningProject(scanRoot, 'my-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.description, contains('Test project description'));
      });

      test('DB displayName override beats PROJECT.md H1', () async {
        await createPlanningProject(scanRoot, 'my-project');
        await db.setProjectDisplayName('my-project', 'Custom Name');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.displayName, equals('Custom Name'));
      });

      test('clearing DB displayName falls back to PROJECT.md H1', () async {
        await createPlanningProject(scanRoot, 'my-project');
        await db.setProjectDisplayName('my-project', 'Custom Name');
        await db.setProjectDisplayName('my-project', null);

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.displayName, equals('my-project'));
      });

      test('whitespace-only DB displayName is treated as cleared', () async {
        await createPlanningProject(scanRoot, 'my-project');
        await db.setProjectDisplayName('my-project', '   ');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.displayName, equals('my-project'));
      });

      test('folderId is the folder basename', () async {
        await createPlainProject(scanRoot, 'project-folder');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.folderId, equals('project-folder'));
      });

      test('path is the absolute path to the project folder', () async {
        await createPlainProject(scanRoot, 'a-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.path, equals(p.join(scanRoot.path, 'a-project')));
      });
    });

    // -----------------------------------------------------------------------
    // Git data assembly
    // -----------------------------------------------------------------------

    group('git data assembly', () {
      test('non-git project gets null git field', () async {
        // Create a project without git (has .planning/ but no .git/)
        await createPlanningProject(scanRoot, 'no-git-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.git, isNull);
      });

      test('git project gets git field populated', () async {
        await createPlanningProject(scanRoot, 'git-project', withGit: true);

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.git, isNotNull);
        expect(results.first.git!.isEmpty, isFalse);
        expect(results.first.git!.lastCommitMessage, equals('Initial commit'));
      });
    });

    // -----------------------------------------------------------------------
    // DB project type resolution
    // -----------------------------------------------------------------------

    group('project type resolution', () {
      test('projectType inferred as research for plain project', () async {
        await createPlainProject(scanRoot, 'untyped-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.projectType, equals(ProjectType.research));
      });

      test('projectType is set from DB settings', () async {
        await createPlainProject(scanRoot, 'typed-project');

        await db.upsertProjectSettings(
          ProjectSettingsTableCompanion.insert(
            folderId: 'typed-project',
            projectType: const Value('code'),
          ),
        );

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.projectType, equals(ProjectType.code));
      });

      test('multiple projects each get their own type from DB', () async {
        await createPlainProject(scanRoot, 'code-project');
        await createPlainProject(scanRoot, 'research-project');
        await createPlainProject(scanRoot, 'untyped-project');

        await db.upsertProjectSettings(
          ProjectSettingsTableCompanion.insert(
            folderId: 'code-project',
            projectType: const Value('code'),
          ),
        );
        await db.upsertProjectSettings(
          ProjectSettingsTableCompanion.insert(
            folderId: 'research-project',
            projectType: const Value('research'),
          ),
        );

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        final byId = {for (final r in results) r.folderId: r};

        expect(byId['code-project']!.projectType, equals(ProjectType.code));
        expect(
          byId['research-project']!.projectType,
          equals(ProjectType.research),
        );
        expect(
          byId['untyped-project']!.projectType,
          equals(ProjectType.research),
        );
      });
    });

    // -----------------------------------------------------------------------
    // Stale detection
    // -----------------------------------------------------------------------

    group('stale detection', () {
      test(
        'non-stale git project: recent commit returns isStale=false',
        () async {
          await createPlanningProject(
            scanRoot,
            'fresh-git-project',
            withGit: true,
          );

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
          expect(results.first.isStale, isFalse);
        },
      );

      test('non-git project with no signal is not stale', () async {
        await createPlainProject(scanRoot, 'no-signal-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.first.isStale, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Mix of project types
    // -----------------------------------------------------------------------

    group('mixed project types', () {
      test('scan dir with mix of .planning/, git, and plain projects', () async {
        await createPlanningProject(scanRoot, 'full-project', withGit: true);
        await createPlanningProject(scanRoot, 'planning-only');
        await createPlainProject(scanRoot, 'plain-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results.length, equals(3));

        final byId = {for (final r in results) r.folderId: r};

        // full-project: has .planning/ and git
        expect(byId['full-project']!.git, isNotNull);

        // planning-only: has .planning/ but no git
        expect(byId['planning-only']!.git, isNull);

        // plain-project: no .planning/, has git (createPlainProject inits git)
        expect(byId['plain-project']!.git, isNotNull);
      });
    });

    // -----------------------------------------------------------------------
    // Memory data integration
    // -----------------------------------------------------------------------

    group('memory data integration', () {
      test(
        'scanned project has memory == null when no MEMORY.md exists',
        () async {
          await createPlanningProject(scanRoot, 'no-memory-project');

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
          expect(results.length, equals(1));
          expect(results.first.memory, isNull);
        },
      );

      test('ProjectModel.memory field is accessible for UI layer', () async {
        await createPlanningProject(scanRoot, 'memory-check-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);
        final project = results.first;

        // Verify the memory field exists and follows the nullable pattern
        // (null = no memory, non-null = has memory with hasMemory/lastConsolidated/isStale)
        expect(project.memory?.hasMemory, isNull);
        expect(project.memory?.lastConsolidated, isNull);
        expect(project.memory?.isStale, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // Memory cache invalidation (code review MAJOR fix)
    //
    // The cache signature used to be the project directory's own mtime,
    // which does NOT change when rem-sleep writes a new MEMORY.md under
    // ~/.claude/projects/<encoded>/memory/ — a completely different
    // directory. That meant a stale memory indicator survived rescans.
    // The fix uses the MEMORY.md file's own mtime as the signature instead.
    // -----------------------------------------------------------------------

    group('memory cache invalidation (rem-sleep consolidation)', () {
      late Directory claudeHome;
      late ProjectScanner scannerWithClaudeHome;

      setUp(() {
        claudeHome = Directory.systemTemp.createTempSync(
          'claude_home_scanner_test_',
        );
        scannerWithClaudeHome = ProjectScanner(
          db,
          claudeHomeDirOverride: claudeHome.path,
        );
      });

      tearDown(() async {
        await claudeHome.delete(recursive: true);
      });

      /// Mirrors memory_reader's encodeProjectPath (kept local to avoid a
      /// cross-layer test import — the encoding rule is simple and stable).
      String encode(String path) => path
          .replaceAll('/', '-')
          .replaceAll('_', '-')
          .replaceAll(' ', '-')
          .replaceAll('.', '-');

      test(
        'rescan after MEMORY.md is updated returns the new consolidation time',
        () async {
          final projectDir = await createPlanningProject(
            scanRoot,
            'memory-cache-project',
          );
          final encoded = encode(projectDir.path);
          final memoryDir = Directory(
            p.join(claudeHome.path, 'projects', encoded, 'memory'),
          );
          await memoryDir.create(recursive: true);
          final memoryFile = File(p.join(memoryDir.path, 'MEMORY.md'));
          await memoryFile.writeAsString('# Memory v1');

          final results1 = await scannerWithClaudeHome.scanAll(
            scanDirOverride: scanRoot.path,
          );
          final firstConsolidated = results1.first.memory?.lastConsolidated;
          expect(firstConsolidated, isNotNull);

          // Simulate rem-sleep writing a new consolidation later. `touch -t`
          // rounds to whole seconds, so a few-ms delay isn't guaranteed to
          // land in a different second — push the mtime 5 minutes forward
          // instead to make the "after" assertion unambiguous.
          await memoryFile.writeAsString('# Memory v2 - updated');
          final newMtime = DateTime.now().add(const Duration(minutes: 5));
          await Process.run('touch', [
            '-t',
            _touchFormat(newMtime),
            memoryFile.path,
          ]);

          final results2 = await scannerWithClaudeHome.scanAll(
            scanDirOverride: scanRoot.path,
          );
          final secondConsolidated = results2.first.memory?.lastConsolidated;

          expect(secondConsolidated, isNotNull);
          expect(
            secondConsolidated!.isAfter(firstConsolidated!),
            isTrue,
            reason:
                'Cache must invalidate on MEMORY.md mtime change, not '
                'project directory mtime',
          );
        },
      );
    });

    // -----------------------------------------------------------------------
    // _FileCache: mtime-based caching
    // -----------------------------------------------------------------------

    group('_FileCache (repeated scanAll calls)', () {
      test('second scanAll() returns same results as first', () async {
        await createPlanningProject(scanRoot, 'cached-project');
        await createPlainProject(scanRoot, 'plain-project');

        final results1 = await scanner.scanAll(scanDirOverride: scanRoot.path);
        final results2 = await scanner.scanAll(scanDirOverride: scanRoot.path);

        expect(results1.length, equals(results2.length));
        for (int i = 0; i < results1.length; i++) {
          expect(results1[i].folderId, equals(results2[i].folderId));
          expect(results1[i].displayName, equals(results2[i].displayName));
        }
      });

      test('scan after PROJECT.md content changes picks up new data', () async {
        final projDir = await createPlanningProject(
          scanRoot,
          'updating-project',
        );

        final results1 = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results1.first.displayName, equals('updating-project'));

        // Modify PROJECT.md with a small delay to change mtime
        await Future.delayed(const Duration(milliseconds: 50));
        await File(
          p.join(projDir.path, '.planning', 'PROJECT.md'),
        ).writeAsString(
          '# Renamed Project\n\n## Core Value\n\nNew description.\n',
        );

        final results2 = await scanner.scanAll(scanDirOverride: scanRoot.path);
        expect(results2.first.displayName, equals('Renamed Project'));
      });
    });

    // -----------------------------------------------------------------------
    // Git/memory/used-agents result caching (MAJOR-2 rescan cost fix)
    // -----------------------------------------------------------------------

    group('rescan caching (git/memory/used-agents)', () {
      test(
        'unrelated project is unaffected when only one project changes',
        () async {
          await createPlanningProject(scanRoot, 'project-a', withGit: true);
          await createPlanningProject(scanRoot, 'project-b', withGit: true);

          final results1 = await scanner.scanAll(
            scanDirOverride: scanRoot.path,
          );
          final byId1 = {for (final r in results1) r.folderId: r};
          final bHashBefore = byId1['project-b']!.git!.lastCommitHash;

          // Add a new commit to project-a only.
          final projectADir = Directory(p.join(scanRoot.path, 'project-a'));
          await File(
            p.join(projectADir.path, 'new-file.txt'),
          ).writeAsString('x');
          await Process.run(
            'git',
            ['add', '.'],
            workingDirectory: projectADir.path,
            runInShell: true,
          );
          await Process.run(
            'git',
            ['commit', '-m', 'Second commit'],
            workingDirectory: projectADir.path,
            runInShell: true,
          );

          final results2 = await scanner.scanAll(
            scanDirOverride: scanRoot.path,
          );
          final byId2 = {for (final r in results2) r.folderId: r};

          // project-a picked up the new commit.
          expect(
            byId2['project-a']!.git!.lastCommitMessage,
            equals('Second commit'),
          );
          // project-b's cached git data is unchanged (same commit hash).
          expect(byId2['project-b']!.git!.lastCommitHash, equals(bHashBefore));
        },
      );

      test(
        'repeated scanAll() with no changes returns stable git data from cache',
        () async {
          await createPlanningProject(
            scanRoot,
            'stable-project',
            withGit: true,
          );

          final results1 = await scanner.scanAll(
            scanDirOverride: scanRoot.path,
          );
          final results2 = await scanner.scanAll(
            scanDirOverride: scanRoot.path,
          );

          expect(
            results1.first.git!.lastCommitHash,
            equals(results2.first.git!.lastCommitHash),
          );
        },
      );
    });

    // -----------------------------------------------------------------------
    // Vault-root exclusion (010-vault-status-writer FR-022b)
    // -----------------------------------------------------------------------

    group('vault-root exclusion (FR-022b)', () {
      test('a vault root nested inside the scan dir is never listed as a '
          'project, even though it looks like a plain directory', () async {
        final vaultDir = Directory(p.join(scanRoot.path, 'MyVault'));
        await vaultDir.create(recursive: true);
        await db.setVaultDir(vaultDir.path);

        // A real project alongside it must still be found.
        await createPlainProject(scanRoot, 'real-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);

        expect(
          results.any((p) => p.path == vaultDir.path),
          isFalse,
          reason:
              'The configured vault root must never appear as a '
              'ProjectModel, per FR-022b.',
        );
        expect(results.any((p) => p.folderId == 'real-project'), isTrue);
      });

      test(
        'a project directory nested INSIDE the vault root is also excluded',
        () async {
          final vaultDir = Directory(p.join(scanRoot.path, 'MyVault'));
          await vaultDir.create(recursive: true);
          await db.setVaultDir(vaultDir.path);

          // Something that looks like a project, but lives under the vault.
          await createPlainProject(vaultDir, 'hub-that-looks-like-a-project');
          await createPlainProject(scanRoot, 'real-project');

          final results = await scanner.scanAll(scanDirOverride: scanRoot.path);

          expect(
            results.any((p) => p.folderId == 'hub-that-looks-like-a-project'),
            isFalse,
          );
          expect(results.any((p) => p.folderId == 'real-project'), isTrue);
        },
      );

      test('no vault configured (default resolution) does not exclude '
          'unrelated project directories', () async {
        await createPlainProject(scanRoot, 'real-project');

        final results = await scanner.scanAll(scanDirOverride: scanRoot.path);

        expect(results.any((p) => p.folderId == 'real-project'), isTrue);
      });
    });
  });
}

/// Formats a DateTime for the macOS `touch -t` command (YYYYMMDDhhmm.ss).
String _touchFormat(DateTime dt) {
  return '${dt.year}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '.${dt.second.toString().padLeft(2, '0')}';
}
