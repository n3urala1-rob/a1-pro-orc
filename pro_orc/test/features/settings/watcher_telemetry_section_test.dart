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

    test(
      'ProcessSemaphore.peakRunning tracks concurrent work correctly — '
      'the tracking mechanism itself, isolated from any widget pumping',
      () async {
        // Review round 1 (Reinhard, nit 4): the previous version of this
        // coverage lived inside a testWidgets body and awaited the
        // process-wide `globalProcessSemaphore` directly — Reinhard
        // observed a ~20% flake rate ("did not complete" after 30s) on a
        // cold machine. A LOCAL ProcessSemaphore instance removes any
        // dependency on TestWidgetsFlutterBinding's controlled async
        // environment entirely (this is a plain `test`, not `testWidgets`)
        // and cannot collide with global state other tests in the same
        // file/run may have touched. The tracking mechanism itself is
        // already covered in depth by process_runner_test.dart's
        // `ProcessSemaphore.peakRunning` group — this is a light
        // reconfirmation local to this file, not a duplicate of that
        // coverage's assertions.
        final semaphore = ProcessSemaphore();

        await Future.wait([
          semaphore.run(() => Future<void>.value()),
          semaphore.run(() => Future<void>.value()),
        ]);

        expect(semaphore.peakRunning, equals(2));
        expect(semaphore.maxConcurrent, equals(6));
      },
    );

    testWidgets(
      'peak-concurrency row displays globalProcessSemaphore.peakRunning / '
      'maxConcurrent, and the "Aktualisieren" button is present and tappable',
      (tester) async {
        // Deliberately does NOT drive globalProcessSemaphore's concurrency
        // here (see the plain `test` above for that coverage, isolated
        // from widget pumping) — this test only asserts the row correctly
        // displays whatever the real singleton's CURRENT value already is,
        // and that the refresh affordance exists and can be tapped without
        // throwing. No process is spawned or awaited on the global here,
        // so there is nothing for this test to race against.
        await _pumpSection(tester, telemetry: WatcherTelemetry());

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
      },
    );
  });
}
