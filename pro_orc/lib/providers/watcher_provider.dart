import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'package:pro_orc/data/services/vault_root_resolver.dart';
import 'package:pro_orc/data/services/watcher_service.dart';
import 'package:pro_orc/providers/database_provider.dart';

/// File watcher stream — emits debounced WatchEvents for all scan directories
/// plus the Claude projects directory (for memory status changes).
/// keepAlive: never disposed (locked decision from CONTEXT.md).
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

  // Forward all events from the service's debounced stream
  yield* service.events;
});
