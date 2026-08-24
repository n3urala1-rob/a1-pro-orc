import 'dart:developer' as developer;
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

/// Valid slash-command skill names: an optional leading slash, then letters,
/// digits and `:_-`. Guards against typos and shell-metacharacter injection.
final RegExp _skillNamePattern = RegExp(r'^/?[A-Za-z0-9:_-]+$');

/// True if [skillName] is a syntactically valid skill/slash-command name.
bool isValidSkillName(String skillName) =>
    _skillNamePattern.hasMatch(skillName);

/// NOTE on the raw [Process.run] calls in this class (process-storm round 3,
/// WP2 review): every call here is `osascript`/`open -a Terminal`,
/// triggered by a single user click and never looped or fired from a
/// watcher/scan path. Deliberately NOT routed through
/// `runProcessWithTimeout`/[ProcessSemaphore]:
/// - These hand off to an already-running, user-facing Terminal.app window
///   and exit almost immediately themselves — there is no compound `sh -c`
///   spawning a background child, so there is nothing for [killProcessTree]
///   to protect against here.
/// - Frequency is bounded by human click rate, not by scan/event volume —
///   the semaphore exists to cap concurrent AUTOMATIC spawns (round-2 root
///   cause: up to 90 concurrent git calls from one scan), which does not
///   apply to a single deliberate click.
/// Revisit if any of these calls is ever wired to fire automatically
/// (e.g. from a batch action or a watcher-driven trigger).
class QuickActionsService {
  /// Opens Terminal.app and cd's into the project directory.
  /// Uses osascript for reliable directory navigation.
  Future<void> openInTerminal(String projectPath) async {
    final script = _terminalScript(_buildCdCommand(projectPath));
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// Reveals project directory in Finder.
  Future<void> openInFinder(String projectPath) async {
    await Process.run('open', [projectPath], runInShell: true);
  }

  /// Reveals a local path in Finder, but only if it exists on disk. Returns
  /// `true` on success, `false` if the path doesn't exist — callers show a
  /// graceful failure indicator instead of silently no-op'ing.
  Future<bool> openLocalPathInFinder(String path) async {
    final exists =
        await FileSystemEntity.isDirectory(path) ||
        await FileSystemEntity.isFile(path);
    if (!exists) return false;
    await Process.run('open', [path], runInShell: true);
    return true;
  }

  /// Builds the shell command that cd's into [projectPath] and runs Claude
  /// Code with [prompt] as its argument — `claude "<prompt>"`. Pure and
  /// exposed for testing so the escaping of both the path and the prompt is
  /// verifiable without spawning a process.
  ///
  /// Both the path and the prompt sit inside double quotes for the shell
  /// layer, so both are escaped via [_shellEscapeDoubleQuoted] to prevent
  /// either one from breaking out of its quoting.
  String buildClaudePromptCommand(String projectPath, String prompt) {
    final escapedPrompt = _shellEscapeDoubleQuoted(prompt);
    return _buildCdCommand(projectPath, 'claude "$escapedPrompt"');
  }

  /// Opens Terminal.app, cd's into the project directory, and runs
  /// Claude Code with the given prompt string.
  Future<void> openClaudeWithPrompt(String projectPath, String prompt) async {
    final script = _terminalScript(
      buildClaudePromptCommand(projectPath, prompt),
    );
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// Opens Terminal.app, cd's into the project directory, and runs
  /// `claude /rem-sleep` to trigger memory consolidation.
  Future<void> openRemSleep(String projectPath) async {
    final script = _terminalScript(
      _buildCdCommand(projectPath, 'claude /rem-sleep'),
    );
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// Opens a URL (e.g. GitHub) in the system default browser.
  /// Silently fails if URL cannot be launched (consistent with service error pattern).
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri);
  }

  /// Builds the AppleScript command to open Claude in the given directory.
  /// Exposed for testability.
  String buildClaudeScript(String projectPath) {
    return _terminalScript(_buildCdCommand(projectPath, 'claude'));
  }

  /// Builds the shell command that launches Claude Code in [projectPath] with
  /// the given [skillName] pre-invoked as a slash command — `claude "/<skill>"`
  /// (AD-4). Pure and exposed for testing so the escaping of paths and skill
  /// names is verifiable without spawning a process.
  ///
  /// Both the path (double-quoted) and the skill argument (double-quoted) are
  /// escaped for the shell: backslashes and double quotes are backslash-escaped
  /// so a path or skill name containing them cannot break out of its quotes.
  /// The leading slash of the slash command is added here — pass the bare
  /// skill name (e.g. `a1-fix`), with or without a leading slash.
  String buildSkillLaunchCommand(String projectPath, String skillName) {
    final skill = skillName.startsWith('/') ? skillName : '/$skillName';
    final skillArg = _shellEscapeDoubleQuoted(skill);
    return _buildCdCommand(projectPath, 'claude "$skillArg"');
  }

  /// Opens Terminal.app, cd's into [projectPath], and starts Claude Code with
  /// [skillName] invoked as a slash command. Rejects (and logs) a skill name
  /// that fails [isValidSkillName] — an early typo/injection guard.
  Future<void> openClaudeWithSkill(String projectPath, String skillName) async {
    if (!isValidSkillName(skillName)) {
      developer.log(
        'Refusing to launch invalid skill name: "$skillName"',
        name: 'quick_actions',
      );
      return;
    }
    final script = _terminalScript(
      buildSkillLaunchCommand(projectPath, skillName),
    );
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// Escapes a value to sit safely inside a double-quoted shell string.
  String _shellEscapeDoubleQuoted(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  /// Builds `cd "<escaped path>"[ && <suffix>]` — the shared shell-command
  /// shape used by every quick action that navigates into [projectPath]
  /// before optionally running another command. The path always goes
  /// through [_shellEscapeDoubleQuoted] so it cannot break out of its quotes.
  String _buildCdCommand(String projectPath, [String? suffix]) {
    final path = _shellEscapeDoubleQuoted(projectPath);
    return suffix == null ? 'cd "$path"' : 'cd "$path" && $suffix';
  }

  /// Opens Terminal.app, cd's into the project directory, and starts Claude Code.
  Future<void> openClaude(String projectPath) async {
    final script = buildClaudeScript(projectPath);
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// The exact, hard-coded command run to re-request the GitHub `delete_repo`
  /// OAuth scope. A Dart string literal — never built from interpolation —
  /// so "no dynamic value in this command" is structurally guaranteed, not
  /// just documented (FR-004a).
  static const String ghScopeRefreshCommand = 'gh auth refresh -s delete_repo';

  /// Builds the AppleScript to run [ghScopeRefreshCommand] in a new Terminal
  /// window. Unlike the other terminal builders above, this command is not
  /// project-scoped — there is no `cd` into a project directory, since
  /// granting a `gh` OAuth scope is not tied to any working directory.
  ///
  /// The constant command is still routed through [_terminalScript] (which
  /// applies the same AppleScript-escaping as every other terminal builder
  /// in this class) rather than being inlined directly into the osascript
  /// call — consistency with the 2026-07-13 command-injection hardening, so
  /// a future edit that adds a dynamic segment to this command inherits the
  /// escaping automatically instead of having to remember to add it.
  String buildGhScopeRefreshScript() {
    return _terminalScript(ghScopeRefreshCommand);
  }

  /// Opens Terminal.app and runs the constant `gh auth refresh -s
  /// delete_repo` command to re-request the GitHub `delete_repo` OAuth
  /// scope. Uses the same osascript `do script` + `open -a Terminal`
  /// execution path as every other terminal-opening action in this class.
  Future<void> openTerminalWithGhScopeRefresh() async {
    final script = buildGhScopeRefreshScript();
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// The exact, hard-coded command run to log in to (and grant the
  /// `delete_repo` scope for) a GitHub account other than the currently
  /// active `gh` session — the correct action when the repo's owning
  /// account differs from the active account, since `gh auth refresh` can
  /// only ever operate on the currently active account (verified against
  /// `gh auth refresh --help`, no `--user` flag; see
  /// 2026-07-22-gh-auth-refresh-wrong-account). Deliberately
  /// account-agnostic — `gh` prompts interactively in the browser for which
  /// account to authenticate as, so no owner name is interpolated into this
  /// command. A Dart string literal, never built from interpolation, same
  /// "no dynamic value" guarantee as [ghScopeRefreshCommand].
  static const String ghScopeLoginCommand = 'gh auth login -s delete_repo';

  /// Builds the AppleScript to run [ghScopeLoginCommand] in a new Terminal
  /// window. Not project-scoped, same shape as [buildGhScopeRefreshScript].
  String buildGhScopeLoginScript() {
    return _terminalScript(ghScopeLoginCommand);
  }

  /// Opens Terminal.app and runs the constant `gh auth login -s
  /// delete_repo` command — logs in (and activates) the account the user
  /// authenticates as in the browser, granting the `delete_repo` scope in
  /// the same step. Used instead of [openTerminalWithGhScopeRefresh] when
  /// the repo owner does not match the currently active `gh` account, since
  /// `gh auth refresh` cannot target a different account
  /// (2026-07-22-gh-auth-refresh-wrong-account).
  Future<void> openTerminalWithGhScopeLogin() async {
    final script = buildGhScopeLoginScript();
    await Process.run('osascript', ['-e', script], runInShell: true);
    await Process.run('open', ['-a', 'Terminal'], runInShell: true);
  }

  /// Builds AppleScript to run a command in a new Terminal window.
  String _terminalScript(String command) {
    // Escape backslashes and double quotes for AppleScript string
    final escaped = command.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return 'tell application "Terminal" to do script "$escaped"';
  }
}
