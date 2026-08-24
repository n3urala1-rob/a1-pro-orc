import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/services/process_runner.dart';
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

    testWidgets('shows the process-semaphore peak-concurrency row against '
        'globalProcessSemaphore.maxConcurrent (team-lead follow-up, '
        'process-storm round 3 WP3)', (tester) async {
      await _pumpSection(tester, telemetry: WatcherTelemetry());

      expect(find.text('Prozess-Schranke — Höchststand'), findsOneWidget);
      expect(
        find.textContaining(
          '${globalProcessSemaphore.peakRunning} / '
          '${globalProcessSemaphore.maxConcurrent}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('peak-concurrency row reflects a real semaphore peak after '
        'concurrent work has run, once refreshed via the "Aktualisieren" '
        'button', (tester) async {
      // Drives the real global semaphore's peakRunning tracking directly
      // via ProcessSemaphore.run — not a provider override, since it's a
      // process-wide singleton (see process_runner.dart) — WITHOUT
      // spawning a real OS process. testWidgets bodies run inside
      // TestWidgetsFlutterBinding's controlled async environment, which
      // does not reliably interleave with real Process.start I/O; real
      // subprocess-spawn coverage for runProcessWithTimeout already lives
      // in process_runner_test.dart (a plain, non-widget test). Here only
      // the display logic (does the row reflect ProcessSemaphore's
      // tracked peak) is under test.
      await Future.wait([
        globalProcessSemaphore.run(() => Future<void>.value()),
        globalProcessSemaphore.run(() => Future<void>.value()),
      ]);
      expect(
        globalProcessSemaphore.peakRunning,
        greaterThan(0),
        reason:
            'Precondition: the two concurrent runs above must have '
            'registered a nonzero peak.',
      );

      await _pumpSection(tester, telemetry: WatcherTelemetry());

      // The row already reads the live value on build (no stale caching),
      // so it should already show the peak — the refresh button exists
      // for the case where the peak changes WHILE the panel stays open.
      expect(
        find.textContaining(
          '${globalProcessSemaphore.peakRunning} / '
          '${globalProcessSemaphore.maxConcurrent}',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(LucideIcons.refreshCw));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          '${globalProcessSemaphore.peakRunning} / '
          '${globalProcessSemaphore.maxConcurrent}',
        ),
        findsOneWidget,
      );
    });
  });
}
