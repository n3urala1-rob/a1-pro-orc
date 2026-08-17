import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pro_orc/data/models/gitignore_template.dart';
import 'package:pro_orc/data/models/project_type.dart';
import 'package:pro_orc/data/services/process_runner.dart';
import 'package:pro_orc/data/services/project_importer_service.dart';

/// Result of a project creation operation.
///
/// [success] is false only if the directory creation itself failed.
/// All other failures (git init, file writes) are collected in [warnings].
class ProjectCreationResult {
  final String projectPath;
  final bool success;
  final List<String> warnings;

  const ProjectCreationResult({
    required this.projectPath,
    required this.success,
    this.warnings = const [],
  });
}

/// Creates a new project directory with optional scaffolding.
///
/// Steps (in order):
/// 1. Create project directory (fails entire operation if this fails)
/// 2. CLAUDE.md starter template
/// 3. .gitignore from template (flutter / nodejs / python)
/// 4. Research README.md (if projectType == 'research')
/// 5. git init + initial commit (warnings on failure, never fails overall)
///
/// All [Process.run] calls use [runInShell: true] because macOS GUI apps
/// do not inherit Homebrew PATH.
Future<ProjectCreationResult> createProject({
  required String scanDir,
  required String folderName, // Already kebab-case
  required String displayName, // Original user input
  required ProjectType projectType,
  bool gitInit = false,
  bool claudeMd = false,
  GitignoreTemplate gitignoreTemplate = GitignoreTemplate.none,
}) async {
  final projectPath = path.join(scanDir, folderName);
  final warnings = <String>[];

  // --- 1. Create directory ---
  final dir = Directory(projectPath);
  if (dir.existsSync()) {
    return ProjectCreationResult(
      projectPath: projectPath,
      success: false,
      warnings: ['Ordner existiert bereits: $projectPath'],
    );
  }

  try {
    await dir.create(recursive: true);
  } catch (e) {
    return ProjectCreationResult(
      projectPath: projectPath,
      success: false,
      warnings: ['Ordner konnte nicht erstellt werden: $e'],
    );
  }

  // --- 2-3. Scaffold files (CLAUDE.md, .gitignore) ---
  final scaffoldResult = await scaffoldProject(
    projectPath: projectPath,
    displayName: displayName,
    claudeMd: claudeMd,
    gitignoreTemplate: gitignoreTemplate,
    // git init is handled by scaffoldProject too, but we also need
    // the research README which is create-specific
  );
  warnings.addAll(scaffoldResult.warnings);

  // --- 4. Research README.md (create-specific, not in scaffoldProject) ---
  if (projectType == ProjectType.research) {
    try {
      await File(path.join(projectPath, 'README.md')).writeAsString(
        '# $displayName\n\n[Projektbeschreibung hier einfuegen]\n',
      );
    } catch (e) {
      warnings.add('README.md konnte nicht erstellt werden: $e');
    }
  }

  // --- 5. git init + initial commit ---
  if (gitInit) {
    final gitWarning = await _gitInitAndCommit(projectPath, displayName);
    if (gitWarning != null) {
      warnings.add(gitWarning);
    }
  }

  return ProjectCreationResult(
    projectPath: projectPath,
    success: true,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// git helpers
// ---------------------------------------------------------------------------

Future<String?> _gitInitAndCommit(
  String projectPath,
  String displayName,
) async {
  try {
    final initResult = await _runWithTimeout('git', ['init'], projectPath);
    if (initResult.exitCode != 0) {
      return 'git init fehlgeschlagen: ${initResult.stderr}';
    }

    final addResult = await _runWithTimeout('git', ['add', '-A'], projectPath);
    if (addResult.exitCode != 0) {
      return 'git add fehlgeschlagen: ${addResult.stderr}';
    }

    final commitResult = await _runWithTimeout('git', [
      'commit',
      '-m',
      'Initial commit: $displayName',
    ], projectPath);
    if (commitResult.exitCode != 0) {
      return 'git commit fehlgeschlagen: ${commitResult.stderr}';
    }

    return null; // success
  } catch (e) {
    return 'git-Fehler: $e';
  }
}

Future<ProcessResult> _runWithTimeout(
  String executable,
  List<String> arguments,
  String workingDirectory,
) {
  return runProcessWithTimeout(executable, arguments, workingDirectory);
}

// File content templates moved to project_importer_service.dart
// (claudeMdContent, gitignoreContent)
