import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes a new, standalone `record/`-type vault note for one completed
/// headless skill run — explicitly NOT built on top of `VaultStatusWriter`
/// (spec 010 FR-011 structurally reserves that class's marker-block
/// mechanism for the six status fields only; reusing it here for freeform
/// skill output would violate that ban). This class reuses only the
/// *pattern* `VaultStatusWriter` established: a path-traversal containment
/// check resolved against [write]'s `vaultRoot` before any file I/O, and an
/// atomic temp-file + rename write in the same directory as the target —
/// not the class itself.
///
/// Unlike `VaultStatusWriter`, this writer never reads or merges an
/// existing file: every call creates a brand-new note. A same-day/
/// same-skill/same-project collision gets a numeric suffix rather than
/// silently overwriting a prior run's note (never destroy prior content —
/// same design philosophy as the Spec 010 writer).
class VaultRecordWriter {
  /// Writes a new `record/`-type note at
  /// `<vaultRoot>/record/<YYYY-MM-DD>-<skillSlug>-<projectSlug>.md` (a
  /// numeric suffix, e.g. `-2`, is appended if that exact filename already
  /// exists).
  ///
  /// [outcome] is expected to be one of 'erfolgreich', 'fehlgeschlagen',
  /// 'abgebrochen' (German, per spec — this class does not validate the
  /// value beyond writing it verbatim into the rendered body).
  /// [bodyContent] (the run's raw captured output) is written inside a
  /// fenced code block so it can never be misinterpreted as Markdown/YAML
  /// structure. The fence length is computed adaptively per CommonMark
  /// (longest backtick run inside the body + 1, minimum 3) so output that
  /// itself contains fenced blocks — the norm for `a1-progress`, whose
  /// templates are fenced — can never break out of the wrapper fence and
  /// render as live Markdown/wikilinks in Obsidian.
  Future<VaultRecordWriteResult> write({
    required String vaultRoot,
    required String projectHubSlug,
    required String skillSlug,
    required String skillDisplayName,
    required String outcome,
    required String bodyContent,
    required DateTime completedAt,
  }) async {
    final normalizedRoot = p.normalize(vaultRoot);
    final recordDir = p.normalize(p.join(normalizedRoot, 'record'));

    if (!_isContained(recordDir, normalizedRoot)) {
      return const VaultRecordWriteResult.skippedOutsideRoot();
    }

    final dateStr = _formatDate(completedAt);
    final safeSkillSlug = _sanitizeSlug(skillSlug);
    final safeProjectSlug = _sanitizeSlug(projectHubSlug);
    final baseName = '$dateStr-$safeSkillSlug-$safeProjectSlug';

    try {
      final targetPath = await _resolveNonCollidingPath(recordDir, baseName);
      if (!_isContained(targetPath, normalizedRoot)) {
        return const VaultRecordWriteResult.skippedOutsideRoot();
      }

      final file = File(targetPath);

      // Symlink guard: if the record/ directory already exists (as itself
      // or as a symlink), re-validate containment against its resolved
      // real path before writing — mirrors VaultStatusWriter's M-3 fix.
      final dir = Directory(recordDir);
      if (await dir.exists()) {
        final resolvedDir = await dir.resolveSymbolicLinks();
        final resolvedRoot = await Directory(normalizedRoot).exists()
            ? await Directory(normalizedRoot).resolveSymbolicLinks()
            : normalizedRoot;
        if (!_isContained(
          p.join(resolvedDir, p.basename(targetPath)),
          resolvedRoot,
        )) {
          return const VaultRecordWriteResult.skippedOutsideRoot();
        }
      }

      final content = _renderNote(
        projectHubSlug: projectHubSlug,
        skillDisplayName: skillDisplayName,
        outcome: outcome,
        bodyContent: bodyContent,
        completedAt: completedAt,
        dateStr: dateStr,
      );

      await file.parent.create(recursive: true);
      await _writeAtomic(file, content);

      return VaultRecordWriteResult.written(targetPath);
    } on FileSystemException catch (e) {
      developer.log(
        'Vault record write failed for $recordDir/$baseName.md: ${e.message}',
        name: 'vault_record_writer',
      );
      final errno = e.osError?.errorCode;
      if (errno == 13 /* EACCES */ || errno == 35 /* EAGAIN/locked */ ) {
        return const VaultRecordWriteResult.skippedLocked();
      }
      return const VaultRecordWriteResult.skippedIoError();
    } catch (e) {
      developer.log(
        'Unexpected vault record write failure: $e',
        name: 'vault_record_writer',
      );
      return const VaultRecordWriteResult.skippedIoError();
    }
  }

  /// Finds the first available `<baseName>[-N].md` path in [recordDir] that
  /// does not already exist — a same-day/same-skill/same-project collision
  /// gets a numeric suffix rather than overwriting the earlier note.
  Future<String> _resolveNonCollidingPath(
    String recordDir,
    String baseName,
  ) async {
    var candidate = p.join(recordDir, '$baseName.md');
    if (!await File(candidate).exists()) return candidate;

    var suffix = 2;
    while (true) {
      candidate = p.join(recordDir, '$baseName-$suffix.md');
      if (!await File(candidate).exists()) return candidate;
      suffix++;
    }
  }

  String _renderNote({
    required String projectHubSlug,
    required String skillDisplayName,
    required String outcome,
    required String bodyContent,
    required DateTime completedAt,
    required String dateStr,
  }) {
    final timeStr = _formatTime(completedAt);
    final fence = _fenceFor(bodyContent);
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('type: record')
      ..writeln('title: $skillDisplayName – $outcome')
      ..writeln('date: $dateStr')
      ..writeln('---')
      ..writeln()
      ..writeln('# $skillDisplayName')
      ..writeln()
      ..writeln('**Skill:** $skillDisplayName')
      ..writeln('**Ergebnis:** $outcome')
      ..writeln('**Abgeschlossen:** $dateStr $timeStr')
      ..writeln()
      ..writeln('## Relations')
      ..writeln()
      ..writeln('part_of [[project/$projectHubSlug]]')
      ..writeln()
      ..writeln('## Ausgabe')
      ..writeln()
      ..writeln(fence)
      ..writeln(bodyContent)
      ..writeln(fence);
    return buffer.toString();
  }

  /// Computes a CommonMark-safe fence delimiter for [body]: three backticks
  /// unless [body] itself contains a run of three or more consecutive
  /// backticks, in which case the fence is one backtick longer than the
  /// longest such run — the standard rule for guaranteeing a fenced code
  /// block actually contains everything inside it, since CommonMark only
  /// closes a fence on a delimiter line of matching or greater length.
  String _fenceFor(String body) {
    final matches = RegExp(r'`{3,}').allMatches(body);
    var longest = 0;
    for (final match in matches) {
      final len = match.end - match.start;
      if (len > longest) longest = len;
    }
    final fenceLength = longest >= 3 ? longest + 1 : 3;
    return '`' * fenceLength;
  }

  bool _isContained(String targetPath, String root) {
    final normalizedRoot = p.normalize(root);
    final normalizedTarget = p.normalize(targetPath);
    final rootWithSep = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    return normalizedTarget == normalizedRoot ||
        normalizedTarget.startsWith(rootWithSep);
  }

  /// Replaces anything that is not alphanumeric, `-`, or `_` — strips path
  /// separators (`/`, `\`) and `..` traversal segments entirely rather than
  /// merely rejecting them, so a manipulated slug can never influence the
  /// resolved path at all (defense-in-depth alongside the containment
  /// check above, which is still the authoritative guard).
  String _sanitizeSlug(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  String _formatDate(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${local.year}-${pad(local.month)}-${pad(local.day)}';
  }

  String _formatTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final local = dt.toLocal();
    return '${pad(local.hour)}:${pad(local.minute)}';
  }

  /// Atomic write: a temp file in the SAME directory as [file] (guaranteeing
  /// the rename is same-filesystem, hence atomic on macOS/APFS/HFS+) is
  /// written and flushed first, then renamed onto [file] — reusing
  /// `VaultStatusWriter._writeAtomic`'s pattern (not the class itself).
  Future<void> _writeAtomic(File file, String content) async {
    final dir = file.parent;
    final tmpPath = p.join(
      dir.path,
      '.${p.basename(file.path)}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final tmpFile = File(tmpPath);
    try {
      final raf = await tmpFile.open(mode: FileMode.write);
      try {
        await raf.writeString(content, encoding: utf8);
        await raf.flush();
      } finally {
        await raf.close();
      }
      await tmpFile.rename(file.path);
    } catch (_) {
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {
        // Cleanup-of-cleanup; the original error still propagates.
      }
      rethrow;
    }
  }
}

/// Outcome of a [VaultRecordWriter.write] call.
class VaultRecordWriteResult {
  const VaultRecordWriteResult.written(this.path)
    : status = VaultRecordWriteStatus.written;
  const VaultRecordWriteResult.skippedOutsideRoot()
    : status = VaultRecordWriteStatus.skippedOutsideRoot,
      path = null;
  const VaultRecordWriteResult.skippedLocked()
    : status = VaultRecordWriteStatus.skippedLocked,
      path = null;
  const VaultRecordWriteResult.skippedIoError()
    : status = VaultRecordWriteStatus.skippedIoError,
      path = null;

  final VaultRecordWriteStatus status;

  /// The written file's absolute path — only set when [status] is
  /// [VaultRecordWriteStatus.written].
  final String? path;
}

enum VaultRecordWriteStatus {
  written,
  skippedOutsideRoot,
  skippedLocked,
  skippedIoError,
}
