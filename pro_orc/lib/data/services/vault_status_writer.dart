import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

/// One-directional writer of Pro Orc's six status fields into an Obsidian
/// vault hub — via frontmatter keys plus a marker-delimited body block.
/// Pure `dart:io` file operations only; never shells out (FR-018), never
/// reads hub content back into app state (FR-019), and never targets any
/// vault folder other than the configured hub folder (FR-020).

const String _markerStart = '<!-- proorc:status:start -->';
const String _markerEnd = '<!-- proorc:status:end -->';

/// The six managed status fields for a single write. Structurally the only
/// input to what ends up in frontmatter/marker content — there is no way to
/// pass arbitrary prose or links through this type (FR-011).
class VaultStatusFields {
  final String status;
  final int progress;
  final String phase;
  final String milestone;
  final String? lastCommit;
  final DateTime lastSync;

  const VaultStatusFields({
    required this.status,
    required this.progress,
    required this.phase,
    required this.milestone,
    required this.lastCommit,
    required this.lastSync,
  });
}

enum VaultWriteResult {
  /// An existing hub's frontmatter/marker block was merged/updated.
  written,

  /// No hub existed yet; a new one was created with minimal frontmatter.
  created,

  /// The target could not be written because it (or its parent) is locked
  /// or otherwise inaccessible. Never thrown past [VaultStatusWriter.write].
  skippedLocked,

  /// The resolved target path escaped [VaultStatusWriter.write]'s
  /// `vaultRoot` — rejected before any file I/O (FR-015).
  skippedOutsideRoot,

  /// Any other I/O failure (e.g. disk full, permission denied on read).
  skippedIoError,
}

class VaultStatusWriter {
  /// Writes [fields] into the hub at
  /// `<vaultRoot>/<hubFolder>/<hubSlug>.md`.
  ///
  /// [vaultRoot]: resolved absolute vault directory (already resolved from
  /// the DB's vaultDir setting by the caller — this class does no HOME
  /// expansion).
  /// [hubFolder]: e.g. 'project'. Hardcoded call-site value — this class
  /// has no code path that can target any other 7-type-IA folder
  /// (`pattern/`, `record/`, `idea/`, `reference/`, `inbox/`, `session/`).
  /// [hubSlug]: confirmed or auto-create slug (filename stem, no '.md').
  /// [displayName]: used only for `title:` on auto-create (FR-006), never
  /// written into the marker block (FR-011 prose ban).
  Future<VaultWriteResult> write({
    required String vaultRoot,
    required String hubFolder,
    required String hubSlug,
    required String displayName,
    required VaultStatusFields fields,
  }) async {
    final normalizedRoot = p.normalize(vaultRoot);
    final targetPath = p.normalize(
      p.join(normalizedRoot, hubFolder, '$hubSlug.md'),
    );

    // Path-traversal guard (FR-015): the resolved target MUST live inside
    // vaultRoot. Checked before any file I/O.
    final rootWithSep = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    if (!targetPath.startsWith(rootWithSep)) {
      return VaultWriteResult.skippedOutsideRoot;
    }

    try {
      final file = File(targetPath);
      if (!await file.exists()) {
        return await _createHub(
          file: file,
          displayName: displayName,
          fields: fields,
        );
      }
      return await _updateHub(file: file, fields: fields);
    } on FileSystemException catch (e) {
      developer.log(
        'Vault write failed for $targetPath: ${e.message}',
        name: 'vault_status_writer',
      );
      // OS lock/permission errors surface with these errno values; treat
      // everything else as a generic soft-fail IO error.
      final errno = e.osError?.errorCode;
      if (errno == 13 /* EACCES */ || errno == 35 /* EAGAIN/locked */ ) {
        return VaultWriteResult.skippedLocked;
      }
      return VaultWriteResult.skippedIoError;
    } catch (e) {
      developer.log(
        'Unexpected vault write failure for $targetPath: $e',
        name: 'vault_status_writer',
      );
      return VaultWriteResult.skippedIoError;
    }
  }

  Future<VaultWriteResult> _createHub({
    required File file,
    required String displayName,
    required VaultStatusFields fields,
  }) async {
    await file.parent.create(recursive: true);

    final frontmatter = <String, String>{
      'type': 'project',
      'title': displayName,
      ..._statusFrontmatter(fields),
    };

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(_renderFrontmatter(frontmatter))
      ..writeln('---')
      ..writeln()
      ..write(_renderMarkerBlock(fields))
      ..writeln();

    await file.writeAsString(buffer.toString());
    return VaultWriteResult.created;
  }

  Future<VaultWriteResult> _updateHub({
    required File file,
    required VaultStatusFields fields,
  }) async {
    final original = await file.readAsString();
    final parsed = _splitFrontmatter(original);

    final mergedFrontmatter = Map<String, String>.from(parsed.frontmatter)
      ..addAll(_statusFrontmatter(fields));

    final updatedBody = _mergeMarkerBlock(parsed.body, fields);

    final buffer = StringBuffer()
      ..writeln('---')
      ..write(_renderFrontmatter(mergedFrontmatter))
      ..writeln('---')
      ..write(updatedBody);

    await file.writeAsString(buffer.toString());
    return VaultWriteResult.written;
  }

  Map<String, String> _statusFrontmatter(VaultStatusFields fields) => {
    'proorc_status': fields.status,
    'proorc_progress': '${fields.progress}',
    'proorc_phase': fields.phase,
    'proorc_milestone': fields.milestone,
    'proorc_last_commit': fields.lastCommit ?? '',
    'proorc_last_sync': fields.lastSync.toUtc().toIso8601String(),
  };

  String _renderMarkerBlock(VaultStatusFields fields) {
    final lastSyncLocal = fields.lastSync.toLocal();
    final syncStr = _formatDateTime(lastSyncLocal);
    final commitStr = fields.lastCommit == null
        ? 'unbekannt'
        : _formatDateTime(DateTime.parse(fields.lastCommit!).toLocal());

    return '''
$_markerStart
**Status:** ${fields.status}
**Fortschritt:** ${fields.progress}%
**Phase:** ${fields.phase}
**Milestone:** ${fields.milestone}
**Letzter Commit:** $commitStr
**Letzte Synchronisierung:** $syncStr
$_markerEnd''';
  }

  String _formatDateTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  /// Merges the rendered marker block into [body]: replaces the content
  /// strictly between existing markers if present (FR-009), otherwise
  /// inserts the pair at the very start of the body — i.e. immediately
  /// after the closing frontmatter `---`, before any existing content
  /// (FR-010).
  String _mergeMarkerBlock(String body, VaultStatusFields fields) {
    final startIdx = body.indexOf(_markerStart);
    final endIdx = body.indexOf(_markerEnd);

    if (startIdx == -1 || endIdx == -1 || endIdx < startIdx) {
      final rendered = _renderMarkerBlock(fields);
      final trimmedBody = body.startsWith('\n') ? body.substring(1) : body;
      return '\n$rendered\n\n$trimmedBody';
    }

    final before = body.substring(0, startIdx);
    final after = body.substring(endIdx + _markerEnd.length);
    return '$before${_renderMarkerBlock(fields)}$after';
  }

  /// Splits a hub file's raw content into its frontmatter map (flat
  /// `key: value` scalars only — this project's hubs never nest YAML) and
  /// the remaining body. Hand-rolled rather than depending on `package:yaml`
  /// (not a direct dependency of this project) since frontmatter here is
  /// always flat scalars.
  _ParsedHub _splitFrontmatter(String content) {
    if (!content.startsWith('---')) {
      return _ParsedHub(frontmatter: {}, body: content);
    }

    final closingIdx = content.indexOf('\n---', 3);
    if (closingIdx == -1) {
      return _ParsedHub(frontmatter: {}, body: content);
    }

    final rawFrontmatter = content.substring(3, closingIdx).trim();
    // Body starts after the closing '---' line.
    final afterClosing = content.indexOf('\n', closingIdx + 1);
    final body = afterClosing == -1 ? '' : content.substring(afterClosing + 1);

    final frontmatter = <String, String>{};
    final order = <String>[];
    for (final line in const LineSplitter().convert(rawFrontmatter)) {
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;
      final key = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();
      if (key.isEmpty) continue;
      frontmatter[key] = value;
      order.add(key);
    }

    return _ParsedHub(frontmatter: frontmatter, body: body, keyOrder: order);
  }

  /// Renders a frontmatter map back to YAML lines, preserving the original
  /// key order where known (from [_ParsedHub.keyOrder]) and appending any
  /// new keys (the `proorc_*` fields on first write) after that.
  String _renderFrontmatter(Map<String, String> frontmatter) {
    final buffer = StringBuffer();
    for (final entry in frontmatter.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    return buffer.toString();
  }
}

class _ParsedHub {
  final Map<String, String> frontmatter;
  final String body;
  final List<String> keyOrder;

  _ParsedHub({
    required this.frontmatter,
    required this.body,
    this.keyOrder = const [],
  });
}

/// Minimal line splitter avoiding a `dart:convert` import cost for a single
/// call site — kept local so this module's imports stay dart:io/path-only,
/// legible against the FR-018 "no Process" structural constraint.
class LineSplitter {
  const LineSplitter();

  List<String> convert(String input) => input.split('\n');
}
