import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/project_type.dart';
import 'package:pro_orc/features/projects/a1_badge.dart';
import 'package:pro_orc/features/projects/project_card.dart';
import 'package:pro_orc/features/projects/type_badge.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/watcher_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';
import 'package:watcher/watcher.dart';

Future<void> _pump(
  WidgetTester tester,
  ProjectModel project, {
  AppDatabase? db,
}) async {
  final database = db ?? AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        watcherProvider.overrideWith((ref) => const Stream<WatchEvent>.empty()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Scaffold(body: ProjectCard(project: project)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the Code TypeBadge for a code project', (tester) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo',
        path: '/tmp/demo',
        projectType: ProjectType.code,
      ),
    );

    expect(find.byType(TypeBadge), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
  });

  testWidgets('shows the Research TypeBadge for a research project', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo',
        path: '/tmp/demo',
        projectType: ProjectType.research,
      ),
    );

    expect(find.text('Research'), findsOneWidget);
  });

  testWidgets('shows the A1Badge when the project has a1 data', (tester) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo',
        path: '/tmp/demo',
        projectType: ProjectType.code,
        a1: A1Data(
          phases: [
            A1Phase(name: 'M1', checkedTasks: 1, totalTasks: 4, planPath: 'x'),
          ],
        ),
      ),
    );

    expect(find.byType(A1Badge), findsOneWidget);
    expect(find.text('a1'), findsOneWidget);
  });

  testWidgets('does not show a1 progress text when a1 is null', (tester) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo',
        path: '/tmp/demo',
        projectType: ProjectType.code,
      ),
    );

    expect(find.text('a1'), findsNothing);
  });

  testWidgets('renders the project display name and description', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo Projekt',
        path: '/tmp/demo',
        projectType: ProjectType.research,
        description: 'Eine Beschreibung',
      ),
    );

    expect(find.text('Demo Projekt'), findsOneWidget);
    expect(find.text('Eine Beschreibung'), findsOneWidget);
  });

  testWidgets('keeps Claude button and quick actions inside a 240px grid cell '
      'even with a1 progress + a maximally long description', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    const longDescription =
        'Diese Beschreibung ist absichtlich sehr lang formuliert, damit '
        'sie bei typischer Kartenbreite garantiert auf drei volle Zeilen '
        'umbricht und den maximal moeglichen vertikalen Platzbedarf der '
        'Beschreibung im Kartenlayout auf die Probe stellt, inklusive '
        'weiterer Fuellwoerter fuer zusaetzliche Zeilenlaenge und Umbruch.';

    const project = ProjectModel(
      folderId: 'demo',
      displayName: 'Demo Projekt mit langem Namen fuer Umbruch',
      path: '/tmp/demo',
      projectType: ProjectType.code,
      description: longDescription,
      a1: A1Data(
        phases: [
          A1Phase(name: 'M1', checkedTasks: 1, totalTasks: 4, planPath: 'x'),
        ],
      ),
    );

    // Simulates the real grid cell: SliverGridDelegateWithFixedCrossAxisCount
    // (group_section.dart) gives every card exactly 240px of height and a
    // typical single-column card width.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          watcherProvider.overrideWith(
            (ref) => const Stream<WatchEvent>.empty(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: const Key('grid-cell'),
                width: 280,
                height: 240,
                child: ProjectCard(project: project),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    final cellRect = tester.getRect(find.byKey(const Key('grid-cell')));
    final buttonRect = tester.getRect(
      find.widgetWithText(TextButton, 'Claude'),
    );
    final quickActionsRect = tester.getRect(find.byTooltip('Finder').first);

    expect(
      buttonRect.bottom,
      lessThanOrEqualTo(cellRect.bottom),
      reason: 'Claude button must stay within the 240px grid cell',
    );
    expect(
      quickActionsRect.bottom,
      lessThanOrEqualTo(cellRect.bottom),
      reason: 'Quick actions row must stay within the 240px grid cell',
    );
  });

  testWidgets('ClaudeSkillsSection (spec 011 FR-002) is never rendered inside '
      'ProjectCard — skill buttons exist only in the Detail Panel', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProjectModel(
        folderId: 'demo',
        displayName: 'Demo',
        path: '/tmp/demo',
        projectType: ProjectType.code,
      ),
    );

    expect(find.text('Claude-Skills'), findsNothing);
  });
}
