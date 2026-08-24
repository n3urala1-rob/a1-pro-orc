import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/features/shared/detail/claude_skills_section.dart';
import 'package:pro_orc/features/shared/skill_run_result_dialog.dart';
import 'package:pro_orc/theme/n3_colors.dart';

const _skill = CuratedSkill(
  id: 'a1-progress',
  displayName: 'a1-progress',
  prompt: '/a1-progress',
  icon: Icons.bar_chart,
);

final _project = ProjectModel(
  folderId: 'pro-orc',
  displayName: 'Pro Orc',
  path: '/tmp/pro-orc',
);

SkillRunTableData _row({
  required String status,
  String outputContent = 'Fortschritt: Phase 12 — 78%',
  required File outputFile,
}) {
  outputFile.writeAsStringSync(outputContent);
  final now = DateTime.now();
  return SkillRunTableData(
    id: 'run-1',
    folderId: 'pro-orc',
    skillId: 'a1-progress',
    pid: 12345,
    processStartTime: now,
    startedAt: now,
    status: status,
    completedAt: now,
    outputFilePath: outputFile.path,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('result_dialog_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpDialog(WidgetTester tester, SkillRunTableData row) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SkillRunResultDialog.show(
                context,
                skill: _skill,
                project: _project,
                row: row,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // build the dialog + start the async load
    // Not pumpAndSettle: the dialog's CircularProgressIndicator animates
    // indefinitely, so pumpAndSettle would never resolve on its own.
    // runAsync lets the real dart:io File I/O in _loadContent actually run
    // to completion (tester.pump alone only drives the Flutter frame
    // scheduler/microtask queue, not real OS-level I/O callbacks). Looped
    // with an intervening pump since a single round was observed to be
    // insufficient for a freshly-written temp file's read to land before
    // the next assertion.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  group('SkillRunResultDialog', () {
    testWidgets('success state renders the captured output content', (
      tester,
    ) async {
      final row = _row(
        status: 'success',
        outputContent: 'Fortschritt: Phase 12 — 78%',
        outputFile: File('${tempDir.path}/success.log'),
      );

      await pumpDialog(tester, row);

      expect(find.textContaining('erfolgreich'), findsOneWidget);
      expect(find.textContaining('Fortschritt: Phase 12'), findsOneWidget);
    });

    testWidgets(
      'failure state renders the same dialog shape with the raw error '
      'content in place of a success result',
      (tester) async {
        final row = _row(
          status: 'failure',
          outputContent: 'Error: Rate limit exceeded (429).',
          outputFile: File('${tempDir.path}/failure.log'),
        );

        await pumpDialog(tester, row);

        expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
        expect(
          find.textContaining('Error: Rate limit exceeded'),
          findsOneWidget,
        );
      },
    );

    testWidgets('timeout state renders with the timeout outcome label', (
      tester,
    ) async {
      final row = _row(
        status: 'timeout',
        outputContent: 'still running when killed',
        outputFile: File('${tempDir.path}/timeout.log'),
      );

      await pumpDialog(tester, row);

      expect(find.textContaining('Zeitüberschreitung'), findsOneWidget);
    });

    testWidgets('cancelled state renders with the cancelled outcome label', (
      tester,
    ) async {
      final row = _row(
        status: 'cancelled',
        outputContent: 'partial output before cancel',
        outputFile: File('${tempDir.path}/cancelled.log'),
      );

      await pumpDialog(tester, row);

      expect(find.textContaining('abgebrochen'), findsOneWidget);
    });

    testWidgets('a missing/unreadable output file shows a neutral empty state, '
        'never a crash', (tester) async {
      final now = DateTime.now();
      final row = SkillRunTableData(
        id: 'run-1',
        folderId: 'pro-orc',
        skillId: 'a1-progress',
        pid: 12345,
        processStartTime: now,
        startedAt: now,
        status: 'success',
        completedAt: now,
        outputFilePath: '${tempDir.path}/does-not-exist.log',
      );

      await pumpDialog(tester, row);

      expect(find.text('Kein Inhalt verfügbar'), findsOneWidget);
    });
  });
}
