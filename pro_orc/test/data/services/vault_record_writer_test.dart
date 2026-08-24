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

    test(
      'fence breakout: body containing a bare ``` fence is still fully '
      'contained inside the rendered note\'s own fence (adaptive fence '
      'length, CommonMark rule)',
      () async {
        final body =
            'Some intro text.\n'
            '```\n'
            'nested code block\n'
            '```\n'
            'More output after the nested fence.';

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-progress',
          skillDisplayName: 'a1-progress',
          outcome: 'erfolgreich',
          bodyContent: body,
          completedAt: completedAt,
        );

        final content = await File(result.path!).readAsString();
        final ausgabeIndex = content.indexOf('## Ausgabe');
        expect(ausgabeIndex, greaterThanOrEqualTo(0));
        final afterHeading = content.substring(ausgabeIndex);

        // The opening fence for the body must be longer than the longest
        // backtick run inside the body (here 3), so the body's own ``` runs
        // never close it early.
        final openFenceMatch = RegExp(
          r'\n(`{3,})\n',
        ).firstMatch(afterHeading);
        expect(
          openFenceMatch,
          isNotNull,
          reason: 'expected an opening fence line after ## Ausgabe',
        );
        final fenceLen = openFenceMatch!.group(1)!.length;
        expect(
          fenceLen,
          greaterThan(3),
          reason:
              'fence must be longer than the longest run inside the body '
              '(3) to actually contain it',
        );

        // Exactly two fence delimiters of that exact length should exist
        // (the wrapper's open + close) — the body's shorter ``` runs must
        // not be recognized as fence delimiters of the same length.
        final delimiterPattern = RegExp('^`{$fenceLen}\$', multiLine: true);
        final delimiterCount = delimiterPattern
            .allMatches(afterHeading)
            .length;
        expect(delimiterCount, equals(2));

        // The nested content must appear verbatim, unrendered, between the
        // wrapper's open and close fence.
        expect(content, contains('nested code block'));
        expect(content, contains('More output after the nested fence.'));
      },
    );

    test(
      'fence breakout: a longer nested fence (````js) still gets fully '
      'contained — adaptive fence length scans the whole body',
      () async {
        final body =
            'Text before.\n'
            '````js\n'
            'const x = 1;\n'
            '```\n'
            'still inside\n'
            '```\n'
            '````\n'
            'Text after.';

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-checklist',
          skillDisplayName: 'a1-checklist',
          outcome: 'erfolgreich',
          bodyContent: body,
          completedAt: completedAt,
        );

        final content = await File(result.path!).readAsString();
        final ausgabeIndex = content.indexOf('## Ausgabe');
        final afterHeading = content.substring(ausgabeIndex);

        final openFenceMatch = RegExp(
          r'\n(`{3,})\n',
        ).firstMatch(afterHeading);
        expect(openFenceMatch, isNotNull);
        final fenceLen = openFenceMatch!.group(1)!.length;
        // Longest run inside the body is 4 (````js) -> wrapper must use >= 5.
        expect(fenceLen, greaterThan(4));

        final delimiterPattern = RegExp('^`{$fenceLen}\$', multiLine: true);
        expect(delimiterPattern.allMatches(afterHeading).length, equals(2));
      },
    );

    test(
      'fence breakout: body containing frontmatter-like lines and a '
      'wikilink after a fence never renders as live Markdown outside the '
      'wrapper fence (vault graph pollution guard)',
      () async {
        final body =
            '```\n'
            '---\n'
            'type: project\n'
            '---\n'
            'part_of [[project/some-other-project]]\n'
            '```\n'
            'trailing output';

        final result = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-progress',
          skillDisplayName: 'a1-progress',
          outcome: 'erfolgreich',
          bodyContent: body,
          completedAt: completedAt,
        );

        final content = await File(result.path!).readAsString();
        final ausgabeIndex = content.indexOf('## Ausgabe');
        final afterHeading = content.substring(ausgabeIndex);

        final openFenceMatch = RegExp(
          r'\n(`{3,})\n',
        ).firstMatch(afterHeading);
        expect(openFenceMatch, isNotNull);
        final fenceLen = openFenceMatch!.group(1)!.length;
        final openFenceEnd = openFenceMatch.end;
        final closeFenceMatch = RegExp(
          '\\n`{$fenceLen}\\n',
        ).firstMatch(afterHeading.substring(openFenceEnd));
        expect(
          closeFenceMatch,
          isNotNull,
          reason: 'expected a matching close fence of the same length',
        );

        // The only 'part_of' wikilink-style line in the whole note must be
        // the legitimate Relations one written by the template — the one
        // embedded in the body must stay literal text inside the fence,
        // not become a second live Relations-style line outside it.
        final relationsPartOf = 'part_of [[project/pro-orc]]';
        expect(content, contains(relationsPartOf));
        final occurrences = 'part_of [['.allMatches(content).length;
        expect(
          occurrences,
          equals(2),
          reason:
              'exactly the template Relations line + the literal body '
              'occurrence — neither multiplied nor escaped out of the fence',
        );
      },
    );

    test(
      'YAML title escaping: a skillDisplayName containing a colon/quote/'
      'newline is rendered as a safe double-quoted YAML scalar, never '
      'breaking the frontmatter block',
      () async {
        final result = await writer.write(
          vaultRoot: vaultDir.path,
          projectHubSlug: 'pro-orc',
          skillSlug: 'a1-progress',
          skillDisplayName: 'a1-progress: "status" check\nnewline',
          outcome: 'erfolgreich',
          bodyContent: 'output',
          completedAt: completedAt,
        );

        final content = await File(result.path!).readAsString();
        final lines = content.split('\n');

        // Exactly two '---' frontmatter delimiter lines — a raw ':' or
        // newline in the title must not have introduced a third by
        // accident (e.g. splitting the YAML block early).
        expect(lines.where((l) => l == '---').length, equals(2));

        final titleLine = lines.firstWhere((l) => l.startsWith('title:'));
        expect(
          titleLine,
          equals(
            r'title: "a1-progress: \"status\" check\nnewline – erfolgreich"',
          ),
        );
      },
    );

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
