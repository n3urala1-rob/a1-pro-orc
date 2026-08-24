import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:pro_orc/data/models/automation_data.dart';
import 'package:pro_orc/data/models/harness_data.dart';
import 'package:pro_orc/data/services/process_runner.dart';
import 'package:pro_orc/data/services/secret_masking.dart';

// ---------------------------------------------------------------------------
// Pure parse functions (top-level, unit-testable with string fixtures)
// ---------------------------------------------------------------------------

/// Extracts the `<key>Label</key>` string value from a launchd plist XML.
/// Returns null when absent.
String? parsePlistLabel(String xml) {
  final match = RegExp(
    r'<key>\s*Label\s*</key>\s*<string>(.*?)</string>',
    dotAll: true,
  ).firstMatch(xml);
  return match?.group(1)?.trim();
}

/// Extracts the `ProgramArguments` array (or a single `Program` string) from a
/// launchd plist XML as a joined command line. Returns an empty string when
/// neither is present.
String parsePlistProgram(String xml) {
  final argsMatch = RegExp(
    r'<key>\s*ProgramArguments\s*</key>\s*<array>(.*?)</array>',
    dotAll: true,
  ).firstMatch(xml);
  if (argsMatch != null) {
    final inner = argsMatch.group(1) ?? '';
    final args = RegExp(r'<string>(.*?)</string>', dotAll: true)
        .allMatches(inner)
        .map((m) => (m.group(1) ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return args.join(' ');
  }

  final progMatch = RegExp(
    r'<key>\s*Program\s*</key>\s*<string>(.*?)</string>',
    dotAll: true,
  ).firstMatch(xml);
  return progMatch?.group(1)?.trim() ?? '';
}

/// True when a plist declares `RunAtLoad`, used as a coarse schedule hint.
bool parsePlistRunAtLoad(String xml) {
  return RegExp(
    r'<key>\s*RunAtLoad\s*</key>\s*<true\s*/>',
    dotAll: true,
  ).hasMatch(xml);
}

/// Parses a single launchd plist XML into an [Automation], or null when it does
/// not reference `claude` in its program. Command is secret-masked.
Automation? parseLaunchdPlist(String xml, {String? fallbackName}) {
  final program = parsePlistProgram(xml);
  if (!_mentionsClaude(program)) return null;

  final label = parsePlistLabel(xml) ?? fallbackName ?? 'launchd-agent';
  return Automation(
    name: label,
    command: maskSecrets(program),
    schedule: parsePlistRunAtLoad(xml) ? 'RunAtLoad' : '',
    source: AutomationSource.launchd,
  );
}

/// Parses `crontab -l` output into [Automation]s, keeping only lines that
/// reference `claude`. Comment (`#`) and blank lines are skipped. Each cron
/// line is `min hour dom mon dow  command…`; the first five fields become the
/// schedule, the rest the (masked) command.
List<Automation> parseCrontab(String output) {
  final out = <Automation>[];
  for (final raw in const LineSplitter().convert(output)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!_mentionsClaude(line)) continue;

    // Split into the 5 schedule fields + remainder command.
    final parts = line.split(RegExp(r'\s+'));
    String schedule = '';
    String command = line;
    if (parts.length > 5) {
      schedule = parts.take(5).join(' ');
      command = parts.skip(5).join(' ');
    }
    out.add(
      Automation(
        name: 'crontab',
        command: maskSecrets(command),
        schedule: schedule,
        source: AutomationSource.cron,
      ),
    );
  }
  return out;
}

/// True when [text] references the Claude CLI (whole-word-ish, case-insensitive).
bool _mentionsClaude(String text) =>
    RegExp(r'\bclaude\b', caseSensitive: false).hasMatch(text);

// ---------------------------------------------------------------------------
// AutomationReader
// ---------------------------------------------------------------------------

/// Discovers automations best-effort (AD-3), strictly read-only.
///
/// No Flutter imports — pure Dart. Defensive throughout: unreadable plists, a
/// missing crontab, or a failing `crontab` invocation each yield no entries
/// from that source rather than an error.
class AutomationReader {
  /// Directory holding launchd user agents. Defaults to
  /// `$HOME/Library/LaunchAgents`; overridable for tests.
  final String launchAgentsDir;

  /// Injectable crontab reader for tests — returns the raw `crontab -l` output,
  /// or null when there is no crontab. Defaults to actually running `crontab`.
  final Future<String?> Function() _readCrontab;

  AutomationReader({
    String? launchAgentsDirOverride,
    Future<String?> Function()? readCrontab,
  }) : launchAgentsDir =
           launchAgentsDirOverride ??
           p.join(
             Platform.environment['HOME'] ?? '',
             'Library',
             'LaunchAgents',
           ),
       _readCrontab = readCrontab ?? _defaultReadCrontab;

  /// Reads all sources and returns the combined result. [hooks] come from the
  /// already-loaded [HarnessData] so hooks are surfaced as automations without
  /// re-reading settings.json.
  Future<AutomationData> read({List<HarnessHook> hooks = const []}) async {
    final automations = <Automation>[];

    automations.addAll(await _readLaunchd());
    automations.addAll(await _readCron());
    automations.addAll(_fromHooks(hooks));

    return AutomationData(automations: automations);
  }

  /// Scans `~/Library/LaunchAgents/*.plist` for agents invoking `claude`.
  Future<List<Automation>> _readLaunchd() async {
    final out = <Automation>[];
    final dir = Directory(launchAgentsDir);
    try {
      if (!await dir.exists()) return out;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.plist')) continue;
        try {
          final xml = await entity.readAsString();
          final automation = parseLaunchdPlist(
            xml,
            fallbackName: p.basenameWithoutExtension(entity.path),
          );
          if (automation != null) out.add(automation);
        } catch (e) {
          developer.log(
            'Skipping unreadable plist ${entity.path}: $e',
            name: 'automation_reader',
          );
        }
      }
    } catch (e) {
      developer.log(
        'Failed to list $launchAgentsDir: $e',
        name: 'automation_reader',
      );
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Reads the user crontab (via the injected reader) and filters for `claude`.
  Future<List<Automation>> _readCron() async {
    try {
      final output = await _readCrontab();
      if (output == null || output.isEmpty) return const [];
      return parseCrontab(output);
    } catch (e) {
      developer.log('Failed to read crontab: $e', name: 'automation_reader');
      return const [];
    }
  }

  /// Converts harness hooks into automations — hooks fire automatically on
  /// events, so they are workflows. Commands are secret-masked.
  List<Automation> _fromHooks(List<HarnessHook> hooks) {
    return [
      for (final h in hooks)
        Automation(
          name: h.matcher.isEmpty ? h.event : '${h.event} · ${h.matcher}',
          command: maskSecrets(h.command),
          schedule: h.event,
          source: AutomationSource.hook,
        ),
    ];
  }

  /// Default crontab reader: `crontab -l` with runInShell (macOS GUI apps do
  /// not inherit a login PATH). Returns null when there is no crontab.
  ///
  /// Routed through [runProcessWithTimeout] (process-storm round 3, WP2) —
  /// this was previously the only ungated spawn reachable from an AUTOMATIC
  /// path (via `automation_provider.dart`'s watcher invalidation), bypassing
  /// the app-wide [ProcessSemaphore] the round-2 fix otherwise made
  /// structural for every other call site.
  static Future<String?> _defaultReadCrontab() async {
    try {
      final result = await runProcessWithTimeout(
        'crontab',
        ['-l'],
        '.',
        timeout: const Duration(seconds: 5),
      );
      if (result.exitCode != 0) return null; // "no crontab for user"
      final stdout = result.stdout;
      return stdout is String ? stdout : stdout.toString();
    } catch (e) {
      developer.log('crontab -l failed: $e', name: 'automation_reader');
      return null;
    }
  }
}
