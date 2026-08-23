import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/features/settings/vault_link_card.dart';
import 'package:pro_orc/providers/vault_link_statuses_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required List<VaultLinkStatus> statuses,
}) async {
  final counts = VaultLinkCounts(
    linked: statuses.where((s) => s.kind == VaultLinkKind.linked).length,
    total: statuses.length,
  );
  final pending = statuses
      .where((s) => s.kind != VaultLinkKind.linked)
      .toList();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultLinkStatusesProvider.overrideWith((ref) async => statuses),
        vaultLinkCountsProvider.overrideWithValue(counts),
        vaultPendingLinksProvider.overrideWithValue(pending),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: const Scaffold(body: VaultLinkCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('VaultLinkCard', () {
    testWidgets(
      'collapsed state shows the "N von M verknüpft" summary and progress bar',
      (tester) async {
        await _pumpCard(
          tester,
          statuses: [
            const VaultLinkStatus(
              folderId: 'pro-orc',
              displayName: 'Pro Orc',
              kind: VaultLinkKind.linked,
              hubSlug: 'pro-orc',
            ),
            const VaultLinkStatus(
              folderId: 'n3ural',
              displayName: 'N3URAL',
              kind: VaultLinkKind.linked,
              hubSlug: 'n3ural',
            ),
            const VaultLinkStatus(
              folderId: 'niimo',
              displayName: 'Niimo',
              kind: VaultLinkKind.pendingSuggestion,
              hubSlug: 'niimo-app',
              confidence: 0.87,
            ),
            const VaultLinkStatus(
              folderId: 'wtv',
              displayName: 'WTV',
              kind: VaultLinkKind.willAutoCreate,
            ),
            const VaultLinkStatus(
              folderId: 'a1-office',
              displayName: 'A1 Office',
              kind: VaultLinkKind.willAutoCreate,
            ),
          ],
        );

        final summaryFinder = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('von'),
        );
        expect(summaryFinder, findsOneWidget);
        final plainText = tester
            .widget<RichText>(summaryFinder)
            .text
            .toPlainText();
        expect(plainText, contains('2 von 5'));
        expect(plainText, contains('Projekten verknüpft'));

        expect(find.byType(FractionallySizedBox), findsOneWidget);

        final box = tester.widget<FractionallySizedBox>(
          find.byType(FractionallySizedBox),
        );
        expect(box.widthFactor, closeTo(2 / 5, 0.001));
      },
    );

    testWidgets(
      'tapping the card expands it and reveals the per-project list',
      (tester) async {
        await _pumpCard(
          tester,
          statuses: [
            const VaultLinkStatus(
              folderId: 'pro-orc',
              displayName: 'Pro Orc',
              kind: VaultLinkKind.linked,
              hubSlug: 'pro-orc',
            ),
          ],
        );

        expect(find.text('Pro Orc'), findsNothing);

        await tester.tap(find.byType(VaultLinkCard));
        await tester.pumpAndSettle();

        expect(find.text('Pro Orc'), findsOneWidget);
      },
    );

    testWidgets(
      'the confirm-links entry point is present when at least one project is pending',
      (tester) async {
        await _pumpCard(
          tester,
          statuses: [
            const VaultLinkStatus(
              folderId: 'niimo',
              displayName: 'Niimo',
              kind: VaultLinkKind.pendingSuggestion,
              hubSlug: 'niimo-app',
              confidence: 0.87,
            ),
          ],
        );

        await tester.tap(find.byType(VaultLinkCard));
        await tester.pumpAndSettle();

        expect(find.textContaining('bestätigen'), findsOneWidget);
      },
    );

    testWidgets(
      'the confirm-links entry point is hidden when all projects are linked',
      (tester) async {
        await _pumpCard(
          tester,
          statuses: [
            const VaultLinkStatus(
              folderId: 'pro-orc',
              displayName: 'Pro Orc',
              kind: VaultLinkKind.linked,
              hubSlug: 'pro-orc',
            ),
          ],
        );

        await tester.tap(find.byType(VaultLinkCard));
        await tester.pumpAndSettle();

        expect(find.textContaining('bestätigen'), findsNothing);
      },
    );
  });
}
