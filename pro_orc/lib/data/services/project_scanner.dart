import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/models/memory_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/project_type.dart';
import 'package:pro_orc/data/services/a1_reader.dart';
import 'package:pro_orc/data/services/git_reader.dart';
import 'package:pro_orc/data/services/memory_reader.dart';
import 'package:pro_orc/data/services/project_importer_service.dart';
import 'package:pro_orc/data/services/project_metadata_reader.dart';
import 'package:pro_orc/data/services/vault_root_resolver.dart';

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Thrown when the configured scan directory does not exist.
class ScanDirectoryNotFoundError implements Exception {
  final String path;
  final String message;

  const ScanDirectoryNotFoundError({required this.path, required this.message});

  @override
  String toString() => 'ScanDirectoryNotFoundError: $message (path: $path)';
}

// ---------------------------------------------------------------------------
// Scan result cache (metadata / git / memory / used-agents / a1)
// ---------------------------------------------------------------------------

/// Caches arbitrary per-project scan results keyed by a "signature" mtime.
///
/// A single FS event previously caused [ProjectScanner.scanAll] to re-run git,
/// memory, and agent-usage scans for EVERY project. This cache lets each of
/// those scans be skipped for projects whose relevant source files have not
/// changed since the last scan, so one changed project no longer pays for a
/// rescan of all the others.
class _ScanResultCache<T> {
  /// Map from "path:signature" → boxed cached result (boxing distinguishes a
  /// cached `null` value from a cache miss).
  final Map<String, _Box<T>> _cache = {};

  String _key(String projectPath, DateTime signature) =>
      '$projectPath:${signature.microsecondsSinceEpoch}';

  /// Returns the cached result for [projectPath] if [signature] matches the
  /// signature it was stored under, boxed so a cached `null` is distinguishable
  /// from a cache miss. Returns null on cache miss.
  _Box<T>? getBoxed(String projectPath, DateTime? signature) {
    if (signature == null) return null;
    return _cache[_key(projectPath, signature)];
  }

  /// Stores [result] for [projectPath] under [signature].
  void put(String projectPath, DateTime signature, T result) {
    _cache[_key(projectPath, signature)] = _Box(result);
  }

  /// Computes [sig] once, returns the cached result if it matches the stored
  /// signature, otherwise runs [compute] and caches the result (when [sig]
  /// resolved to a non-null signature). Collapses the
  /// getBoxed→hit?→compute→put shape shared by every `_read*WithCache`
  /// method in [ProjectScanner].
  Future<T> getOrCompute(
    String projectPath,
    Future<DateTime?> Function() sig,
    Future<T> Function() compute,
  ) async {
    final signature = await sig();
    final cached = getBoxed(projectPath, signature);
    if (cached != null) return cached.value;

    final result = await compute();
    if (signature != null) {
      put(projectPath, signature, result);
    }
    return result;
  }
}

/// Simple box so a cached `null` value is distinguishable from "not cached".
class _Box<T> {
  final T value;
  const _Box(this.value);
}

/// Returns the latest mtime of .planning/PROJECT.md, PROJECT.md, or
/// CLAUDE.md in [projectPath], or null if none exist.
Future<DateTime?> _metadataMtime(String projectPath) async {
  DateTime? latest;
  for (final name in const [
    '.planning/PROJECT.md',
    'PROJECT.md',
    'CLAUDE.md',
  ]) {
    final filePath = p.join(projectPath, name);
    try {
      final stat = await FileStat.stat(filePath);
      if (stat.type == FileSystemEntityType.notFound) continue;
      if (latest == null || stat.modified.isAfter(latest)) {
        latest = stat.modified;
      }
    } catch (e) {
      developer.log('Failed to stat $filePath: $e', name: 'project_scanner');
    }
  }
  return latest;
}

/// Computes a combined "signature" mtime for a project's git state.
///
/// Uses `.git/HEAD` (changes on checkout/commit) and `.git/refs/heads` — the
/// directory mtime changes whenever a branch ref is updated (new commit).
/// Returns null if the project is not a git repo (cache is then always missed,
/// which is correct: [readGitData] itself handles the non-git case cheaply).
Future<DateTime?> _gitSignature(String projectPath) async {
  final headPath = p.join(projectPath, '.git', 'HEAD');
  try {
    final stat = await FileStat.stat(headPath);
    if (stat.type == FileSystemEntityType.notFound) return null;

    var latest = stat.modified;
    final refsHeadsDir = Directory(
      p.join(projectPath, '.git', 'refs', 'heads'),
    );
    if (await refsHeadsDir.exists()) {
      final refsStat = await refsHeadsDir.stat();
      if (refsStat.modified.isAfter(latest)) latest = refsStat.modified;
    }
    return latest;
  } catch (e) {
    developer.log(
      'Failed to compute git signature for $projectPath: $e',
      name: 'project_scanner',
    );
    return null;
  }
}

/// Computes a signature mtime for a project's `.planning/phases` directory,
/// used to detect changes relevant to the used-agents scan.
Future<DateTime?> _phasesSignature(String projectPath) async {
  final phasesDir = Directory(p.join(projectPath, '.planning', 'phases'));
  try {
    if (!await phasesDir.exists()) return null;
    return (await phasesDir.stat()).modified;
  } catch (e) {
    developer.log(
      'Failed to compute phases signature for $projectPath: $e',
      name: 'project_scanner',
    );
    return null;
  }
}

/// Computes a signature mtime for a project's `.a1` directory, combining the
/// `.a1/phases` dir mtime and `.a1/roadmap.md` mtime, used to detect changes
/// relevant to the a1 roadmap/phase scan. Null when the project has no `.a1/`.
Future<DateTime?> _a1Signature(String projectPath) async {
  final a1Dir = Directory(p.join(projectPath, '.a1'));
  try {
    if (!await a1Dir.exists()) return null;
    var latest = (await a1Dir.stat()).modified;

    final phasesDir = Directory(p.join(a1Dir.path, 'phases'));
    if (await phasesDir.exists()) {
      // Include each PLAN.md mtime so a checkbox toggle (which changes the file
      // but not the phases dir) still invalidates the cache.
      await for (final entity in phasesDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (p.basename(entity.path) != 'PLAN.md') continue;
        final s = (await entity.stat()).modified;
        if (s.isAfter(latest)) latest = s;
      }
    }
    final roadmap = File(p.join(a1Dir.path, 'roadmap.md'));
    if (await roadmap.exists()) {
      final s = (await roadmap.stat()).modified;
      if (s.isAfter(latest)) latest = s;
    }
    return latest;
  } catch (e) {
    developer.log(
      'Failed to compute a1 signature for $projectPath: $e',
      name: 'project_scanner',
    );
    return null;
  }
}

// ---------------------------------------------------------------------------
// ProjectScanner
// ---------------------------------------------------------------------------

/// Top-level orchestration service for the Phase 7 data layer.
///
/// [scanAll] scans a flat directory, reads project metadata + git metadata,
/// resolves project types from the DB, and returns a complete list of
/// [ProjectModel] objects sorted by [ProjectModel.displayName].
class ProjectScanner {
  final AppDatabase _db;
  final _ScanResultCache<ProjectMetadata> _metadataCache =
      _ScanResultCache<ProjectMetadata>();
  final _ScanResultCache<GitData> _gitCache = _ScanResultCache<GitData>();
  final _ScanResultCache<MemoryData> _memoryCache =
      _ScanResultCache<MemoryData>();
  final _ScanResultCache<List<String>?> _usedAgentsCache =
      _ScanResultCache<List<String>?>();
  final _ScanResultCache<A1Data> _a1Cache = _ScanResultCache<A1Data>();
  final A1Reader _a1Reader = A1Reader();

  /// Overrides `$HOME/.claude` for memory lookups — used by tests to point
  /// at a temp directory instead of the real Claude home.
  final String? _claudeHomeDirOverride;

  ProjectScanner(this._db, {String? claudeHomeDirOverride})
    : _claudeHomeDirOverride = claudeHomeDirOverride;

  /// Scans the configured (or overridden) scan directory and returns a
  /// [List<ProjectModel>] sorted by displayName.
  ///
  /// If [scanDirOverride] is provided it takes precedence over the DB config
  /// value (useful for unit tests).
  ///
  /// Throws [ScanDirectoryNotFoundError] when the scan directory does not
  /// exist or is configured as an empty string.
  Future<List<ProjectModel>> scanAll({String? scanDirOverride}) async {
    // --- 1. Resolve scan directories ---
    final scanDirs = scanDirOverride != null
        ? [scanDirOverride]
        : await _db.getScanDirs();

    if (scanDirs.isEmpty) {
      throw ScanDirectoryNotFoundError(
        path: '',
        message: 'No scan directories configured',
      );
    }

    // Read git binary + ignore patterns from DB regardless of whether
    // scanDirs came from an override (used by tests) or DB config.
    String gitBinary = 'git';
    List<String> ignorePatterns = [];
    try {
      final config = await _db.getConfig();
      gitBinary = config.gitBinaryPath;
      ignorePatterns = _parseIgnoreList(config.ignoreListJson);
    } catch (e) {
      // If DB read fails, proceed with defaults (git binary + empty ignore list)
      developer.log(
        'Failed to read DB config for git binary/ignore list: $e',
        name: 'project_scanner',
      );
    }

    // --- 2. List project directories from all scan dirs ---
    final rawProjectPaths = <String>[];
    for (final scanDir in scanDirs) {
      try {
        final paths = await _listProjectPaths(scanDir, ignorePatterns);
        rawProjectPaths.addAll(paths);
      } on ScanDirectoryNotFoundError {
        // When using a single override, propagate the error.
        // For multi-dir configs, skip non-existent dirs gracefully.
        if (scanDirOverride != null) rethrow;
      }
    }

    // Vault-root exclusion (010-vault-status-writer FR-022b): the vault
    // MUST NOT be listed as a project even when it happens to sit inside
    // (or equal) a configured scan dir — it is a writer target
    // (VaultStatusWriter), not a scannable project. Resolved the same way
    // watcher_provider.dart resolves it for isNoiseEvent's vaultRoot param,
    // so both halves of FR-022's guard agree on what "the vault" means.
    final vaultRoot = await resolveVaultRoot(_db);
    final projectPaths = rawProjectPaths
        .where((path) => !_isUnderVaultRoot(path, vaultRoot))
        .toList();

    if (projectPaths.isEmpty) {
      return [];
    }

    // --- 3. Read project metadata (displayName/description) for all projects (with cache) ---
    final metadataResults = await Future.wait(
      projectPaths.map((path) => _readMetadataWithCache(path)),
    );

    // --- 4. Read git data for all projects (with cache) ---
    final gitResults = await Future.wait(
      projectPaths.map((path) => _readGitWithCache(path, gitBinary)),
    );

    // --- 4b. Read memory data for all projects (with cache) ---
    final memoryResults = await Future.wait(
      projectPaths.map((path) => _readMemoryWithCache(path)),
    );

    // --- 4c. Read a1 roadmap/phase data for all projects (with cache) ---
    final a1Results = await Future.wait(
      projectPaths.map((path) => _readA1WithCache(path)),
    );

    // --- 5. Assemble ProjectModel for each project ---
    final models = <ProjectModel>[];

    for (int i = 0; i < projectPaths.length; i++) {
      final path = projectPaths[i];
      final folderId = p.basename(path);
      final metadata = metadataResults[i];
      final gitData = gitResults[i];
      final memoryData = memoryResults[i];
      final a1Data = a1Results[i];

      // Resolve project type: DB override > content heuristic
      final settings = await _db.getProjectSettings(folderId);
      final projectType =
          ProjectType.fromString(settings?.projectType) ??
          await _inferType(path);

      // Nullify empty git data
      final git = (gitData.isEmpty) ? null : gitData;

      // Compute stale
      final isStale = await _computeStale(path, git?.lastCommitDate);

      // Extract used agents from .planning/ VERIFICATION.md files (with cache)
      final usedAgents = await _extractUsedAgentsWithCache(path);

      // Scan for .md files
      final mdFiles = await _scanMdFiles(path);

      // Resolve displayName: DB override > PROJECT.md/CLAUDE.md H1 > folderId
      final overrideName = settings?.displayName?.trim();
      final resolvedName = (overrideName != null && overrideName.isNotEmpty)
          ? overrideName
          : (metadata.displayName ?? folderId);

      models.add(
        ProjectModel(
          folderId: folderId,
          displayName: resolvedName,
          path: path,
          projectType: projectType,
          description: metadata.description,
          a1: a1Data.isEmpty ? null : a1Data,
          git: git,
          memory: memoryData.hasMemory ? memoryData : null,
          isStale: isStale,
          usedAgents: usedAgents,
          mdFiles: mdFiles,
        ),
      );
    }

    // --- 6. Sort by displayName ---
    models.sort((a, b) => a.displayName.compareTo(b.displayName));

    return models;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Delegates to shared [inferProjectType] from project_importer_service.
  Future<ProjectType> _inferType(String projectPath) =>
      inferProjectType(projectPath);

  /// Lists all direct child directories of [scanDir], filtering out hidden
  /// directories and those matching [ignorePatterns].
  ///
  /// Throws [ScanDirectoryNotFoundError] when [scanDir] does not exist.
  Future<List<String>> _listProjectPaths(
    String scanDir,
    List<String> ignorePatterns,
  ) async {
    final dir = Directory(scanDir);
    if (!await dir.exists()) {
      throw ScanDirectoryNotFoundError(
        path: scanDir,
        message: 'Scan directory does not exist: $scanDir',
      );
    }

    final paths = <String>[];

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! Directory) continue;

      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (_matchesAnyIgnorePattern(name, ignorePatterns)) continue;

      // Check if this directory is itself a project (has .planning/ or .git/)
      final isProject = await _isProjectDir(entity.path);
      if (isProject) {
        paths.add(entity.path);
      } else {
        // Not a project — scan its children one level deeper
        await for (final child in entity.list(
          recursive: false,
          followLinks: false,
        )) {
          if (child is! Directory) continue;
          final childName = p.basename(child.path);
          if (childName.startsWith('.')) continue;
          if (_matchesAnyIgnorePattern(childName, ignorePatterns)) continue;
          paths.add(child.path);
        }
      }
    }

    return paths;
  }

  /// Returns true if [path] is the vault root itself or nested inside it.
  bool _isUnderVaultRoot(String path, String vaultRoot) {
    final normalizedPath = p.normalize(path);
    final normalizedRoot = p.normalize(vaultRoot);
    if (normalizedPath == normalizedRoot) return true;
    final rootWithSep = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    return normalizedPath.startsWith(rootWithSep);
  }

  /// Returns true if [path] looks like a project directory
  /// (has .planning/, .git/, or CLAUDE.md).
  Future<bool> _isProjectDir(String path) async {
    final planning = Directory(p.join(path, '.planning'));
    final git = Directory(p.join(path, '.git'));
    final claudeMd = File(p.join(path, 'CLAUDE.md'));
    return await planning.exists() ||
        await git.exists() ||
        await claudeMd.exists();
  }

  /// Returns true if [name] matches any of the [patterns].
  ///
  /// Pattern formats:
  /// - Exact match: `node_modules` matches `node_modules`
  /// - Suffix wildcard: `build*` matches any name starting with `build`
  bool _matchesAnyIgnorePattern(String name, List<String> patterns) {
    for (final pattern in patterns) {
      if (pattern.endsWith('*')) {
        // Prefix match
        final prefix = pattern.substring(0, pattern.length - 1);
        if (name.startsWith(prefix)) return true;
      } else {
        // Exact match
        if (name == pattern) return true;
      }
    }
    return false;
  }

  /// Reads project metadata (displayName/description) using the cache to
  /// avoid re-parsing unchanged files.
  Future<ProjectMetadata> _readMetadataWithCache(String projectPath) =>
      _metadataCache.getOrCompute(
        projectPath,
        () => _metadataMtime(projectPath),
        () => readProjectMetadata(projectPath),
      );

  /// Reads git data using the cache to avoid spawning a git subprocess for
  /// projects whose `.git/HEAD`/refs have not changed since the last scan.
  Future<GitData> _readGitWithCache(String projectPath, String gitBinary) =>
      _gitCache.getOrCompute(
        projectPath,
        () => _gitSignature(projectPath),
        () => readGitData(projectPath, gitBinary: gitBinary),
      );

  /// Reads memory data using the cache to avoid the fuzzy-match directory
  /// scan under `~/.claude/projects/` for projects whose memory has not
  /// changed since the last scan.
  ///
  /// Signature is the mtime of the actual MEMORY.md file (via
  /// [memoryFileSignature]) — NOT the project directory's own mtime. The
  /// project directory does not change when rem-sleep consolidates a new
  /// MEMORY.md (that file lives under `~/.claude/projects/<encoded>/memory/`,
  /// a completely different directory), so using the project dir's mtime as
  /// the signature meant the cache never invalidated after a real memory
  /// update — the indicator stayed stale until an unrelated project file
  /// changed. (Fixed per code review MAJOR finding.)
  Future<MemoryData> _readMemoryWithCache(String projectPath) =>
      _memoryCache.getOrCompute(
        projectPath,
        () => memoryFileSignature(
          projectPath,
          claudeHomeDirOverride: _claudeHomeDirOverride,
        ),
        () => readMemoryData(
          projectPath,
          claudeHomeDirOverride: _claudeHomeDirOverride,
        ),
      );

  /// Reads a1 roadmap/phase data using the cache to avoid re-parsing `.a1/`
  /// for projects whose roadmap/phases have not changed since the last scan.
  Future<A1Data> _readA1WithCache(String projectPath) => _a1Cache.getOrCompute(
    projectPath,
    () => _a1Signature(projectPath),
    () => _a1Reader.read(projectPath),
  );

  /// Extracts used agents using the cache to avoid re-walking
  /// `.planning/phases/` recursively for projects whose phases directory has
  /// not changed since the last scan.
  Future<List<String>?> _extractUsedAgentsWithCache(String projectPath) =>
      _usedAgentsCache.getOrCompute(
        projectPath,
        () => _phasesSignature(projectPath),
        () => _extractUsedAgents(projectPath),
      );

  /// Computes whether a project is stale (>30 days since last activity).
  ///
  /// - Git project: stale if [lastCommitDate] is older than 30 days
  /// - Non-git project with `.planning/STATE.md`: stale if its mtime is
  ///   older than 30 days
  /// - No signal: not stale (benefit of the doubt)
  Future<bool> _computeStale(
    String projectPath,
    DateTime? lastCommitDate,
  ) async {
    const threshold = Duration(days: 30);
    final now = DateTime.now();

    if (lastCommitDate != null) {
      return now.difference(lastCommitDate) > threshold;
    }

    // Non-git: check STATE.md mtime
    final statePath = p.join(projectPath, '.planning', 'STATE.md');
    try {
      final stat = await FileStat.stat(statePath);
      if (stat.type != FileSystemEntityType.notFound) {
        return now.difference(stat.modified) > threshold;
      }
    } catch (e) {
      // Ignore errors — no signal means not stale
      developer.log(
        'Failed to stat $statePath for staleness check: $e',
        name: 'project_scanner',
      );
    }

    return false;
  }

  /// Extracts agent names used in a project by scanning `.planning/` for
  /// VERIFICATION.md files containing `_Verifier: Claude (agent-name)_`
  /// or `Spawned by` references.
  Future<List<String>?> _extractUsedAgents(String projectPath) async {
    final planningDir = Directory(p.join(projectPath, '.planning', 'phases'));
    if (!await planningDir.exists()) return null;

    final agents = <String>{};
    final agentPattern = RegExp(r'Claude \(([a-z0-9-]+)\)');
    final spawnedPattern = RegExp(r'Spawned by.*?([a-z0-9]+-[a-z0-9-]+)');

    try {
      await for (final entity in planningDir.list(recursive: true)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.contains('VERIFICATION') && !name.contains('SUMMARY')) {
          continue;
        }

        try {
          final content = await entity.readAsString();
          for (final match in agentPattern.allMatches(content)) {
            agents.add(match.group(1)!);
          }
          for (final match in spawnedPattern.allMatches(content)) {
            agents.add(match.group(1)!);
          }
        } catch (e) {
          developer.log(
            'Failed to read ${entity.path}: $e',
            name: 'project_scanner',
          );
        }
      }
    } catch (e) {
      developer.log('Failed to list $planningDir: $e', name: 'project_scanner');
    }

    if (agents.isEmpty) return null;
    final sorted = agents.toList()..sort();
    return sorted;
  }

  /// Role labels for known .md files in Claude Code project workflows.
  static const _roleMap = <String, String>{
    'CLAUDE.md': 'Projekt-Instruktionen',
    'README.md': 'Dokumentation',
    'REQUIREMENTS.md': 'Anforderungen',
    'PROJECT.md': 'Projektvision',
    'STATE.md': 'Aktueller Stand',
    'ROADMAP.md': 'Phasen-Uebersicht',
  };

  /// Suffix-based roles for plan/phase files.
  static String? _suffixRole(String name) {
    if (name.endsWith('-PLAN.md')) return 'Ausfuehrungsplan';
    if (name.endsWith('-SUMMARY.md')) return 'Zusammenfassung';
    if (name.endsWith('-VERIFICATION.md')) return 'Verifikation';
    if (name.endsWith('-RESEARCH.md')) return 'Recherche';
    if (name.endsWith('-CONTEXT.md')) return 'Kontext';
    return null;
  }

  /// Scans a project for .md files at root and inside `.planning/` (max depth 3).
  ///
  /// Returns null if no .md files are found.
  Future<List<MdFileInfo>?> _scanMdFiles(String projectPath) async {
    final results = <MdFileInfo>[];

    // 1. Root-level .md files
    final rootDir = Directory(projectPath);
    try {
      await for (final entity in rootDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.md')) continue;
        results.add(
          MdFileInfo(
            name: name,
            relativePath: name,
            path: entity.path,
            role: _roleMap[name] ?? _suffixRole(name),
          ),
        );
      }
    } catch (e) {
      developer.log(
        'Failed to list root .md files in $projectPath: $e',
        name: 'project_scanner',
      );
    }

    // 2. .planning/ recursive (max depth ~3)
    final planningDir = Directory(p.join(projectPath, '.planning'));
    if (await planningDir.exists()) {
      try {
        await for (final entity in planningDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if (!name.endsWith('.md')) continue;

          final relativePath = p.relative(entity.path, from: projectPath);
          // Enforce max depth (~3 levels inside .planning)
          final segments = p.split(relativePath);
          if (segments.length > 5) continue; // .planning/a/b/c/file.md = 5

          results.add(
            MdFileInfo(
              name: name,
              relativePath: relativePath,
              path: entity.path,
              role: _roleMap[name] ?? _suffixRole(name),
            ),
          );
        }
      } catch (e) {
        developer.log(
          'Failed to list $planningDir: $e',
          name: 'project_scanner',
        );
      }
    }

    if (results.isEmpty) return null;
    results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return results;
  }

  /// Parses the JSON ignore list from the DB config string.
  List<String> _parseIgnoreList(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            // Hidden dirs are handled separately; drop '.*' to avoid confusion
            // but leave other patterns intact
            .where((p) => p != '.*')
            .toList();
      }
    } catch (e) {
      developer.log(
        'Malformed ignore list JSON, using empty list: $e',
        name: 'project_scanner',
      );
    }
    return [];
  }
}
