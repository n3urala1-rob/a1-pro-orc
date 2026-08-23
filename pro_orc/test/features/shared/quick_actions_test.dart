import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/quick_actions_service.dart';
import 'package:pro_orc/features/shared/quick_actions.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

const _archiveGroupId = '__archiv__';

ProjectModel _project(String folderId) => ProjectModel(
  folderId: folderId,
  displayName: folderId,
  path: '/tmp/$folderId',
);

/// A minimal harness widget that renders `buildQuickActionRow` for [project]
/// so widget tests can inspect the resulting icon/disabled state without
/// pumping a full ProjectCard or QuickActionsSection.
class _Harness extends ConsumerWidget {
  const _Harness({required this.project});

  final ProjectModel project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final actions = buildProjectQuickActions(
      project,
      QuickActionsService(),
      ref,
    );
    return buildQuickActionRow(actions, colors);
  }
}

Future<void> _pumpHarness(
  WidgetTester tester,
  ProjectModel project, {
  required ProviderScope Function(Widget child) scope,
}) async {
  await tester.pumpWidget(
    scope(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Scaffold(body: _Harness(project: project)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('buildProjectQuickActions — vault sync action (FR-014)', () {
    testWidgets(
      'a non-Archiv project includes the "Jetzt synchronisieren" action',
      (tester) async {
        await _pumpHarness(
          tester,
          _project('pro-orc'),
          scope: (child) => ProviderScope(
            overrides: [
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
            ],
            child: child,
          ),
        );

        expect(find.byTooltip('Jetzt synchronisieren'), findsOneWidget);
      },
    );

    testWidgets('an Archiv-group project OMITS the action entirely', (
      tester,
    ) async {
      await _pumpHarness(
        tester,
        _project('archived-proj'),
        scope: (child) => ProviderScope(
          overrides: [
            membershipProvider.overrideWith(
              () => _FakeMembershipNotifier({'archived-proj': _archiveGroupId}),
            ),
          ],
          child: child,
        ),
      );

      expect(find.byTooltip('Jetzt synchronisieren'), findsNothing);
    });

    testWidgets(
      'onPressed is null (disabled) while isSyncing is true for this project',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await _pumpHarness(
          tester,
          _project('pro-orc'),
          scope: (child) => ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              vaultStatusProvider.overrideWith(
                () => _FakeVaultStatusNotifier({'pro-orc'}),
              ),
            ],
            child: child,
          ),
        );

        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Jetzt synchronisieren'),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets(
      'onPressed is non-null (enabled) when isSyncing is false for this project',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await _pumpHarness(
          tester,
          _project('pro-orc'),
          scope: (child) => ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              vaultStatusProvider.overrideWith(
                () => _FakeVaultStatusNotifier(const {}),
              ),
            ],
            child: child,
          ),
        );

        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Jetzt synchronisieren'),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      'a different project in-flight does not disable THIS project\'s button',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await _pumpHarness(
          tester,
          _project('pro-orc'),
          scope: (child) => ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              membershipProvider.overrideWith(
                () => _FakeMembershipNotifier({'pro-orc': null}),
              ),
              vaultStatusProvider.overrideWith(
                () => _FakeVaultStatusNotifier({'some-other-project'}),
              ),
            ],
            child: child,
          ),
        );

        final button = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Jetzt synchronisieren'),
            matching: find.byType(IconButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );
  });

  group('buildQuickActionRow — disabled visual state', () {
    testWidgets(
      'renders a dimmed icon color when QuickAction.disabled is true',
      (tester) async {
        final colors = AppColors.dark;
        final actions = [
          QuickAction(
            icon: LucideIcons.refreshCw100,
            tooltip: 'Test Enabled',
            onPressed: () {},
          ),
          QuickAction(
            icon: LucideIcons.refreshCw100,
            tooltip: 'Test Disabled',
            onPressed: () {},
            disabled: true,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(extensions: [colors]),
            home: Scaffold(body: buildQuickActionRow(actions, colors)),
          ),
        );

        final enabledIcon = tester.widget<Icon>(
          find.descendant(
            of: find.ancestor(
              of: find.byTooltip('Test Enabled'),
              matching: find.byType(IconButton),
            ),
            matching: find.byType(Icon),
          ),
        );
        final disabledIcon = tester.widget<Icon>(
          find.descendant(
            of: find.ancestor(
              of: find.byTooltip('Test Disabled'),
              matching: find.byType(IconButton),
            ),
            matching: find.byType(Icon),
          ),
        );

        expect(enabledIcon.color, isNot(equals(disabledIcon.color)));
      },
    );
  });
}

/// Fake [ProjectGroupMembershipNotifier] seeding fixed state without any DB
/// access — the real notifier's `build()` awaits `projectsProvider.future`,
/// which would otherwise hit the real filesystem in a widget test.
class _FakeMembershipNotifier extends ProjectGroupMembershipNotifier {
  _FakeMembershipNotifier(this._seed);
  final Map<String, String?> _seed;

  @override
  Map<String, String?> build() => _seed;
}

/// Fake [VaultStatusNotifier] exposing a fixed in-flight set without
/// performing any real writes.
class _FakeVaultStatusNotifier extends VaultStatusNotifier {
  _FakeVaultStatusNotifier(this._seed);
  final Set<String> _seed;

  @override
  Set<String> build() => _seed;
}
