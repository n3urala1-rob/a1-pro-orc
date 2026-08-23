import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pro_orc/features/onboarding/onboarding_wizard.dart';
import 'package:pro_orc/features/settings/vault_link_card.dart';
import 'package:pro_orc/features/shell/glass_card.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/learning_provider.dart';
import 'package:pro_orc/providers/projects_provider.dart';
import 'package:pro_orc/providers/theme_mode_provider.dart';
import 'package:pro_orc/providers/vault_link_statuses_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';
import 'package:pro_orc/providers/watcher_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Full-page settings tab — manages scan directories, ignore patterns,
/// git binary path, and launch-at-login preference.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  List<String> _scanDirs = [];
  List<String> _ignorePatterns = [];
  String _gitBinaryPath = 'git';
  String _vaultDir = '';
  String _vaultHubFolder = 'project';
  bool _launchAtLogin = false;
  bool _loading = true;

  final _gitController = TextEditingController();
  final _vaultController = TextEditingController();
  final _vaultHubFolderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _gitController.dispose();
    _vaultController.dispose();
    _vaultHubFolderController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final db = ref.read(appDatabaseProvider);
    final dirs = await db.getScanDirs();
    final config = await db.getConfig();
    final hubFolder = await db.getVaultHubFolder();

    List<String> patterns = [];
    try {
      final decoded = jsonDecode(config.ignoreListJson);
      if (decoded is List) {
        patterns = decoded.whereType<String>().toList();
      }
    } catch (e) {
      developer.log(
        'Failed to decode ignoreListJson: $e',
        name: 'settings_tab',
      );
    }

    bool launchEnabled = false;
    try {
      launchEnabled = await launchAtStartup.isEnabled();
    } catch (e) {
      developer.log(
        'Failed to read launchAtStartup.isEnabled: $e',
        name: 'settings_tab',
      );
    }

    if (mounted) {
      setState(() {
        _scanDirs = List.from(dirs);
        _ignorePatterns = patterns;
        _gitBinaryPath = config.gitBinaryPath;
        _gitController.text = config.gitBinaryPath;
        _vaultDir = config.vaultDir;
        _vaultController.text = config.vaultDir;
        _vaultHubFolder = hubFolder;
        _vaultHubFolderController.text = hubFolder;
        _launchAtLogin = launchEnabled;
        _loading = false;
      });
    }
  }

  // --- Scan Dirs ---

  Future<void> _addScanDir() async {
    final dir = await getDirectoryPath();
    if (dir != null && !_scanDirs.contains(dir)) {
      setState(() => _scanDirs = [..._scanDirs, dir]);
      await _saveScanDirs();
    }
  }

  Future<void> _removeScanDir(int index) async {
    setState(() => _scanDirs = [..._scanDirs]..removeAt(index));
    await _saveScanDirs();
  }

  Future<void> _saveScanDirs() async {
    final db = ref.read(appDatabaseProvider);
    await db.setScanDirs(_scanDirs);
    ref.invalidate(projectsProvider);
    // New/removed scan dirs must be picked up by the watcher immediately —
    // watcherProvider is keepAlive() and only reads scan dirs once at init
    // (see watcher_provider.dart), so without this invalidation newly added
    // directories are silently unwatched until the app restarts (F-011).
    ref.invalidate(watcherProvider);
  }

  // --- Ignore Patterns ---

  /// Opens the native macOS folder picker and adds the picked folder's
  /// basename as an ignore pattern. Cancelling the picker (null) is a no-op.
  /// Free-text/wildcard patterns are not creatable via this UI anymore —
  /// the basename is the exact unit `_matchesAnyIgnorePattern` compares
  /// against (see project_scanner.dart).
  Future<void> _addIgnorePattern() async {
    final dir = await getDirectoryPath();
    if (dir == null) return;
    final pattern = p.basename(dir);
    if (pattern.isEmpty || _ignorePatterns.contains(pattern)) return;
    setState(() => _ignorePatterns.add(pattern));
    await _saveIgnorePatterns();
  }

  Future<void> _removeIgnorePattern(int index) async {
    setState(() => _ignorePatterns.removeAt(index));
    await _saveIgnorePatterns();
  }

  Future<void> _saveIgnorePatterns() async {
    final db = ref.read(appDatabaseProvider);
    await db.updateConfig(ignoreListJson: jsonEncode(_ignorePatterns));
    ref.invalidate(projectsProvider);
  }

  // --- Git Binary ---

  Future<void> _saveGitBinary() async {
    final value = _gitController.text.trim();
    if (value.isNotEmpty && value != _gitBinaryPath) {
      setState(() => _gitBinaryPath = value);
      final db = ref.read(appDatabaseProvider);
      await db.updateConfig(gitBinaryPath: value);
      ref.invalidate(projectsProvider);
    }
  }

  // --- Vault-Pfad ---

  Future<void> _saveVaultDir() async {
    final value = _vaultController.text.trim();
    if (value == _vaultDir) return;
    setState(() => _vaultDir = value);
    final db = ref.read(appDatabaseProvider);
    await db.setVaultDir(value);
    ref.invalidate(learningProvider);
  }

  /// Persists the hub-folder convention (FR-001/FR-003 — M-4 fix, review
  /// round 1): previously the DB column/accessor existed and was fully
  /// tested, but no UI ever called `setVaultHubFolder`, leaving it
  /// permanently `'project'` in practice. Falls back to `'project'` on an
  /// empty save — the field is never allowed to end up truly blank, since
  /// VaultStatusWriter always needs some folder name to target.
  Future<void> _saveVaultHubFolder() async {
    final raw = _vaultHubFolderController.text.trim();
    final value = raw.isEmpty ? 'project' : raw;
    if (value == _vaultHubFolder) return;
    setState(() {
      _vaultHubFolder = value;
      _vaultHubFolderController.text = value;
    });
    final db = ref.read(appDatabaseProvider);
    await db.setVaultHubFolder(value);
    ref.invalidate(vaultLinkStatusesProvider);
  }

  // --- Launch at Login ---

  Future<void> _toggleLaunchAtLogin(bool value) async {
    setState(() => _launchAtLogin = value);
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (e) {
      // May fail in debug mode
      developer.log(
        'Failed to toggle launchAtStartup (value=$value): $e',
        name: 'settings_tab',
      );
    }
  }

  // --- Setup Wizard ---

  Future<void> _restartWizard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_completed');
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingWizard(
        onComplete: () {
          ref.invalidate(watcherProvider);
          ref.invalidate(projectsProvider);
          _loadSettings(); // Refresh settings tab state
        },
      ),
    );
    await prefs.setBool('onboarding_completed', true);
  }

  // --- UI Helpers ---

  String _abbreviatePath(String path) {
    return path.replaceFirst(RegExp(r'^/Users/[^/]+'), '~');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.cyan),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Einstellungen',
            style: TextStyle(
              color: colors.textPri,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          // --- Erscheinungsbild ---
          _buildThemeSection(colors),

          const SizedBox(height: 20),

          // --- Scan-Ordner ---
          _buildSection(
            colors: colors,
            icon: Icons.folder_outlined,
            title: 'Scan-Ordner',
            subtitle: 'Verzeichnisse, die nach Projekten durchsucht werden',
            child: Column(
              children: [
                if (_scanDirs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Keine Ordner konfiguriert',
                      style: TextStyle(color: colors.textSec, fontSize: 13),
                    ),
                  )
                else
                  ...List.generate(_scanDirs.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildDirRow(
                        colors,
                        _scanDirs[i],
                        () => _removeScanDir(i),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addScanDir,
                    icon: Icon(Icons.add, size: 16, color: colors.cyan),
                    label: Text(
                      'Ordner hinzufuegen',
                      style: TextStyle(color: colors.cyan, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.cyan.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Ignore-Muster ---
          _buildSection(
            colors: colors,
            icon: Icons.visibility_off_outlined,
            title: 'Ignorierte Ordner',
            subtitle: 'Ordner, die von der Projekt-Suche ausgeschlossen werden',
            child: Column(
              children: [
                if (_ignorePatterns.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(_ignorePatterns.length, (i) {
                      return Chip(
                        label: Text(
                          _ignorePatterns[i],
                          style: TextStyle(
                            color: colors.textSec,
                            fontSize: 12,
                            fontFamily: 'SF Mono',
                          ),
                        ),
                        deleteIcon: Icon(
                          Icons.close,
                          size: 14,
                          color: colors.textDim,
                        ),
                        onDeleted: () => _removeIgnorePattern(i),
                        backgroundColor: colors.bgElev.withValues(alpha: 0.6),
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      );
                    }),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ordner per Auswahl-Dialog hinzufuegen',
                        style: TextStyle(color: colors.textDim, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      onPressed: _addIgnorePattern,
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: colors.cyan,
                        size: 20,
                      ),
                      tooltip: 'Ordner hinzufuegen',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Git Binary ---
          _buildSection(
            colors: colors,
            icon: Icons.terminal_outlined,
            title: 'Git-Pfad',
            subtitle: 'Pfad zum Git-Binary (Standard: git)',
            child: _buildTextSettingRow(
              colors: colors,
              controller: _gitController,
              onSave: _saveGitBinary,
            ),
          ),

          const SizedBox(height: 20),

          // --- Vault-Pfad ---
          _buildSection(
            colors: colors,
            icon: LucideIcons.notebook,
            title: 'Obsidian-Vault',
            subtitle:
                'Pfad zum Vault für die Learning-Ansicht '
                '(Standard: ~/N3URAL-Vault)',
            child: _buildTextSettingRow(
              colors: colors,
              controller: _vaultController,
              hintText: '~/N3URAL-Vault',
              onSave: _saveVaultDir,
            ),
          ),

          const SizedBox(height: 20),

          // --- Vault-Sync ---
          _buildSection(
            colors: colors,
            icon: LucideIcons.refreshCw,
            title: 'Vault-Sync',
            subtitle: 'Projektstatus automatisch in Obsidian-Hubs schreiben',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ordner-Konvention',
                  style: TextStyle(
                    color: colors.textSec,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildTextSettingRow(
                  colors: colors,
                  controller: _vaultHubFolderController,
                  hintText: 'project',
                  onSave: _saveVaultHubFolder,
                ),
                const SizedBox(height: 10),
                Consumer(
                  builder: (context, ref, _) {
                    final reachableAsync = ref.watch(vaultReachableProvider);
                    if (reachableAsync.value == false) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Vault-Pfad nicht erreichbar — Sync pausiert '
                                'bis der Pfad wieder existiert. Zuordnungen '
                                'bleiben erhalten.',
                                style: TextStyle(
                                  color: colors.amber,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const VaultLinkCard(),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Launch at Login ---
          _buildSection(
            colors: colors,
            icon: Icons.rocket_launch_outlined,
            title: 'Autostart',
            subtitle: 'App beim Login automatisch starten',
            child: Row(
              children: [
                Text(
                  _launchAtLogin ? 'Aktiviert' : 'Deaktiviert',
                  style: TextStyle(color: colors.textSec, fontSize: 13),
                ),
                const Spacer(),
                Switch.adaptive(
                  value: _launchAtLogin,
                  onChanged: _toggleLaunchAtLogin,
                  activeTrackColor: colors.cyan,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- Setup Wizard ---
          _buildSection(
            colors: colors,
            icon: LucideIcons.wand,
            title: 'Setup',
            subtitle: 'Ersteinrichtungs-Wizard erneut durchlaufen',
            child: TextButton.icon(
              onPressed: _restartWizard,
              icon: Icon(LucideIcons.refreshCw, size: 16, color: colors.cyan),
              label: Text(
                'Setup-Wizard erneut starten',
                style: TextStyle(color: colors.textSec, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSection(AppColors colors) {
    final currentMode = ref.watch(themeModeProvider);

    return _buildSection(
      colors: colors,
      icon: Icons.palette_outlined,
      title: 'Erscheinungsbild',
      subtitle: 'Hell, Dunkel oder System-Einstellung folgen',
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Hell'),
            icon: Icon(Icons.light_mode_outlined, size: 16),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dunkel'),
            icon: Icon(Icons.dark_mode_outlined, size: 16),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            label: Text('System'),
            icon: Icon(Icons.settings_suggest_outlined, size: 16),
          ),
        ],
        selected: {currentMode},
        onSelectionChanged: (selected) {
          ref.read(themeModeProvider.notifier).setMode(selected.first);
        },
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, color: colors.textPri),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colors.textDim.withValues(alpha: 0.3)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.cyan.withValues(alpha: 0.18);
            }
            return colors.bgElev.withValues(alpha: 0.4);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.cyan;
            }
            return colors.textSec;
          }),
        ),
      ),
    );
  }

  Widget _buildSection({
    required AppColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.cyan, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPri,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: colors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  /// Shared row for a single text-setting field + "Speichern" button, used
  /// by both the Git-Pfad and Obsidian-Vault sections.
  Widget _buildTextSettingRow({
    required AppColors colors,
    required TextEditingController controller,
    String? hintText,
    required VoidCallback onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: TextStyle(
              color: colors.textPri,
              fontSize: 13,
              fontFamily: 'SF Mono',
            ),
            decoration: colors.glassInputDecoration(
              hintText: hintText,
              isDense: true,
            ),
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onSave,
          child: Text(
            'Speichern',
            style: TextStyle(color: colors.cyan, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildDirRow(AppColors colors, String dir, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bgElev.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder,
            color: colors.cyan.withValues(alpha: 0.7),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _abbreviatePath(dir),
              style: TextStyle(
                color: colors.textSec,
                fontSize: 12,
                fontFamily: 'SF Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.remove_circle_outline,
                color: colors.textDim,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
