import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

/// One-directional writer of Pro Orc's six status fields into an Obsidian
/// vault hub — via frontmatter keys plus a marker-delimited body block.
/// Pure `dart:io` file operations only; never shells out (FR-018), never
/// reads hub content back into app state (FR-019), and never targets any
/// vault folder other than the configured hub folder (FR-020).
///
/// Every mutation is byte-preserving outside the six managed frontmatter
/// keys and the marker-delimited block: frontmatter is edited by line-level
/// splice (never parsed into a map and re-rendered — see [_spliceFrontmatter])
/// and the body's marker block is only touched when a single, well-formed,
/// line-anchored pair is found outside any fenced code region (see
/// [_mergeMarkerBlock]). When the file's shape is ambiguous or malformed,
/// this writer always prefers doing nothing (or appending, never deleting)
/// over guessing — losing a sync cycle is recoverable, destroying
/// hand-authored content is not.

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
  /// `vaultRoot` — rejected before any file I/O (FR-015). Also returned
  /// when a symlink resolves the target outside the root (M-3).
  skippedOutsideRoot,

  /// Any other I/O failure (e.g. disk full, permission denied on read).
  skippedIoError,
}

/// Sanitizes a single-line field value before it is interpolated into YAML
/// frontmatter or the marker block (M-2): strips CR/LF and other control
/// characters (which could inject a fake `---` terminator, a bogus
/// frontmatter key, or a premature marker), collapsing them to a single
/// space, THEN strips any occurrence of the literal marker strings or a
/// bare `---` line-delimiter substring so an attacker-controlled value
/// (these originate from parsed `.planning/`/`.a1/` file content — not a
/// trusted constant set) cannot forge a YAML document terminator or a fake
/// marker even after newlines are gone (e.g. `evil --- injected_key: x`
/// on one physical line still LOOKS like a YAML terminator to a human/
/// future-parser even without a real line break). This runs
/// unconditionally on every field.
String _sanitizeValue(String value) {
  // Strip all control characters (0x00-0x1F, 0x7F) — covers \n, \r, and
  // anything else that could desynchronize line-oriented parsing/writing.
  var stripped = value.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ');
  // Remove the marker literals and any run of 3+ dashes (a YAML/Markdown
  // delimiter) so they cannot masquerade as real structure even without
  // a newline.
  stripped = stripped
      .replaceAll(_markerStart, '')
      .replaceAll(_markerEnd, '')
      .replaceAll(RegExp(r'-{3,}'), '');
  // Collapse whitespace runs left behind by the removals above.
  return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
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
    if (!_isContained(targetPath, normalizedRoot)) {
      return VaultWriteResult.skippedOutsideRoot;
    }

    final sanitizedFields = _sanitizeFields(fields);
    final sanitizedDisplayName = _sanitizeValue(displayName);

    try {
      final file = File(targetPath);
      final exists = await file.exists();

      // Symlink guard (M-3): re-validate containment against the resolved
      // real path — a symlinked hub folder or hub file can lexically look
      // contained while actually pointing outside vaultRoot. Only
      // meaningful once something exists to resolve; a not-yet-created
      // file has no real path to escape through (its *parent* directory is
      // what could be a symlink — checked below before create).
      final parentDir = file.parent;
      if (await parentDir.exists()) {
        final resolvedParent = await parentDir.resolveSymbolicLinks();
        final resolvedRoot = await Directory(normalizedRoot).exists()
            ? await Directory(normalizedRoot).resolveSymbolicLinks()
            : normalizedRoot;
        if (!_isContained(
          p.join(resolvedParent, p.basename(targetPath)),
          resolvedRoot,
        )) {
          return VaultWriteResult.skippedOutsideRoot;
        }
      }
      if (exists) {
        final resolvedTarget = await file.resolveSymbolicLinks();
        final resolvedRoot = await Directory(
          normalizedRoot,
        ).resolveSymbolicLinks();
        if (!_isContained(resolvedTarget, resolvedRoot)) {
          return VaultWriteResult.skippedOutsideRoot;
        }
      }

      if (!exists) {
        return await _createHub(
          file: file,
          displayName: sanitizedDisplayName,
          fields: sanitizedFields,
        );
      }
      return await _updateHub(file: file, fields: sanitizedFields);
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

  VaultStatusFields _sanitizeFields(VaultStatusFields fields) =>
      VaultStatusFields(
        status: _sanitizeValue(fields.status),
        progress: fields.progress,
        phase: _sanitizeValue(fields.phase),
        milestone: _sanitizeValue(fields.milestone),
        lastCommit: fields.lastCommit == null
            ? null
            : _sanitizeValue(fields.lastCommit!),
        lastSync: fields.lastSync,
      );

  bool _isContained(String targetPath, String root) {
    final normalizedRoot = p.normalize(root);
    final normalizedTarget = p.normalize(targetPath);
    final rootWithSep = normalizedRoot.endsWith(p.separator)
        ? normalizedRoot
        : '$normalizedRoot${p.separator}';
    return normalizedTarget == normalizedRoot ||
        normalizedTarget.startsWith(rootWithSep);
  }

  Future<VaultWriteResult> _createHub({
    required File file,
    required String displayName,
    required VaultStatusFields fields,
  }) async {
    await file.parent.create(recursive: true);

    final frontmatterLines = [
      'type: project',
      'title: $displayName',
      ..._statusFrontmatterLines(fields),
    ];

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeAll(frontmatterLines.map((l) => '$l\n'))
      ..writeln('---')
      ..writeln()
      ..write(_renderMarkerBlock(fields))
      ..writeln();

    await _writeAtomic(file, buffer.toString());
    return VaultWriteResult.created;
  }

  Future<VaultWriteResult> _updateHub({
    required File file,
    required VaultStatusFields fields,
  }) async {
    // BOM preservation (m-2 from review): dart:io's readAsString() silently
    // strips a leading UTF-8 BOM on read and never re-adds it on write —
    // detect it on the raw bytes and prepend it back to whatever this
    // method produces, so a BOM-prefixed hub keeps its BOM across writes.
    final rawBytes = await file.readAsBytes();
    final hasBom =
        rawBytes.length >= 3 &&
        rawBytes[0] == 0xEF &&
        rawBytes[1] == 0xBB &&
        rawBytes[2] == 0xBF;
    // Normalize line endings to '\n' immediately on read (m-1 from review):
    // every line-oriented operation below (frontmatter splice, marker
    // scan) assumes '\n' separators — mixing in '\r\n'/'\r' produced
    // orphaned '\r' characters stranded mid-line after a write. This is a
    // whole-document normalization, not a byte-preserving no-op, but it is
    // consistent and produces a clean file rather than a mixed one; a
    // fully CRLF-preserving rewrite would need a much larger restructuring
    // and is not required by the review's fix guidance (grouped as Minor).
    final original = utf8
        .decode(rawBytes, allowMalformed: true)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final split = _splitFrontmatter(original);

    final newContent = split.hasFrontmatter
        ? _spliceFrontmatter(original, split, fields) +
              _mergeMarkerBlock(
                original.substring(split.bodyStart),
                fields,
                insertAtStart: true,
              )
        : _mergeMarkerBlock(original, fields, insertAtStart: false);

    await _writeAtomic(file, newContent, prependBom: hasBom);
    return VaultWriteResult.written;
  }

  List<String> _statusFrontmatterLines(VaultStatusFields fields) => [
    'proorc_status: ${fields.status}',
    'proorc_progress: ${fields.progress}',
    'proorc_phase: ${fields.phase}',
    'proorc_milestone: ${fields.milestone}',
    'proorc_last_commit: ${fields.lastCommit ?? ''}',
    'proorc_last_sync: ${fields.lastSync.toUtc().toIso8601String()}',
  ];

  String _renderMarkerBlock(VaultStatusFields fields) {
    final lastSyncLocal = fields.lastSync.toLocal();
    final syncStr = _formatDateTime(lastSyncLocal);
    final commitStr = _formatCommitTimestamp(fields.lastCommit);

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

  /// Formats [lastCommit] defensively (m-3 from review): a non-ISO8601
  /// value must never throw inside the write path — it is reported as
  /// "unbekannt" the same as a null value, rather than surfacing as a
  /// misleading `skippedIoError`.
  String _formatCommitTimestamp(String? lastCommit) {
    if (lastCommit == null) return 'unbekannt';
    final parsed = DateTime.tryParse(lastCommit);
    if (parsed == null) return 'unbekannt';
    return _formatDateTime(parsed.toLocal());
  }

  String _formatDateTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  /// Merges the rendered marker block into [body]: replaces the content
  /// strictly between a single well-formed, line-anchored marker pair if
  /// one is found outside any fenced code region (FR-009); otherwise
  /// inserts a fresh pair — at the very start of the body when
  /// [insertAtStart] is true (immediately after the closing frontmatter
  /// `---`, before any existing content — FR-010), or appended at the end
  /// otherwise (used for the no-frontmatter path, where there is no
  /// closing `---` to insert after).
  ///
  /// B-2 hardening: marker detection is line-anchored (the marker string
  /// must be the ENTIRE trimmed line — a mid-sentence mention of the
  /// literal marker text does not count), matches are skipped inside
  /// fenced code blocks (``` or ~~~), and any malformed shape — no start,
  /// no end, more than one of either, or an end before its start — causes
  /// this to fall back to the "insert a fresh block" path rather than
  /// guessing at a splice. Existing non-managed text is NEVER deleted by
  /// this method; the fallback only ever appends.
  String _mergeMarkerBlock(
    String body,
    VaultStatusFields fields, {
    required bool insertAtStart,
  }) {
    final marker = _locateMarkerPair(body);

    if (marker == null) {
      final rendered = _renderMarkerBlock(fields);
      if (insertAtStart) {
        final trimmedBody = body.startsWith('\n') ? body.substring(1) : body;
        return '\n$rendered\n\n$trimmedBody';
      }
      final needsLeadingNewline = body.isNotEmpty && !body.endsWith('\n');
      final separator = body.isEmpty
          ? ''
          : (needsLeadingNewline ? '\n\n' : '\n');
      return '$body$separator$rendered\n';
    }

    final before = body.substring(0, marker.startLineStart);
    final after = body.substring(marker.endLineEnd);
    return '$before${_renderMarkerBlock(fields)}\n$after';
  }

  /// Scans [body] line by line, skipping any content inside a fenced code
  /// block (``` or ~~~, matched by fence character run, not requiring a
  /// specific length beyond 3, and not requiring the closing fence to
  /// match the opening length — a conservative "inside some fence" state
  /// machine, not a full Markdown parser), for a start marker whose ENTIRE
  /// trimmed line equals [_markerStart] and an end marker whose entire
  /// trimmed line equals [_markerEnd]. Returns null (→ "no usable marker
  /// pair, insert fresh") unless exactly one start and exactly one end are
  /// found outside fences, in that order.
  _MarkerPair? _locateMarkerPair(String body) {
    final lines = const LineSplitter().convert(body);

    var offset = 0;
    var inFence = false;
    String? fenceChar;

    int? startLineStart;
    int? endLineStart;
    int? endLineEnd;
    var startCount = 0;
    var endCount = 0;

    for (final line in lines) {
      final lineStart = offset;
      final lineEnd = offset + line.length + 1; // includes the '\n'
      offset = lineEnd;

      final trimmed = line.trim();
      final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
      if (fenceMatch != null) {
        final char = fenceMatch.group(1)![0];
        if (!inFence) {
          inFence = true;
          fenceChar = char;
        } else if (fenceChar == char) {
          inFence = false;
          fenceChar = null;
        }
        continue;
      }

      if (inFence) continue;

      if (trimmed == _markerStart) {
        startCount++;
        startLineStart = lineStart;
      } else if (trimmed == _markerEnd) {
        endCount++;
        endLineStart = lineStart;
        endLineEnd = lineEnd > body.length ? body.length : lineEnd;
      }
    }

    if (startCount != 1 || endCount != 1) return null;
    if (startLineStart == null || endLineStart == null) return null;
    if (endLineStart < startLineStart) return null;

    return _MarkerPair(startLineStart: startLineStart, endLineEnd: endLineEnd!);
  }

  /// Splices the six `proorc_*` keys into [original]'s frontmatter block
  /// WITHOUT ever parsing it into a map and re-rendering (B-1 fix): each
  /// managed key's existing line (matched by exact `key:` line prefix,
  /// anchored at line start) is replaced in place; a key with no existing
  /// line is appended just before the closing `---`. Every other line —
  /// block-style YAML lists, nested keys, comments, blank lines, whatever
  /// — passes through completely untouched, byte-for-byte.
  String _spliceFrontmatter(
    String original,
    _FrontmatterSplit split,
    VaultStatusFields fields,
  ) {
    final frontmatterBlock = original.substring(
      split.contentStart,
      split.contentEnd,
    );
    // frontmatterBlock always ends with '\n' (contentEnd is right before
    // the closing delimiter line, per _splitFrontmatter) — splitting on
    // '\n' therefore always yields a trailing '' element representing "the
    // blank spot right before the closing ---". Missing managed keys must
    // be inserted BEFORE that trailing '' (i.e. still inside the block,
    // each on its own line with a trailing newline), not after it.
    final lines = frontmatterBlock.split('\n');
    final hasTrailingBlank = lines.isNotEmpty && lines.last.isEmpty;
    final contentLines = hasTrailingBlank
        ? lines.sublist(0, lines.length - 1)
        : lines;

    final managedLines = {
      for (final line in _statusFrontmatterLines(fields))
        line.substring(0, line.indexOf(':')): line,
    };
    final remainingKeys = Set<String>.from(managedLines.keys);

    final splicedLines = <String>[];
    for (final line in contentLines) {
      final colonIdx = line.indexOf(':');
      final key = colonIdx == -1 ? null : line.substring(0, colonIdx);
      if (key != null && managedLines.containsKey(key)) {
        // Only treat this as a "key line" to replace if it looks like a
        // real top-level `key: value` line (no leading whitespace) — a
        // nested key under a nested map (e.g. `  proorc_status: x` inside
        // some unrelated block) must not be clobbered. Managed keys are
        // always written at top level by this writer, so requiring
        // zero-indentation here cannot collide with a legitimately nested
        // occurrence of the same literal key name.
        if (!line.startsWith(' ') && !line.startsWith('\t')) {
          splicedLines.add(managedLines[key]!);
          remainingKeys.remove(key);
          continue;
        }
      }
      splicedLines.add(line);
    }

    // Append any managed keys that had no existing line, in the six-field
    // canonical order (not iteration order over the Set) — still inside
    // the frontmatter content, before the closing delimiter.
    for (final line in _statusFrontmatterLines(fields)) {
      final key = line.substring(0, line.indexOf(':'));
      if (remainingKeys.contains(key)) {
        splicedLines.add(line);
      }
    }

    // Re-add the trailing blank marker so the join reproduces the original
    // "ends with \n" shape of the block.
    if (hasTrailingBlank) splicedLines.add('');

    final newFrontmatterBlock = splicedLines.join('\n');
    // Returns ONLY the header region: opening '---' line through the
    // closing delimiter line (inclusive) — the caller appends the merged
    // body separately. Deliberately does NOT include anything from
    // split.contentEnd onward (that's the closing delimiter + body,
    // already accounted for by [split.bodyStart] in the caller).
    return original.substring(0, split.contentStart) +
        newFrontmatterBlock +
        original.substring(split.contentEnd, split.bodyStart);
  }

  /// Determines whether [content] begins with a genuine YAML frontmatter
  /// block: a `---` line at the very start, followed later by a `---` (or
  /// `...`) line on its own, with nothing required about what's between
  /// them (frontmatter here may contain block-style YAML this writer never
  /// parses into a map — see [_spliceFrontmatter]). If no closing
  /// delimiter line is found, the leading `---` is NOT frontmatter (M-6):
  /// it is left as ordinary body content (e.g. a Markdown horizontal
  /// rule), and the whole file is treated as body-only.
  _FrontmatterSplit _splitFrontmatter(String content) {
    final firstLineEnd = content.indexOf('\n');
    if (firstLineEnd == -1 ||
        content.substring(0, firstLineEnd).trim() != '---') {
      return const _FrontmatterSplit.none();
    }

    final closingPattern = RegExp(r'\n(---|\.\.\.)[ \t]*(\r?\n|$)');
    final match = closingPattern.firstMatch(content.substring(firstLineEnd));
    if (match == null) {
      return const _FrontmatterSplit.none();
    }

    final contentStart = firstLineEnd + 1;
    final contentEnd = firstLineEnd + match.start + 1;
    final bodyStart = firstLineEnd + match.end;

    return _FrontmatterSplit(
      hasFrontmatter: true,
      contentStart: contentStart,
      contentEnd: contentEnd,
      bodyStart: bodyStart > content.length ? content.length : bodyStart,
    );
  }

  /// Writes [content] atomically (B-3): a temp file in the SAME directory
  /// as [file] (guaranteeing the rename below is same-filesystem, hence
  /// atomic on macOS/APFS/HFS+) is written and flushed first, then
  /// renamed onto [file]. A crash, kill, or power loss at any point before
  /// the rename leaves the ORIGINAL file completely untouched — there is
  /// no window where the hub can be observed truncated or partially
  /// written, unlike the previous direct `writeAsString` (which opens with
  /// `FileMode.write`, truncating the target immediately).
  Future<void> _writeAtomic(
    File file,
    String content, {
    bool prependBom = false,
  }) async {
    final dir = file.parent;
    final tmpPath = p.join(
      dir.path,
      '.${p.basename(file.path)}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final tmpFile = File(tmpPath);
    final raf = await tmpFile.open(mode: FileMode.write);
    try {
      if (prependBom) {
        await raf.writeFrom(const [0xEF, 0xBB, 0xBF]);
      }
      await raf.writeString(content, encoding: utf8);
      await raf.flush();
    } finally {
      await raf.close();
    }
    await tmpFile.rename(file.path);
  }
}

class _MarkerPair {
  final int startLineStart;
  final int endLineEnd;

  const _MarkerPair({required this.startLineStart, required this.endLineEnd});
}

class _FrontmatterSplit {
  final bool hasFrontmatter;

  /// Offset (inclusive) where the frontmatter's inner content starts —
  /// right after the opening `---\n`.
  final int contentStart;

  /// Offset (exclusive) where the frontmatter's inner content ends — right
  /// before the closing delimiter line.
  final int contentEnd;

  /// Offset where the document body starts — right after the closing
  /// delimiter line (and its trailing newline, if present).
  final int bodyStart;

  const _FrontmatterSplit({
    required this.hasFrontmatter,
    required this.contentStart,
    required this.contentEnd,
    required this.bodyStart,
  });

  const _FrontmatterSplit.none()
    : hasFrontmatter = false,
      contentStart = 0,
      contentEnd = 0,
      bodyStart = 0;
}
