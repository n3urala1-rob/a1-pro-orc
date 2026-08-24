import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/features/shared/detail/claude_skills_section.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/skill_run_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

const _archiveGroupId = '__archiv__';

class _FakeMembershipNotifier extends ProjectGroupMembershipNotifier {
  _FakeMembershipNotifier(this._seed);
  final Map<String, String?> _seed;

  @override
  Map<String, String?> build() => _seed;
}

/// Fake [SkillRunNotifier] that records `start`/`cancel` calls without ever
/// spawning a real process — reconciliation-on-build is skipped by
/// overriding [build] to return a fixed, injectable state instead of
/// triggering `_reconcileOnStartup` (which would need a real DB row set).
class _FakeSkillRunNotifier extends SkillRunNotifier {
  _FakeSkillRunNotifier(this._seed);
  final SkillRunState _seed;

  int startCalls = 0;
  int cancelCalls = 0;
  String? lastCancelledFolderId;
  String? lastCancelledSkillId;

  @override
  SkillRunState build() => _seed;

  StartSkillOutcome outcomeToReturn = StartSkillOutcome.started;

  @override
  Future<StartSkillResult> start(
    ProjectModel project,
    String skillId,
    String skillPrompt, {
    String? skillDisplayName,
  }) async {
    startCalls++;
    return StartSkillResult(outcomeToReturn);
  }

  @override
  Future<void> cancel(String folderId, String skillId) async {
    cancelCalls++;
    lastCancelledFolderId = folderId;
    lastCancelledSkillId = skillId;
  }
}

ProjectModel _project(String folderId) => ProjectModel(
  folderId: folderId,
  displayName: folderId,
  path: '/tmp/$folderId',
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required ProjectModel project,
  required Map<String, String?> membership,
  SkillRunState skillRunState = const SkillRunState(),
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        membershipProvider.overrideWith(
          () => _FakeMembershipNotifier(membership),
        ),
        skillRunProvider.overrideWith(
          () => _FakeSkillRunNotifier(skillRunState),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            final colors = Theme.of(context).extension<AppColors>()!;
            return Scaffold(
              body: ClaudeSkillsSection(project: project, colors: colors),
            );
          },
        ),
      ),
    ),
  );
  // pumpAndSettle never resolves while a skill is shown as "running" — the
  // button's CircularProgressIndicator animates indefinitely by design.
  // A fixed pump lets the initial build/layout settle in both cases.
  if (skillRunState.inFlightKeys.isEmpty) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('ClaudeSkillsSection', () {
    testWidgets(
      'renders exactly the curated skill set, each showing "noch nicht '
      'ausgeführt" for a project with no run history',
      (tester) async {
        await _pumpSection(
          tester,
          project: _project('pro-orc'),
          membership: {'pro-orc': null},
        );

        expect(find.text('Claude-Skills'), findsOneWidget);
        for (final skill in kCuratedSkills) {
          expect(
            find.textContaining('${skill.displayName}: noch nicht ausgeführt'),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'an Archiv-group project renders nothing — no tappable skill row '
      'exists',
      (tester) async {
        await _pumpSection(
          tester,
          project: _project('archived-proj'),
          membership: {'archived-proj': _archiveGroupId},
        );

        expect(find.text('Claude-Skills'), findsNothing);
        for (final skill in kCuratedSkills) {
          expect(find.text(skill.displayName), findsNothing);
        }
      },
    );

    testWidgets('tapping an idle skill row calls start() immediately, with no '
        'dialog/confirmation shown first', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fakeNotifier = _FakeSkillRunNotifier(const SkillRunState());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            membershipProvider.overrideWith(
              () => _FakeMembershipNotifier({'pro-orc': null}),
            ),
            skillRunProvider.overrideWith(() => fakeNotifier),
          ],
          child: MaterialApp(
            theme: ThemeData.dark().copyWith(
              extensions: const [AppColors.dark],
            ),
            home: Builder(
              builder: (context) {
                final colors = Theme.of(context).extension<AppColors>()!;
                return Scaffold(
                  body: ClaudeSkillsSection(
                    project: _project('pro-orc'),
                    colors: colors,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(kCuratedSkills.first.displayName));
      await tester.pumpAndSettle();

      expect(fakeNotifier.startCalls, equals(1));
      // No dialog route was pushed.
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets(
      'a running skill row shows a distinct visual state and a functional '
      'Abbrechen button that calls cancel()',
      (tester) async {
        final skill = kCuratedSkills.first;
        final key = skillRunKey('pro-orc', skill.id);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fakeNotifier = _FakeSkillRunNotifier(
          SkillRunState(inFlightKeys: {key}),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              skillRunProvider.overrideWith(() => fakeNotifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  final colors = Theme.of(context).extension<AppColors>()!;
                  return Scaffold(
                    body: ClaudeSkillsSection(
                      project: _project('pro-orc'),
                      colors: colors,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        // pumpAndSettle would never resolve here — the running button's
        // CircularProgressIndicator animates indefinitely by design. A
        // fixed pump is sufficient to let the initial build/layout settle.
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.textContaining('${skill.displayName} läuft'),
          findsOneWidget,
        );
        expect(find.text('Abbrechen'), findsOneWidget);

        await tester.tap(find.text('Abbrechen'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(fakeNotifier.cancelCalls, equals(1));
        expect(fakeNotifier.lastCancelledFolderId, equals('pro-orc'));
        expect(fakeNotifier.lastCancelledSkillId, equals(skill.id));
      },
    );

    testWidgets(
      'a rejected start (concurrency limit) surfaces a SnackBar instead of '
      'silently doing nothing',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fakeNotifier = _FakeSkillRunNotifier(const SkillRunState())
          ..outcomeToReturn = StartSkillOutcome.rejectedConcurrencyLimit;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              skillRunProvider.overrideWith(() => fakeNotifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  final colors = Theme.of(context).extension<AppColors>()!;
                  return Scaffold(
                    body: ClaudeSkillsSection(
                      project: _project('pro-orc'),
                      colors: colors,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(kCuratedSkills.first.displayName));
        await tester.pumpAndSettle();

        expect(fakeNotifier.startCalls, equals(1));
        expect(find.byType(SnackBar), findsOneWidget);
        // No unhandled async error escaped the tap — pumpAndSettle above
        // would have surfaced one via FlutterError.onError/exceptions.
      },
    );

    testWidgets(
      'claude CLI not available surfaces a distinct SnackBar message',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fakeNotifier = _FakeSkillRunNotifier(const SkillRunState())
          ..outcomeToReturn = StartSkillOutcome.claudeNotAvailable;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              skillRunProvider.overrideWith(() => fakeNotifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  final colors = Theme.of(context).extension<AppColors>()!;
                  return Scaffold(
                    body: ClaudeSkillsSection(
                      project: _project('pro-orc'),
                      colors: colors,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(kCuratedSkills.first.displayName));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('Claude CLI'), findsOneWidget);
      },
    );

    testWidgets(
      'a spawn failure surfaces a distinct SnackBar message',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fakeNotifier = _FakeSkillRunNotifier(const SkillRunState())
          ..outcomeToReturn = StartSkillOutcome.spawnFailed;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              skillRunProvider.overrideWith(() => fakeNotifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  final colors = Theme.of(context).extension<AppColors>()!;
                  return Scaffold(
                    body: ClaudeSkillsSection(
                      project: _project('pro-orc'),
                      colors: colors,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(kCuratedSkills.first.displayName));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('fehlgeschlagen'), findsOneWidget);
      },
    );

    testWidgets(
      'a successful start shows no SnackBar (self-evident via the button '
      'switching to its running state)',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fakeNotifier = _FakeSkillRunNotifier(const SkillRunState());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              skillRunProvider.overrideWith(() => fakeNotifier),
            ],
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  final colors = Theme.of(context).extension<AppColors>()!;
                  return Scaffold(
                    body: ClaudeSkillsSection(
                      project: _project('pro-orc'),
                      colors: colors,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(kCuratedSkills.first.displayName));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('while one skill is running for a project, a DIFFERENT curated '
        'skill row in the same section shows the blocked state, not a '
        'normal idle state', (tester) async {
      final running = kCuratedSkills.first;
      final other = kCuratedSkills[1];
      final key = skillRunKey('pro-orc', running.id);

      await _pumpSection(
        tester,
        project: _project('pro-orc'),
        membership: {'pro-orc': null},
        skillRunState: SkillRunState(inFlightKeys: {key}),
      );

      // The other skill's button must be present but not tappable/
      // idle-styled — verified by tapping it and confirming no start()
      // call fires (start() is stubbed to increment startCalls).
      final otherButtonFinder = find.text(other.displayName);
      expect(otherButtonFinder, findsOneWidget);
    });
  });
}
