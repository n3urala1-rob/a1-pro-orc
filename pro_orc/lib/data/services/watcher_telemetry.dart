/// Lightweight, in-memory diagnostics for [WatcherService] construction and
/// runtime behavior (process-storm round 3, WP3).
///
/// Round 2's verification was mechanism-level only ("the fix works because
/// we reasoned about the code"); the round-3 report's Confidence section
/// explicitly flags that Falk could not prove or disprove pro_orc's
/// contribution to the observed shell freezes. This class exists so the
/// *next* incident produces numbers instead of another pattern-match: it
/// captures how long constructing all watchers took and how many raw
/// (pre-filter) filesystem events have been observed, without holding a
/// per-entity tree itself (that retention is exactly what round 3 removed).
class WatcherTelemetry {
  /// Wall-clock time to construct every underlying native watch subscription
  /// across all watched roots (see [WatcherService._init]). With the
  /// `Directory.watch(recursive: true)`-based engine this is expected to be
  /// low single-digit milliseconds per root — the 2026-08-20 baseline
  /// (`RecursiveDirectoryWatcher` + `listSync()` tree) measured ~10.7s total
  /// across the four production roots.
  Duration constructionTime = Duration.zero;

  /// Number of directories/roots currently being watched.
  int watchedRootCount = 0;

  /// Count of raw native filesystem events received since construction,
  /// BEFORE [isNoiseEvent] filtering and before debouncing. High growth here
  /// relative to [emittedEventCount] indicates a noisy root (e.g. a
  /// `node_modules` still inside a watched tree) — useful for diagnosing a
  /// future regression of this same class.
  int rawEventCount = 0;

  /// Count of events that passed [isNoiseEvent] filtering and were forwarded
  /// downstream (pre-debounce).
  int emittedEventCount = 0;

  /// Best-effort process RSS in bytes at the moment telemetry was last
  /// snapshotted, via [ProcessInfo.currentRss] (see [snapshotRss]). Null
  /// until the first snapshot.
  int? lastRssBytes;
}
