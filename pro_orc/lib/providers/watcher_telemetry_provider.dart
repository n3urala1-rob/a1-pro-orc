import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pro_orc/data/services/watcher_telemetry.dart';

/// Latest [WatcherTelemetry] snapshot published by [watcherProvider]'s
/// current [WatcherService] instance (process-storm round 3, WP3).
///
/// A plain mutable value holder rather than a [StreamProvider]: telemetry is
/// diagnostic, not reactive data the UI needs to rebuild live for — the
/// Settings tab telemetry section reads the current snapshot on build/refresh
/// rather than subscribing to a stream of updates.
final watcherTelemetryProvider = NotifierProvider<WatcherTelemetryNotifier, WatcherTelemetry?>(
  WatcherTelemetryNotifier.new,
);

class WatcherTelemetryNotifier extends Notifier<WatcherTelemetry?> {
  @override
  WatcherTelemetry? build() => null;

  /// Publishes a new snapshot — called by [watcherProvider] right after its
  /// [WatcherService] is constructed.
  void publish(WatcherTelemetry telemetry) {
    state = telemetry;
  }
}
