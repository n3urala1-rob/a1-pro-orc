import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:pro_orc/data/db/app_database.dart';

/// Single canonical resolution of the configured Obsidian vault root,
/// shared by every call site that needs it (vault_status_provider.dart,
/// project_scanner.dart, watcher_provider.dart).
///
/// Review round 1 (m-7): these three call sites previously each carried
/// their own copy of "read `getVaultDir()`, fall back to
/// `$HOME/N3URAL-Vault`" and had already drifted — the watcher provider
/// treated an empty-string DB value as "configured" (only `null` triggered
/// the fallback) while the scanner and writer required `.isNotEmpty`, so an
/// empty-string `vaultDir` made the watcher's FR-022 self-trigger guard
/// compare against `''` while the scanner correctly excluded
/// `$HOME/N3URAL-Vault` — silently disengaging the guard. One shared
/// resolver removes the possibility of that drift recurring.
Future<String> resolveVaultRoot(AppDatabase db) async {
  final raw = await db.getVaultDir();
  if (raw != null && raw.isNotEmpty) return p.normalize(raw);
  final home = Platform.environment['HOME'] ?? '/tmp';
  return p.normalize(p.join(home, 'N3URAL-Vault'));
}
