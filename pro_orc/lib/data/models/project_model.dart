import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/models/memory_data.dart';
import 'package:pro_orc/data/models/project_type.dart';

/// Metadata for a .md file discovered in a project directory.
class MdFileInfo {
  final String name; // "STATE.md"
  final String relativePath; // ".planning/STATE.md"
  final String path; // absoluter Pfad
  final String? role; // "Aktueller Stand", "Projekt-Instruktionen", etc.

  const MdFileInfo({
    required this.name,
    required this.relativePath,
    required this.path,
    this.role,
  });

  /// Value equality — see [ProjectModel.operator==] for why this matters.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MdFileInfo &&
          name == other.name &&
          relativePath == other.relativePath &&
          path == other.path &&
          role == other.role);

  @override
  int get hashCode => Object.hash(name, relativePath, path, role);
}

class ProjectModel {
  final String folderId; // folder name, canonical ID
  final String displayName; // PROJECT.md H1 or folder name fallback
  final String path; // absolute path
  final ProjectType? projectType; // null = unclassified
  final String? description; // from PROJECT.md or CLAUDE.md
  final A1Data? a1; // null if no .a1/ (a1 roadmap/phase status, M6)
  final GitData? git; // null if not a git repo
  final bool isStale; // >30 days since last activity
  final List<String>? usedAgents; // agent names found in .planning/ files
  final MemoryData? memory; // null if no Claude memory consolidation
  final List<MdFileInfo>? mdFiles; // .md files discovered in project

  const ProjectModel({
    required this.folderId,
    required this.displayName,
    required this.path,
    this.projectType,
    this.description,
    this.a1,
    this.git,
    this.memory,
    this.isStale = false,
    this.usedAgents,
    this.mdFiles,
  });

  /// Value equality across all fields, so [ProjectModel] can be safely used
  /// as a `FutureProvider.family` key (externalResourcesProvider,
  /// visionProvider, roadmapProvider) without a fresh instance from every
  /// rescan invalidating those families' caches and re-running their work
  /// (e.g. re-spawning the vercel CLI) even when nothing actually changed.
  ///
  /// Full-field equality — not just `path`/`folderId` — is deliberate:
  /// `externalResourcesProvider`'s `resource_detector.dart` reads
  /// `project.git?.githubUrl` and `project.mdFiles` too, so an identity- or
  /// path-only comparison could mask a real content change (e.g. the git
  /// remote changing, or a new .md file with resource links appearing)
  /// behind a "same key" family cache hit — showing stale data instead of
  /// re-running detection. Comparing every field costs nothing extra here
  /// (all fields are already small, comparable values or comparable lists)
  /// and is the only choice that can't silently go stale.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectModel &&
          folderId == other.folderId &&
          displayName == other.displayName &&
          path == other.path &&
          projectType == other.projectType &&
          description == other.description &&
          a1 == other.a1 &&
          git == other.git &&
          memory == other.memory &&
          isStale == other.isStale &&
          _listEquals(usedAgents, other.usedAgents) &&
          _listEquals(mdFiles, other.mdFiles));

  @override
  int get hashCode => Object.hash(
    folderId,
    displayName,
    path,
    projectType,
    description,
    a1,
    git,
    memory,
    isStale,
    usedAgents == null ? null : Object.hashAll(usedAgents!),
    mdFiles == null ? null : Object.hashAll(mdFiles!),
  );
}

/// Nullable-list-aware element-wise equality (order-sensitive) — avoids
/// adding `package:collection` as a direct dependency for this comparison.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
