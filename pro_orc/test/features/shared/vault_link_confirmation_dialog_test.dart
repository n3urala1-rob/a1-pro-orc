import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/features/shared/vault_link_confirmation_dialog.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/vault_link_statuses_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

const _pendingHighMatch = VaultLinkStatus(
  folderId: 'niimo',
  displayName: 'niimo-mobile',
  kind: VaultLinkKind.pendingSuggestion,
  hubSlug: 'niimo-mobile-app',
  confidence: 0.87,
);

const _noMatch = VaultLinkStatus(
  folderId: 'pro-orc-experimental',
  displayName: 'pro-orc-experimental',
  kind: VaultLinkKind.willAutoCreate,
);

Future<AppDatabase> _pumpDialog(
  WidgetTester tester, {
  required List<VaultLinkStatus> pending,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        vaultPendingLinksProvider.overrideWithValue(pending),
        vaultLinkStatusesProvider.overrideWith((ref) async => pending),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: const Scaffold(body: VaultLinkConfirmationDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

void main() {
  group('VaultLinkConfirmationDialog', () {
    testWidgets(
      'renders one row per pending project with the fuzzy-suggested hub name',
      (tester) async {
        await _pumpDialog(tester, pending: [_pendingHighMatch]);

        expect(find.text('niimo-mobile'), findsOneWidget);
        expect(find.textContaining('niimo-mobile-app.md'), findsOneWidget);
        expect(find.textContaining('87%'), findsOneWidget);
      },
    );

    testWidgets(
      'a no-candidate project renders the exact "wird neu angelegt: project/<slug>.md" string',
      (tester) async {
        await _pumpDialog(tester, pending: [_noMatch]);

        expect(
          find.text('wird neu angelegt: project/pro-orc-experimental.md'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping Accept then the batch-confirm control calls setVaultHubSlug with the expected slug',
      (tester) async {
        final db = await _pumpDialog(tester, pending: [_pendingHighMatch]);

        // Accept the row (check icon button).
        await tester.tap(find.byIcon(LucideIcons.check100));
        await tester.pump();

        // Batch-confirm footer button.
        await tester.tap(find.textContaining('Alle 1 bestätigen'));
        await tester.pumpAndSettle();

        expect(await db.getVaultHubSlug('niimo'), equals('niimo-mobile-app'));
      },
    );

    testWidgets(
      'tapping Reject leaves that project unchanged while other accepted rows still commit',
      (tester) async {
        const secondCandidate = VaultLinkStatus(
          folderId: 'n3ural',
          displayName: 'n3ural-platform',
          kind: VaultLinkKind.pendingSuggestion,
          hubSlug: 'n3ural-platform',
          confidence: 0.94,
        );

        final db = await _pumpDialog(
          tester,
          pending: [_pendingHighMatch, secondCandidate],
        );

        // Accept both rows first (two check icons visible).
        final checkButtons = find.byIcon(LucideIcons.check100);
        expect(checkButtons, findsNWidgets(2));
        await tester.tap(checkButtons.first);
        await tester.pump();
        await tester.tap(find.byIcon(LucideIcons.check100).last);
        await tester.pump();

        // Reject the first row again (tapping the now-accepted check icon
        // toggles it back off).
        await tester.tap(find.byIcon(LucideIcons.check100).first);
        await tester.pump();

        await tester.tap(find.textContaining('Alle 2 bestätigen'));
        await tester.pumpAndSettle();

        expect(await db.getVaultHubSlug('niimo'), isNull);
        expect(await db.getVaultHubSlug('n3ural'), equals('n3ural-platform'));
      },
    );
  });
}
