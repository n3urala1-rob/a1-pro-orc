import 'package:drift/native.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/features/settings/settings_tab.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/projects_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Fake for [FileSelectorPlatform] — the plugin's platform interface is
/// designed to be swapped out via `FileSelectorPlatform.instance` for
/// testing (see file_selector_platform_interface). Only the single method
/// the ignore-list picker uses is overridden; the picked path is fixed at
/// construction time.
class _FakeFileSelectorPlatform extends FileSelectorPlatform {
  _FakeFileSelectorPlatform(this.pathToReturn);

  final String? pathToReturn;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    return pathToReturn;
  }
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      // Since Wave 4, SettingsTab renders VaultLinkCard, which reads
      // vaultLinkStatusesProvider -> projectsProvider. Without this
      // override, pumping SettingsTab triggers the REAL ProjectScanner +
      // watcherProvider chain (a live DirectoryWatcher with background
      // timers) — the same "real scan/watch chain" project_group_
      // membership_provider_test.dart avoids with this exact override.
      // Left unmocked, a test that pumpAndSettle()s long enough for the
      // watcher's internal timer to fire hits "Timer still pending after
      // dispose" at teardown.
      projectsProvider.overrideWith((ref) async => []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: const Scaffold(body: SettingsTab()),
      ),
    ),
  );
  // Initial frame shows the loading spinner while _loadSettings() awaits.
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final originalFileSelector = FileSelectorPlatform.instance;

  tearDown(() {
    FileSelectorPlatform.instance = originalFileSelector;
  });

  group('SettingsTab ignore pattern add (folder picker)', () {
    testWidgets(
      'plus click opens the picker; picked folder basename becomes a chip '
      'and is persisted',
      (tester) async {
        FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
          '/Users/rob/code/build-artifacts',
        );

        final container = await _pump(tester);
        await tester.tap(
          find.widgetWithIcon(IconButton, Icons.add_circle_outline),
        );
        await tester.pumpAndSettle();

        expect(find.text('build-artifacts'), findsOneWidget);
        expect(find.widgetWithText(Chip, 'build-artifacts'), findsOneWidget);

        final db = container.read(appDatabaseProvider);
        final config = await db.getConfig();
        expect(config.ignoreListJson, contains('build-artifacts'));
      },
    );

    testWidgets('picker cancelled (null) adds nothing and writes nothing', (
      tester,
    ) async {
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(null);

      final container = await _pump(tester);
      final db = container.read(appDatabaseProvider);
      final chipCountBefore = find.byType(Chip).evaluate().length;
      final ignoreListJsonBefore = (await db.getConfig()).ignoreListJson;

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Chip).evaluate().length, chipCountBefore);
      final configAfter = await db.getConfig();
      expect(configAfter.ignoreListJson, ignoreListJsonBefore);
    });

    testWidgets('picking a folder whose basename is already ignored adds no '
        'second chip', (tester) async {
      // "build" is part of the DB's default ignore list (see
      // app_config_table.dart) — use a basename that isn't, so the
      // duplicate is unambiguously caused by this test's own first pick.
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
        '/Users/rob/code/dist-artifacts',
      );

      final container = await _pump(tester);

      // Add it once.
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'dist-artifacts'), findsOneWidget);

      // Pick a different path with the same basename. The chip added
      // above may have pushed the button below the fold in the test
      // viewport — that's a real, harmless scroll offset (not a hidden
      // widget), so tap with warnIfMissed: false rather than fighting
      // the scroll position.
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(
        '/Users/rob/other/dist-artifacts',
      );
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'dist-artifacts'), findsOneWidget);

      final db = container.read(appDatabaseProvider);
      final config = await db.getConfig();
      expect('dist-artifacts'.allMatches(config.ignoreListJson).length, 1);
    });
  });

  group('Vault-Sync hub-folder field (M-4, review round 1)', () {
    testWidgets(
      'the field is pre-filled with the persisted vaultHubFolder value',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        await database.setVaultHubFolder('records');

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            // See _pump()'s matching override for why this is required.
            projectsProvider.overrideWith((ref) async => []),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: const Scaffold(body: SettingsTab()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(
          find.byWidgetPredicate(
            (w) => w is TextField && w.controller?.text == 'records',
          ),
        );
        expect(field.controller!.text, equals('records'));
      },
    );

    testWidgets(
      'editing the field and tapping Speichern calls setVaultHubFolder',
      (tester) async {
        final container = await _pump(tester);
        final db = container.read(appDatabaseProvider);

        expect(await db.getVaultHubFolder(), equals('project'));

        // Identify the field by its HINT text ('project', from
        // _saveVaultHubFolder's fallback), not its current controller
        // text — the hint is stable across enterText, unlike the
        // controller value, so finders built on top of it stay valid after
        // editing (find.ancestor/descendant re-evaluate their `of:` finder
        // lazily at use-time; a finder keyed on transient text silently
        // resolves to zero widgets once that text changes).
        final fieldFinder = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'project',
        );
        expect(fieldFinder, findsOneWidget);

        final rowFinder = find.ancestor(
          of: fieldFinder,
          matching: find.byType(Row),
        );
        final saveButton = find.descendant(
          of: rowFinder,
          matching: find.widgetWithText(TextButton, 'Speichern'),
        );
        expect(saveButton, findsOneWidget);

        await tester.enterText(fieldFinder, 'idea');
        // The Vault-Sync section (further down the settings page) can push
        // this row's Save button below the fold in the default 800x600
        // test viewport — settings_tab.dart wraps everything in a
        // SingleChildScrollView, so scroll it into view before tapping
        // rather than tapping blind (a plain tap at an off-screen offset
        // silently no-ops instead of registering).
        await tester.ensureVisible(saveButton);
        await tester.pumpAndSettle();
        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(await db.getVaultHubFolder(), equals('idea'));
      },
    );

    testWidgets(
      'saving an empty value falls back to "project" rather than persisting blank',
      (tester) async {
        final container = await _pump(tester);
        final db = container.read(appDatabaseProvider);

        final fieldFinder = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'project',
        );
        final rowFinder = find.ancestor(
          of: fieldFinder,
          matching: find.byType(Row),
        );
        final saveButton = find.descendant(
          of: rowFinder,
          matching: find.widgetWithText(TextButton, 'Speichern'),
        );

        await tester.enterText(fieldFinder, '');
        await tester.ensureVisible(saveButton);
        await tester.pumpAndSettle();
        await tester.tap(saveButton);
        await tester.pumpAndSettle();

        expect(await db.getVaultHubFolder(), equals('project'));
      },
    );
  });
}
