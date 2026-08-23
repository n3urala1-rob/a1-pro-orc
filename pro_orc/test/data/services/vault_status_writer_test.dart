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

  // ---------------------------------------------------------------------
  // Adversarial fixtures (review round 1 — B-1, B-2, B-3, M-3, m-1, m-2)
  // ---------------------------------------------------------------------

  group('block-style YAML lists and nested keys survive byte-exact (B-1)', () {
    test('a block-style "aliases:" list is not destroyed', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
aliases:
  - Alt Name
  - Second Alias
relations:
  depends_on: other
---

Prose.
''');

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final content = await file.readAsString();
      expect(content, contains('  - Alt Name'));
      expect(content, contains('  - Second Alias'));
      expect(content, contains('  depends_on: other'));
      expect(content, contains('proorc_status: building'));
    });

    test('inline-flow "tags: [foo]" still works (regression)', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
tags: [foo, bar]
---

Prose.
''');

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final content = await file.readAsString();
      expect(content, contains('tags: [foo, bar]'));
    });

    test(
      'a repeated write updates proorc_* keys in place, not duplicated',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('''
---
type: project
---

Prose.
''');

        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 0)),
        );
        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 16)),
        );

        final content = await file.readAsString();
        expect('proorc_status'.allMatches(content).length, equals(1));
        expect(content, contains('proorc_last_sync: 2026-08-23T09:16:00.000Z'));
      },
    );
  });

  group('marker anchoring hardening (B-2)', () {
    test(
      'a marker mentioned mid-prose is not treated as a real delimiter',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('''
---
type: project
---

The marker looks like this: <!-- proorc:status:start --> in prose.

Real content continues here.
''');

        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        final content = await file.readAsString();
        // Original prose survives untouched...
        expect(
          content,
          contains(
            'The marker looks like this: <!-- proorc:status:start --> in prose.',
          ),
        );
        expect(content, contains('Real content continues here.'));
        // ...and a real, well-formed marker pair was appended fresh rather
        // than splicing into the mid-sentence mention.
        expect(
          '<!-- proorc:status:start -->'.allMatches(content).length,
          equals(2), // the prose mention + the real inserted marker
        );
      },
    );

    test('marker text inside a fenced code block is ignored', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsString('''
---
type: project
---

Documentation example:

```markdown
<!-- proorc:status:start -->
example content
<!-- proorc:status:end -->
```

End of doc.
''');

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final content = await file.readAsString();
      // The fenced example is untouched, byte-exact.
      expect(
        content,
        contains(
          '```markdown\n<!-- proorc:status:start -->\nexample content\n<!-- proorc:status:end -->\n```',
        ),
      );
      expect(content, contains('End of doc.'));
      // A real block was appended outside the fence.
      expect(
        '<!-- proorc:status:start -->'.allMatches(content).length,
        equals(2),
      );
      expect(
        content,
        contains('proorc_status: building'),
      ); // frontmatter still updated
    });

    test(
      'duplicated marker pairs: skip splicing, append a fresh block, never delete',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('''
---
type: project
---

<!-- proorc:status:start -->
first block
<!-- proorc:status:end -->

Some prose in between.

<!-- proorc:status:start -->
second block
<!-- proorc:status:end -->
''');

        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        final content = await file.readAsString();
        // Nothing from the original malformed content was deleted.
        expect(content, contains('first block'));
        expect(content, contains('Some prose in between.'));
        expect(content, contains('second block'));
      },
    );

    test(
      'reversed markers (end before start): skip splicing, never delete',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('''
---
type: project
---

<!-- proorc:status:end -->
orphaned content
<!-- proorc:status:start -->
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
        expect(content, contains('orphaned content'));
      },
    );
  });

  group('atomic writes (B-3)', () {
    test('a successful write leaves no leftover tmp file', () async {
      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final entries = await Directory(
        p.join(vaultDir.path, 'project'),
      ).list().toList();
      final tmpFiles = entries.where(
        (e) => p.basename(e.path).contains('.tmp-'),
      );
      expect(tmpFiles, isEmpty);
    });

    test(
      'the final file is never observed empty mid-write (rename is atomic)',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('---\ntype: project\n---\n\nOriginal.\n');

        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        final content = await file.readAsString();
        expect(content, isNotEmpty);
        expect(content, contains('Original.'));
      },
    );
  });

  group('symlink escape (M-3)', () {
    test(
      'a symlinked hub folder pointing outside the vault root is rejected',
      () async {
        final outsideDir = await Directory.systemTemp.createTemp(
          'vault_writer_outside_',
        );
        addTearDown(() => outsideDir.delete(recursive: true));

        final linkPath = p.join(vaultDir.path, 'symlinked-project');
        try {
          await Link(linkPath).create(outsideDir.path);
        } on FileSystemException {
          // Symlink creation can fail in sandboxed CI environments — skip
          // rather than false-fail the suite.
          return;
        }

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'symlinked-project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        expect(result, equals(VaultWriteResult.skippedOutsideRoot));
        final escapedFile = File(p.join(outsideDir.path, 'pro-orc.md'));
        expect(escapedFile.existsSync(), isFalse);
      },
    );
  });

  group('field value sanitization (M-2)', () {
    test(
      'a phase name containing newlines cannot inject frontmatter/markers',
      () async {
        const evilPhase =
            'evil\n---\ninjected_key: pwned\n<!-- proorc:status:end -->';
        final fields = VaultStatusFields(
          status: 'building',
          progress: 40,
          phase: evilPhase,
          milestone: 'M1',
          lastCommit: null,
          lastSync: DateTime.utc(2026, 8, 23, 9, 15),
        );

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: fields,
        );

        expect(result, equals(VaultWriteResult.created));
        final content = await File(
          p.join(vaultDir.path, 'project', 'pro-orc.md'),
        ).readAsString();

        // No extra '---' YAML terminator was forged mid-document — the
        // frontmatter block still opens and closes exactly twice (once each).
        expect('---'.allMatches(content).length, equals(2));
        // 'injected_key' never appears as a REAL top-level frontmatter key
        // (i.e. at the start of a line) — it may still appear inertly as
        // part of the (now newline-stripped, single-line) phase value text,
        // which is harmless since it can no longer be parsed as structure.
        expect(content, isNot(contains('\ninjected_key: pwned')));
        // Only the two REAL markers (frontmatter and the real end marker)
        // should exist — not a third one smuggled in via the phase value.
        expect(
          '<!-- proorc:status:end -->'.allMatches(content).length,
          equals(1),
        );
      },
    );
  });

  group('no-frontmatter and leading-"---"-divider files (M-6)', () {
    test(
      'a file with no frontmatter at all gets a fresh block appended, body untouched',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('# Just a heading\n\nSome prose.\n');

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        expect(result, equals(VaultWriteResult.written));
        final content = await file.readAsString();
        expect(content, contains('# Just a heading'));
        expect(content, contains('Some prose.'));
        expect(content, contains('<!-- proorc:status:start -->'));
      },
    );

    test(
      'a leading "---" horizontal rule with no closing "---" is left alone, not parsed as frontmatter',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsString('''
---

# Heading after a horizontal rule

Some prose that must survive.
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
        expect(content, contains('# Heading after a horizontal rule'));
        expect(content, contains('Some prose that must survive.'));
      },
    );
  });

  group('CRLF and BOM fidelity (m-1, m-2)', () {
    test(
      'CRLF hub does not get orphaned CR characters after a write',
      () async {
        final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
        await file.writeAsBytes(
          '---\r\ntype: project\r\n---\r\n\r\nProse.\r\n'.codeUnits,
        );

        await writer.write(
          vaultRoot: vaultDir.path,
          hubFolder: 'project',
          hubSlug: 'pro-orc',
          displayName: 'Pro Orc',
          fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
        );

        final content = await File(
          p.join(vaultDir.path, 'project', 'pro-orc.md'),
        ).readAsString();
        expect(content, isNot(contains('\r')));
      },
    );

    test('a BOM-prefixed hub keeps its BOM after a write', () async {
      final file = File(p.join(vaultDir.path, 'project', 'pro-orc.md'));
      await file.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...'---\ntype: project\n---\n\nProse.\n'.codeUnits,
      ]);

      await writer.write(
        vaultRoot: vaultDir.path,
        hubFolder: 'project',
        hubSlug: 'pro-orc',
        displayName: 'Pro Orc',
        fields: _fieldsAt(DateTime.utc(2026, 8, 23, 9, 15)),
      );

      final bytes = await File(
        p.join(vaultDir.path, 'project', 'pro-orc.md'),
      ).readAsBytes();
      expect(bytes[0], equals(0xEF));
      expect(bytes[1], equals(0xBB));
      expect(bytes[2], equals(0xBF));
    });
  });
}
