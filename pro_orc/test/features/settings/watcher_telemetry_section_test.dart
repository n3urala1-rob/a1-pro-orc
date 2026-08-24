import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pro_orc/data/services/watcher_telemetry.dart';
import 'package:pro_orc/features/settings/watcher_telemetry_section.dart';
import 'package:pro_orc/providers/watcher_telemetry_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

Future<void> _pumpSection(
  WidgetTester tester, {
  WatcherTelemetry? telemetry,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        watcherTelemetryProvider.overrideWith(() {
          final notifier = WatcherTelemetryNotifier();
          if (telemetry != null) {
            Future.microtask(() => notifier.publish(telemetry));
          }
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: const Scaffold(body: WatcherTelemetrySection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WatcherTelemetrySection', () {
    testWidgets(
      'shows a placeholder before the watcher has published telemetry',
      (tester) async {
        await _pumpSection(tester, telemetry: null);

        expect(find.textContaining('Noch keine Daten'), findsOneWidget);
      },
    );

    testWidgets('shows root count, construction time, and event counters once '
        'telemetry is published', (tester) async {
      final telemetry = WatcherTelemetry()
        ..watchedRootCount = 4
        ..constructionTime = const Duration(milliseconds: 12)
        ..rawEventCount = 30
        ..emittedEventCount = 2;

      await _pumpSection(tester, telemetry: telemetry);

      expect(find.text('4'), findsOneWidget);
      expect(find.text('12 ms'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows the section title and description', (tester) async {
      await _pumpSection(tester, telemetry: WatcherTelemetry());

      expect(find.text('Watcher-Diagnose'), findsOneWidget);
      expect(find.textContaining('Technische Kennzahlen'), findsOneWidget);
    });
  });
}
