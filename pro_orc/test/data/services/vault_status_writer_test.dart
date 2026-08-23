import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/services/vault_status_writer.dart';

Future<Directory> _createTempVault() async {
  final dir = await Directory.systemTemp.createTemp('vault_writer_test_');
  await Directory(p.join(dir.path, 'project')).create(recursive: true);
  return dir;
}

VaultStatusFields _fieldsAt(DateTime lastSync) => VaultStatusFields(
  status: 'building',
  progress: 55,
  phase: 'Phase 3 von 5: Vault-Integration',
  milestone: 'M12 — Vault-Integration',
  lastCommit: '2026-08-22T14:03:00.000Z',
  lastSync: lastSync,
);

void main() {
  late Directory vaultDir;
  late VaultStatusWriter writer;

  setUp(() async {
    vaultDir = await _createTempVault();
    writer = VaultStatusWriter();
  });

  tearDown(() async {
    await vaultDir.delete(recursive: true);
  });

  group('auto-create (FR-006/FR-007)', () {
    test(
      'creates a new hub with minimal frontmatter and marker block',
      () async {
        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        expect(result, equals(VaultWriteResult.created));

        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        expect(file.existsSync(), isTrue);
        final content = await file.readAsString();

        expect(content, contains('type: project'));
        expect(content, contains('title: Pro Orc'));
        expect(content, contains('proorc_status: building'));
        expect(content, contains('proorc_progress: 55'));
        expect(content, contains('proorc_phase:'));
        expect(content, contains('proorc_milestone:'));
        expect(content, contains('proorc_last_commit:'));
        expect(content, contains('proorc_last_sync:'));
        expect(content, contains('<!-- proorc:status:start -->'));
        expect(content, contains('<!-- proorc:status:end -->'));
      },
    );

    test('auto-create does not touch any other file in the vault', () async {
      final indexFile = File(p.join(vaultDir.path, 'project', 'index.md'));
      await indexFile.writeAsString('# Index\n\nHand-curated content.\n');
      final indexBefore = await indexFile.readAsString();

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final indexAfter = await indexFile.readAsString();
      expect(indexAfter, equals(indexBefore));

      final entries = await Directory(
        p.join(vaultDir.path, 'project'),
      ).list().toList();
      final names = entries.map((e) => p.basename(e.path)).toSet();
      expect(names, equals({'index.md', 'pro-orc.md'}));
    });

    test('handles umlauts and special characters in display name', () async {
      final result = await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'muenchen-buero',
        displayName: 'München Büro – Ãbc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      expect(result, equals(VaultWriteResult.created));
      final file = File(p.join(vaultDir.path, 'project', 'muenchen-buero.md'));
      final content = await file.readAsString();
      expect(content, contains('München Büro'));
    });
  });

  group('existing hub, keys preserved (FR-008)', () {
    test('preserves pre-existing frontmatter keys and body prose', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
title: Pro Orc
tags: [foo]
permalink: bar
---

Hand-written prose that must survive untouched.
''');

      final result = await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      expect(result, equals(VaultWriteResult.written));
      final content = await file.readAsString();

      expect(content, contains('tags: [foo]'));
      expect(content, contains('permalink: bar'));
      expect(content, contains('proorc_status: building'));
      expect(content, contains('proorc_progress: 55'));
      expect(
        content,
        contains('Hand-written prose that must survive untouched.'),
      );
    });
  });

  group('marker replace only (FR-009)', () {
    test('replaces only the inter-marker text, prose untouched', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
title: Pro Orc
---

Prose before the marker block.

<!-- proorc:status:start -->
**Status:** stale-value-from-last-week
<!-- proorc:status:end -->

Prose after the marker block.
''');

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final content = await file.readAsString();

      expect(content, isNot(contains('stale-value-from-last-week')));
      expect(content, contains('building'));

      // Byte-exact: the body prose immediately surrounding the markers is
      // untouched, not merely "still present somewhere" in the file.
      final secondDashLineEnd = content.indexOf(
        '\n',
        content.indexOf('\n---', 4) + 1,
      );
      final body = content.substring(secondDashLineEnd + 1);
      final beforeMarker = body.substring(
        0,
        body.indexOf('<!-- proorc:status:start -->'),
      );
      final afterMarker = body.substring(
        body.indexOf('<!-- proorc:status:end -->') +
            '<!-- proorc:status:end -->'.length,
      );
      expect(
        beforeMarker,
        equals('''

Prose before the marker block.

'''),
      );
      expect(
        afterMarker,
        equals('''


Prose after the marker block.
'''),
      );
    });
  });

  group('marker insertion (FR-010)', () {
    test('inserts marker pair after frontmatter when absent', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
title: Pro Orc
---

Original body content with no marker block yet.
''');

      final result = await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      expect(result, equals(VaultWriteResult.written));
      final content = await file.readAsString();

      expect(content, contains('<!-- proorc:status:start -->'));
      expect(content, contains('<!-- proorc:status:end -->'));
      expect(
        content,
        contains('Original body content with no marker block yet.'),
      );

      final startIdx = content.indexOf('<!-- proorc:status:start -->');
      final bodyIdx = content.indexOf('Original body content');
      expect(startIdx, lessThan(bodyIdx));

      final frontmatterEndIdx = content.indexOf('---', 4);
      expect(startIdx, greaterThan(frontmatterEndIdx));
    });
  });

  group('no prose leakage (FR-011)', () {
    test('written file contains no forbidden freeform content', () async {
      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      final content = await file.readAsString();

      expect(content, isNot(contains('github.com/fake-org/fake-repo')));
      expect(
        content,
        isNot(contains('This project looks great and is on track')),
      );
    });
  });

  group('path traversal (FR-015)', () {
    test('rejects a hubSlug containing ".." segments', () async {
      final result = await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: '../../etc/passwd',
        displayName: 'Evil',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      expect(result, equals(VaultWriteResult.skippedOutsideRoot));

      final outsideFile = File(
        p.normalize(p.join(vaultDir.path, '..', '..', 'etc', 'passwd.md')),
      );
      expect(outsideFile.existsSync(), isFalse);
    });

    test(
      'rejects a hubSlug that escapes the vault root by two levels',
      () async {
        // 'project/../../outside' resolves to a sibling of vaultRoot itself,
        // not merely a sibling of the 'project' subfolder — genuinely outside
        // vaultRoot, unlike a single '../' which can still land back inside it.
        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: '../../outside',
          displayName: 'Evil',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        expect(result, equals(VaultWriteResult.skippedOutsideRoot));
        final outsideFile = File(
          p.normalize(p.join(vaultDir.path, '..', 'outside.md')),
        );
        expect(outsideFile.existsSync(), isFalse);
      },
    );
  });

  group('hardcoded hub folder scope (FR-020)', () {
    test('never creates anything under a sibling IA folder', () async {
      await Directory(p.join(vaultDir.path, 'pattern')).create(recursive: true);

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final patternEntries = await Directory(
        p.join(vaultDir.path, 'pattern'),
      ).list().toList();
      expect(patternEntries, isEmpty);
    });
  });

  group('soft-fail on IO errors', () {
    test(
      'locked/unreadable target does not throw, returns typed failure',
      () async {
        // Simulate an unreadable target by pointing the hub folder at a path
        // segment that is actually a file, not a directory — Directory.create
        // and File writes both fail with a FileSystemException in that case.
        final blockerFile = File(p.join(vaultDir.path, 'blocked-folder'));
        await blockerFile.writeAsString('I am a file, not a directory');

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'blocked-folder',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        expect(
          result,
          anyOf(
            equals(VaultWriteResult.skippedIoError),
            equals(VaultWriteResult.skippedLocked),
          ),
        );
      },
    );
  });
}
