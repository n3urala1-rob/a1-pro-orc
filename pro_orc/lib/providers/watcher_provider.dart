import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'package:pro_orc/data/services/vault_root_resolver.dart';
import 'package:pro_orc/data/services/watcher_service.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/watcher_telemetry_provider.dart';

/// File watcher stream — emits debounced WatchEvents for all scan directories
/// plus the Claude projects directory (for memory status changes).
/// keepAlive: never disposed (locked decision from CONTEXT.md).
///
/// [WatcherService] construction is synchronous and cheap (native
/// `Directory.watch(recursive: true)` subscriptions, no upfront directory
/// walk — see watcher_service.dart's class doc for the process-storm round 3
/// rewrite), so this no longer needs to run off the main isolate the way the
/// pre-round-3 `RecursiveDirectoryWatcher`-based implementation did (measured
/// ~10.7s blocking `listSync()` walk across the production roots).
final watcherProvider = StreamProvider<WatchEvent>((ref) async* {
  ref.keepAlive();

  // Read scan dirs from DB config
  final db = ref.read(appDatabaseProvider);
  final scanDirs = await db.getScanDirs();

  // Also watch Claude projects dir for memory changes (rem-sleep updates)
  final claudeProjectsDir = p.join(
    Platform.environment['HOME'] ?? '/tmp',
    '.claude',
    'projects',
  );
  final allDirs = [...scanDirs, claudeProjectsDir];

  // Resolved vault root (010-vault-status-writer FR-022a): when configured
  // and it overlaps a scan dir, events under it are dropped as noise so a
  // VaultStatusWriter write never triggers a rescan of that scan dir — see
  // isNoiseEvent's vaultRoot doc for the self-trigger loop this closes.
  // Uses the shared resolveVaultRoot (review round 1, m-7) — this call site
  // previously had its own copy that treated an empty-string DB value as
  // "configured" (only `null` triggered the fallback) while project_scanner
  // and the writer required `.isNotEmpty`, silently disengaging this exact
  // guard whenever vaultDir was set to `''`.
  final vaultRoot = await resolveVaultRoot(db);

  final service = WatcherService.multi(allDirs, vaultRoot: vaultRoot);
  ref.onDispose(service.dispose);

  // WP3 (process-storm round 3): publish construction telemetry so a future
  // regression of this class (unbounded tracked-entity growth, slow
  // construction) is observable instead of requiring another pattern-match
  // postmortem. Logged at startup and surfaced in Settings.
  developer.log(
    'Watcher constructed: ${service.telemetry.watchedRootCount} roots in '
    '${service.telemetry.constructionTime.inMilliseconds}ms',
    name: 'watcher_provider',
  );
  ref.read(watcherTelemetryProvider.notifier).publish(service.telemetry);

  // Forward all events from the service's debounced stream
  yield* service.events;
});
