import 'dart:convert';
import 'dart:developer' as developer;

import 'package:pro_orc/data/models/roadmap_data.dart';
import 'package:pro_orc/data/services/process_runner.dart';
import 'package:pro_orc/data/services/roadmap/mcp_transport.dart';
import 'package:pro_orc/data/services/roadmap/roadmap_repository.dart';

/// A1 Brain MCP tier of the roadmap fallback chain (FR-002, FR-010,
/// FR-015).
///
/// Speaks streamable-HTTP MCP (JSON-RPC 2.0), NOT a plain REST API:
/// `initialize` → `notifications/initialized` → `tools/call` with
/// `search_notes` (find the project's `project/<slug>.md` hub note) and
/// `read_note` (fetch its content), per the 7-type Brain IA
/// (`~/code/n3ural-brain/brain-deploy/BRAIN-IA.md`) and the handshake in
/// `~/code/n3ural-brain/brain-deploy/CLIENT-CONNECT.md`.
///
/// The bearer token is read from the macOS Keychain at call time via
/// `security find-generic-password -a brain-proxy -s brain-proxy-token -w`
/// and is NEVER logged, persisted, or included in any [developer.log] call
/// or exception message (FR-010) — every log/error string in this file is
/// checked against that constraint; see the "never logs token" test.
///
/// Pure Dart, no Flutter imports. Never throws: every failure mode is
/// caught and classified into exactly one [RoadmapFailureKind] (FR-015),
/// surfaced as an empty [RoadmapData] with a [RoadmapFailure] attached.
class A1BrainRoadmapRepository implements RoadmapRepository {
  A1BrainRoadmapRepository({
    McpTransport? transport,
    Future<String?> Function()? readToken,
  }) : _transport = transport ?? HttpMcpTransport(),
       _readToken = readToken ?? _readTokenFromKeychain;

  final McpTransport _transport;
  final Future<String?> Function() _readToken;

  static int _requestId = 0;

  /// Reads the bearer token from the macOS Keychain. Never logs the
  /// resulting value; returns null (not an exception) when the entry is
  /// missing so the caller can classify that as an auth failure.
  static Future<String?> _readTokenFromKeychain() async {
    try {
      final result = await runProcessWithTimeout('security', [
        'find-generic-password',
        '-a',
        'brain-proxy',
        '-s',
        'brain-proxy-token',
        '-w',
      ], '.');
      if (result.exitCode != 0) return null;
      final token = (result.stdout as String).trim();
      return token.isEmpty ? null : token;
    } catch (_) {
      // Deliberately no logging here — an exception's message could echo
      // process arguments; nothing sensitive is in them, but we still avoid
      // logging Keychain interaction details entirely per FR-010's spirit.
      return null;
    }
  }

  @override
  Future<RoadmapResult> resolve(String slug, String projectPath) async {
    try {
      final token = await _readToken();
      if (token == null) {
        return _failure(RoadmapFailureKind.authFailure, 'no token in keychain');
      }

      final initResult = await _transport.send(
        body: _jsonRpc('initialize', {
          'protocolVersion': '2024-11-05',
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'pro_orc', 'version': '1.0'},
        }),
        bearerToken: token,
      );
      final sessionId = initResult.sessionId;

      await _transport.send(
        body: {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, dynamic>{},
        },
        bearerToken: token,
        sessionId: sessionId,
      );

      final searchResult = await _transport.send(
        body: _jsonRpc('tools/call', {
          'name': 'search_notes',
          'arguments': {'query': 'project/$slug', 'page': 1, 'page_size': 5},
        }),
        bearerToken: token,
        sessionId: sessionId,
      );

      final noteId = _extractHubNoteId(searchResult.body, slug);
      if (noteId == null) {
        return _failure(
          RoadmapFailureKind.noResult,
          'no matching hub note for slug',
        );
      }

      final readResult = await _transport.send(
        body: _jsonRpc('tools/call', {
          'name': 'read_note',
          'arguments': {'identifier': noteId},
        }),
        bearerToken: token,
        sessionId: sessionId,
      );

      final data = _parseRoadmapData(readResult.body);
      if (data.isEmpty) {
        return _failure(
          RoadmapFailureKind.noResult,
          'hub note had no roadmap content',
        );
      }

      return RoadmapResult(data: data, source: RoadmapSource.brain);
    } on McpTimeoutException {
      return _failure(RoadmapFailureKind.timeout, 'mcp call timed out');
    } on McpAuthException {
      return _failure(
        RoadmapFailureKind.authFailure,
        'mcp server rejected token',
      );
    } catch (e) {
      // Any other unexpected failure (connection refused, malformed JSON,
      // etc.) is treated as "no result" — never propagated as an exception.
      developer.log(
        'A1 Brain resolve failed: $e',
        name: 'a1_brain_roadmap_repository',
      );
      return _failure(RoadmapFailureKind.noResult, 'unexpected error');
    }
  }

  RoadmapResult _failure(RoadmapFailureKind kind, String message) {
    return RoadmapResult(
      data: RoadmapData.empty,
      source: RoadmapSource.brain,
      failure: RoadmapFailure(kind, message),
    );
  }

  Map<String, dynamic> _jsonRpc(String method, Map<String, dynamic> params) {
    return {
      'jsonrpc': '2.0',
      'id': ++_requestId,
      'method': method,
      'params': params,
    };
  }

  /// Extracts the Brain resource identifier for the project's hub note
  /// (`project/<slug>.md`) from a `search_notes` JSON-RPC response.
  ///
  /// Expected shape (MCP `tools/call` result): `result.content[0].text` is
  /// a JSON- or plain-text search result payload; this defensively looks
  /// for a `permalink`/`id`/`path` field matching `project/<slug>` among
  /// any nested result entries, returning null (not throwing) on any
  /// unexpected shape.
  String? _extractHubNoteId(Map<String, dynamic>? response, String slug) {
    if (response == null) return null;
    final result = response['result'];
    if (result is! Map) return null;

    // Prefer a structured `results` array when present. Some servers only
    // expose results embedded as a JSON string inside `content[].text` (the
    // MCP `tools/call` envelope) — fall back to parsing that.
    if (result['results'] is List) {
      for (final item in result['results'] as List) {
        final candidate = _findPermalink(item, slug);
        if (candidate != null) return candidate;
      }
    }

    final content = result['content'];
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['text'] is String) {
          final parsed = _tryDecode(item['text'] as String);
          if (parsed != null) {
            final candidate = _findPermalink(parsed, slug);
            if (candidate != null) return candidate;
          }
        }
      }
    }

    return null;
  }

  dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  String? _findPermalink(dynamic node, String slug) {
    if (node is Map) {
      for (final key in ['permalink', 'id', 'path', 'identifier']) {
        final value = node[key];
        if (value is String &&
            value.contains('project/') &&
            value.contains(slug)) {
          return value;
        }
      }
      for (final value in node.values) {
        final found = _findPermalink(value, slug);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findPermalink(value, slug);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Parses a `read_note` JSON-RPC response's Markdown body into
  /// [RoadmapData]. The Brain hub note is free-form Markdown, not the
  /// milestone-table shape `A1Reader` parses — this looks for `## `
  /// headings as milestone names and nested `- ` list items as phase
  /// entries, which is deliberately lenient: any parse failure yields
  /// [RoadmapData.empty] rather than throwing (per FR-009's spirit,
  /// applied here to the Brain tier too).
  RoadmapData _parseRoadmapData(Map<String, dynamic>? response) {
    if (response == null) return RoadmapData.empty;
    final result = response['result'];
    if (result is! Map) return RoadmapData.empty;

    final content = result['content'];
    String? text;
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['text'] is String) {
          text = item['text'] as String;
          break;
        }
      }
    } else if (result['text'] is String) {
      text = result['text'] as String;
    }
    if (text == null || text.trim().isEmpty) return RoadmapData.empty;

    final milestones = <RoadmapMilestone>[];
    String? currentMilestone;
    final phases = <RoadmapPhase>[];

    void flush() {
      final milestoneName = currentMilestone;
      if (milestoneName != null) {
        milestones.add(
          RoadmapMilestone(
            name: milestoneName,
            status: 'unknown',
            phases: List.of(phases),
          ),
        );
        phases.clear();
      }
    }

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('## ')) {
        flush();
        currentMilestone = line.substring(3).trim();
      } else if (currentMilestone != null &&
          (line.startsWith('- ') || line.startsWith('* '))) {
        phases.add(
          RoadmapPhase(name: line.substring(2).trim(), status: 'unknown'),
        );
      }
    }
    flush();

    return RoadmapData(milestones: milestones);
  }
}
