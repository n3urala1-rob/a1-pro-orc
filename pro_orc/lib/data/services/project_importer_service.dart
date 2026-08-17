import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pro_orc/data/models/gitignore_template.dart';
import 'package:pro_orc/data/models/project_type.dart';
import 'package:pro_orc/data/services/process_runner.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Code project marker files — if any exist, it's a code project.
const codeMarkers = [
  'pubspec.yaml',
  'package.json',
  'Cargo.toml',
  'go.mod',
  'pom.xml',
  'build.gradle',
  'CMakeLists.txt',
  'Makefile',
  'requirements.txt',
  'pyproject.toml',
  'setup.py',
  'Gemfile',
  'mix.exs',
  'composer.json',
  'tsconfig.json',
  'eslint.config.mjs',
  'next.config.js',
  'next.config.ts',
  'vite.config.ts',
  'vite.config.js',
];

/// Common code subdirectories.
const _codeDirs = ['lib', 'src', 'app', 'bin'];

// ---------------------------------------------------------------------------
// Type inference
// ---------------------------------------------------------------------------

/// Infers project type from folder contents.
///
/// Checks for common build/config files that indicate a code project.
/// Then checks common code subdirs (lib, src, app, bin).
/// Then checks one level of subdirectories for monorepo patterns.
/// Falls back to [ProjectType.research] if nothing matches.
Future<ProjectType> inferProjectType(String projectPath) async {
  // Check root-level marker files
  for (final marker in codeMarkers) {
    final file = File(p.join(projectPath, marker));
    if (await file.exists()) return ProjectType.code;
  }

  // Check common code subdirectories
  for (final dir in _codeDirs) {
    final d = Directory(p.join(projectPath, dir));
    if (await d.exists()) return ProjectType.code;
  }

  // Check one level of subdirectories for code markers (monorepos)
  final rootDir = Directory(projectPath);
  try {
    await for (final entity in rootDir.list()) {
      if (entity is Directory) {
        for (final marker in codeMarkers) {
          final file = File(p.join(entity.path, marker));
          if (await file.exists()) return ProjectType.code;
        }
      }
    }
  } catch (e) {
    // Ignore errors — fall through to research
    developer.log(
      'Failed to scan subdirectories of $projectPath for code markers: $e',
      name: 'project_importer_service',
    );
  }

  return ProjectType.research;
}

// ---------------------------------------------------------------------------
// Folder analysis
// ---------------------------------------------------------------------------

/// Result of analyzing an existing folder for import.
class FolderAnalysis {
  final String path;
  final String folderName;
  final ProjectType detectedType;
  final bool hasGit;
  final bool hasPlanning;
  final bool hasClaudeMd;
  final bool hasGitignore;
  final bool isInsideScanDir;
  final String? containingScanDir;

  const FolderAnalysis({
    required this.path,
    required this.folderName,
    required this.detectedType,
    required this.hasGit,
    required this.hasPlanning,
    required this.hasClaudeMd,
    required this.hasGitignore,
    required this.isInsideScanDir,
    this.containingScanDir,
  });
}

/// Analyzes an existing folder for import readiness.
///
/// Detects project type, existing files/dirs, and whether the folder
/// is inside any of the given [scanDirs] using [p.isWithin].
Future<FolderAnalysis> analyzeFolder(
  String folderPath,
  List<String> scanDirs,
) async {
  final hasGit = Directory(p.join(folderPath, '.git')).existsSync();
  final hasPlanning = Directory(p.join(folderPath, '.planning')).existsSync();
  final hasClaudeMd = File(p.join(folderPath, 'CLAUDE.md')).existsSync();
  final hasGitignore = File(p.join(folderPath, '.gitignore')).existsSync();
  final detectedType = await inferProjectType(folderPath);
  final folderName = p.basename(folderPath);

  // Check scan-dir containment (strip trailing slashes)
  String? containingScanDir;
  for (final scanDir in scanDirs) {
    final normalized = scanDir.endsWith('/')
        ? scanDir.substring(0, scanDir.length - 1)
        : scanDir;
    if (p.isWithin(normalized, folderPath)) {
      containingScanDir = normalized;
      break;
    }
  }

  return FolderAnalysis(
    path: folderPath,
    folderName: folderName,
    detectedType: detectedType,
    hasGit: hasGit,
    hasPlanning: hasPlanning,
    hasClaudeMd: hasClaudeMd,
    hasGitignore: hasGitignore,
    isInsideScanDir: containingScanDir != null,
    containingScanDir: containingScanDir,
  );
}

// ---------------------------------------------------------------------------
// Scaffolding
// ---------------------------------------------------------------------------

/// Result of scaffolding a project folder.
class ScaffoldResult {
  /// Relative paths of files created during scaffolding.
  final List<String> created;

  /// Non-fatal warnings encountered during scaffolding.
  final List<String> warnings;

  const ScaffoldResult({this.created = const [], this.warnings = const []});
}

/// Scaffolds an existing project folder with optional CLAUDE.md,
/// .gitignore, and git init.
///
/// Each step checks existence before writing — never overwrites existing files.
/// After scaffolding, if git is available and files were created, runs
/// `git add -A` + `git commit`.
///
/// All [Process.run] calls use [runInShell: true] because macOS GUI apps
/// do not inherit Homebrew PATH.
Future<ScaffoldResult> scaffoldProject({
  required String projectPath,
  required String displayName,
  bool claudeMd = false,
  GitignoreTemplate gitignoreTemplate = GitignoreTemplate.none,
  bool gitInit = false,
}) async {
  final created = <String>[];
  final warnings = <String>[];

  // --- CLAUDE.md ---
  if (claudeMd) {
    final claudeFile = File(p.join(projectPath, 'CLAUDE.md'));
    if (!claudeFile.existsSync()) {
      try {
        await claudeFile.writeAsString(claudeMdContent(displayName));
        created.add('CLAUDE.md');
      } catch (e) {
        warnings.add('CLAUDE.md konnte nicht erstellt werden: $e');
      }
    }
  }

  // --- .gitignore ---
  if (gitignoreTemplate != GitignoreTemplate.none) {
    final gitignoreFile = File(p.join(projectPath, '.gitignore'));
    if (!gitignoreFile.existsSync()) {
      try {
        final content = gitignoreContent(gitignoreTemplate);
        if (content != null) {
          await gitignoreFile.writeAsString(content);
          created.add('.gitignore');
        }
      } catch (e) {
        warnings.add('.gitignore konnte nicht erstellt werden: $e');
      }
    }
  }

  // --- git init ---
  final gitDir = Directory(p.join(projectPath, '.git'));
  if (gitInit && !gitDir.existsSync()) {
    try {
      final initResult = await _runWithTimeout('git', ['init'], projectPath);
      if (initResult.exitCode != 0) {
        warnings.add('git init fehlgeschlagen: ${initResult.stderr}');
      }
    } catch (e) {
      warnings.add('git init fehlgeschlagen: $e');
    }
  }

  // --- Auto-commit scaffolded files ---
  if (created.isNotEmpty && gitDir.existsSync()) {
    try {
      final addResult = await _runWithTimeout('git', [
        'add',
        '-A',
      ], projectPath);
      if (addResult.exitCode == 0) {
        final commitMsg = 'scaffold: ${created.join(', ')}';
        await _runWithTimeout('git', ['commit', '-m', commitMsg], projectPath);
      }
    } catch (e) {
      warnings.add('git commit fehlgeschlagen: $e');
    }
  }

  return ScaffoldResult(created: created, warnings: warnings);
}

// ---------------------------------------------------------------------------
// Git helper
// ---------------------------------------------------------------------------

Future<ProcessResult> _runWithTimeout(
  String executable,
  List<String> arguments,
  String workingDirectory,
) {
  return runProcessWithTimeout(executable, arguments, workingDirectory);
}

// ---------------------------------------------------------------------------
// File content templates (public for reuse by project_creator_service)
// ---------------------------------------------------------------------------

String claudeMdContent(String displayName) =>
    '''
# CLAUDE.md

## Project Overview

**$displayName** — [Projektbeschreibung hier einfuegen]

## Build & Run Commands

```bash
# [Build-Befehle hier einfuegen]
```

## Architecture

[Architektur hier beschreiben]

## Conventions

[Konventionen hier definieren]
''';

String? gitignoreContent(GitignoreTemplate template) {
  switch (template) {
    case GitignoreTemplate.flutter:
      return '''
.dart_tool/
.packages
build/
.flutter-plugins
.flutter-plugins-dependencies
*.iml
.idea/
.vscode/
*.lock
.DS_Store
''';
    case GitignoreTemplate.nodejs:
      return '''
node_modules/
dist/
build/
.env
.env.local
*.log
.DS_Store
.vscode/
.idea/
coverage/
''';
    case GitignoreTemplate.nextjs:
      return '''
node_modules/
.next/
out/
build/
.env
.env.local
.env*.local
*.log
.DS_Store
.vscode/
.idea/
coverage/
.vercel/
.tailwind/
''';
    case GitignoreTemplate.python:
      return '''
__pycache__/
*.py[cod]
.env
.venv/
venv/
dist/
build/
*.egg-info/
.DS_Store
.idea/
.vscode/
''';
    case GitignoreTemplate.html:
      return '''
.DS_Store
.idea/
.vscode/
*.log
Thumbs.db
node_modules/
.tailwind/
''';
    case GitignoreTemplate.none:
      return null;
  }
}
