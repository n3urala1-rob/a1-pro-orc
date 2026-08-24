import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:pro_orc/data/services/vault_record_writer.dart';

void main() {
  group('VaultRecordWriter', () {
    late Directory vaultDir;
    late VaultRecordWriter writer;

    setUp(() async {
      vaultDir = await Directory.systemTemp.createTemp('vault_record_test_');
      writer = VaultRecordWriter();
    });

    tearDown(() async {
      if (await vaultDir.exists()) {
        await vaultDir.delete(recursive: true);
      }
    });

    final completedAt = DateTime(2026, 8, 24, 14, 30);

    test('new note created at record/YYYY-MM-DD-<skill>-<project>.md with '
        'type: record frontmatter and a Relations/part_of line', () async {
      final result = await writer.write(
        vaultRoot: vaultDir.path,
        projectHubSlug: 'pro-orc',
        skillSlug: 'a1-progress',
        skillDisplayName: 'a1-progress',
        outcome: 'erfolgreich',
        bodyContent: 'Alles im grünen Bereich.',
        completedAt: completedAt,
      );

      expect(result.status, equals(VaultRecordWriteStatus.written));
      expect(result.path, isNotNull);

      final expectedPath = p.join(
        vaultDir.path,
        'record',
        '2026-08-24-a1-progress-pro-orc.md',
      );
      expect(result.path, equals(expectedPath));

      final content = await File(expectedPath).readAsString();
      expect(content, contains('type: record'));
      expect(content, contains('## Relations'));
      expect(content, contains('part_of [[project/pro-orc]]'));
      expect(content, contains('Alles im grünen Bereich.'));
      expect(content, contains('erfolgreich'));
    });

    test('not written through VaultStatusWriter status block — no marker '
        'strings anywhere in the output', () async {
      final result = await writer.write(
        vaultRoot: vaultDir.path,
        projectHubSlug: 'pro-orc',
        skillSlug: 'a1-checklist',
        skillDisplayName: 'a1-checklist',
        outcome: 'fehlgeschlagen',
        bodyContent: 'error output here',
        completedAt: completedAt,
      );

      final content = await File(result.path!).readAsString();
      expect(content, isNot(contains('proorc:status')));
      expect(content, isNot(contains('proorc_status')));
      expect(content, isNot(contains('proorc_progress')));
    });

    test(
      'same-day collision: writing twice for the same skill/project/day '
      'does not overwrite the first note — a numeric suffix is used',
      () async {
        final first = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-progress',
          skillDisplayName: 'a1-progress',
          outcome: 'erfolgreich',
          bodyContent: 'first run output',
          completedAt: completedAt,
        );

        final second = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-progress',
          skillDisplayName: 'a1-progress',
          outcome: 'erfolgreich',
          bodyContent: 'second run output',
          completedAt: completedAt,
        );

        expect(first.path, isNot(equals(second.path)));
        expect(second.path, endsWith('-2.md'));

        final firstContent = await File(first.path!).readAsString();
        final secondContent = await File(second.path!).readAsString();
        expect(firstContent, contains('first run output'));
        expect(secondContent, contains('second run output'));
        // The first note is untouched by the second write.
        expect(firstContent, isNot(contains('second run output')));
      },
    );

    test('path traversal guard: a manipulated slug is sanitized and never '
        'escapes vaultRoot', () async {
      final result = await writer.write(
        vaultRoot: vaultDir.path,
        projectHubSlug: '../../etc/passwd',
        skillSlug: '../../../evil',
        skillDisplayName: 'evil skill',
        outcome: 'erfolgreich',
        bodyContent: 'should not escape',
        completedAt: completedAt,
      );

      expect(result.status, equals(VaultRecordWriteStatus.written));
      // The resolved path must remain inside vaultRoot/record/.
      final recordDir = p.join(vaultDir.path, 'record');
      expect(p.isWithin(recordDir, result.path!), isTrue);

      // No file was created outside vaultRoot.
      final outsideFile = File(p.join(vaultDir.parent.path, 'evil-passwd.md'));
      expect(await outsideFile.exists(), isFalse);
    });

    test('no shell usage (structural): the module has zero Process spawn '
        'references — plain file I/O (File/Directory) only', () {
      final source = File(
        p.join(
          Directory.current.path,
          'lib',
          'data',
          'services',
          'vault_record_writer.dart',
        ),
      ).readAsStringSync();
      expect(source, isNot(contains('Process.run')));
      expect(source, isNot(contains('Process.start')));
      expect(source, isNot(contains('dart:io\' as')));
      expect(source, isNot(matches(RegExp(r'\bProcess\b'))));
    });
  });
}
