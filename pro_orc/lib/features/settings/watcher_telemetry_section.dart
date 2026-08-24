import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/services/watcher_telemetry.dart';
import 'package:pro_orc/providers/watcher_telemetry_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Settings-tab diagnostics section for [WatcherTelemetry] (process-storm
/// round 3, WP3).
///
/// Round 2's verification was mechanism-level only; the round-3 report's
/// Confidence section explicitly notes the diagnosis could not be fully
/// proven or disproven at runtime. This section exists so the next
/// incident of this class produces numbers a person can read directly,
/// instead of requiring another multi-hour probe-based investigation.
class WatcherTelemetrySection extends ConsumerWidget {
  const WatcherTelemetrySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Technische Kennzahlen des Datei-Beobachters — hilft, eine '
          'künftige Regression dieser Art an Zahlen statt an Vermutungen '
          'zu erkennen.',
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

  Widget _row(String label, String value) {
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
              color: colors.textPri,
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
