import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/services/process_runner.dart';
import 'package:pro_orc/data/services/watcher_telemetry.dart';
import 'package:pro_orc/providers/watcher_telemetry_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Settings-tab diagnostics section for [WatcherTelemetry] and
/// [ProcessSemaphore.peakRunning] (process-storm round 3, WP3).
///
/// Round 2's verification was mechanism-level only; the round-3 report's
/// Confidence section explicitly notes the diagnosis could not be fully
/// proven or disproven at runtime — attribution to pro_orc stayed
/// medium-low (the freeze itself was never reproduced). This section is not
/// a nice-to-have: it is the runtime-verification story round 2 was
/// missing. It shows the watcher's tracked-entity count and construction
/// time, AND whether the process semaphore's concurrency cap was ever
/// actually approached — so the next incident of this class produces
/// numbers a person can read directly, instead of requiring another
/// multi-hour probe-based investigation.
///
/// [globalProcessSemaphore.peakRunning] changes continuously as processes
/// run throughout the app's lifetime (unlike [WatcherTelemetry], which is
/// published once per watcher construction), so its row is refreshed via an
/// explicit "Aktualisieren" button rather than a live poll — deliberately
/// simple: this is a diagnostics panel someone checks after/during an
/// incident, not a live dashboard, and a `Timer.periodic` inside a settings
/// section adds test-harness complexity (pending-timer teardown) for a
/// value nobody needs updating in real time.
class WatcherTelemetrySection extends ConsumerStatefulWidget {
  const WatcherTelemetrySection({super.key});

  @override
  ConsumerState<WatcherTelemetrySection> createState() =>
      _WatcherTelemetrySectionState();
}

class _WatcherTelemetrySectionState
    extends ConsumerState<WatcherTelemetrySection> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final telemetry = ref.watch(watcherTelemetryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.activity, color: colors.cyan, size: 18),
            const SizedBox(width: 8),
            Text(
              'Watcher-Diagnose',
              style: TextStyle(
                color: colors.textPri,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: 'Prozess-Schranke-Wert aktualisieren',
              child: InkWell(
                onTap: () => setState(() {}),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.refreshCw,
                    color: colors.textDim,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Technische Kennzahlen des Datei-Beobachters und der '
          'Prozess-Schranke — hilft, eine künftige Regression dieser Art '
          'an Zahlen statt an Vermutungen zu erkennen.',
          style: TextStyle(color: colors.textDim, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (telemetry == null)
          Text(
            'Noch keine Daten — der Watcher wird beim Start initialisiert.',
            style: TextStyle(color: colors.textSec, fontSize: 12),
          )
        else
          _TelemetryRows(telemetry: telemetry, colors: colors),
        const SizedBox(height: 4),
        _ProcessSemaphoreRow(colors: colors),
      ],
    );
  }
}

class _TelemetryRows extends StatelessWidget {
  const _TelemetryRows({required this.telemetry, required this.colors});

  final WatcherTelemetry telemetry;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(
          'Beobachtete Wurzelverzeichnisse',
          '${telemetry.watchedRootCount}',
        ),
        _row('Aufbauzeit', '${telemetry.constructionTime.inMilliseconds} ms'),
        _row('Rohe Ereignisse (vor Filter)', '${telemetry.rawEventCount}'),
        _row(
          'Weitergeleitete Ereignisse (nach Filter)',
          '${telemetry.emittedEventCount}',
        ),
      ],
    );
  }

  Widget _row(String label, String value) =>
      _TelemetryRow(label: label, value: value, colors: colors);
}

/// Shows [ProcessSemaphore.peakRunning] against [ProcessSemaphore.maxConcurrent]
/// for [globalProcessSemaphore] — the highest number of child processes
/// (git, gh, vercel, ...) ever running concurrently since app start, and
/// whether that ever reached the structural cap. Falk's diagnosis (round 3)
/// could not confirm or rule out process load as a contributing factor;
/// this is the number that answers it for the NEXT incident.
class _ProcessSemaphoreRow extends StatelessWidget {
  const _ProcessSemaphoreRow({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final peak = globalProcessSemaphore.peakRunning;
    final max = globalProcessSemaphore.maxConcurrent;
    final saturated = peak >= max;

    return _TelemetryRow(
      label: 'Prozess-Schranke — Höchststand',
      value: '$peak / $max${saturated ? ' (ausgereizt)' : ''}',
      colors: colors,
      valueColor: saturated ? colors.amber : null,
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  final String label;
  final String value;
  final AppColors colors;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.textSec, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? colors.textPri,
              fontSize: 12,
              fontFamily: 'SF Mono',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
