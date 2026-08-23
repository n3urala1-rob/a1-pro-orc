import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/features/onboarding/onboarding_wizard.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/project_detail_provider.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/projects_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';
import 'package:pro_orc/providers/watcher_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';
import 'package:pro_orc/tray/tray_service.dart';
import 'package:pro_orc/window/activation_policy_service.dart';
import 'package:pro_orc/window/window_geometry_service.dart';
import 'package:pro_orc/features/agents/agents_tab.dart';
import 'package:pro_orc/features/claude_tools/claude_tools_tab.dart';
import 'package:pro_orc/features/harness/harness_tab.dart';
import 'package:pro_orc/features/learning/learning_tab.dart';
import 'package:pro_orc/features/projects/projects_tab.dart';
import 'package:pro_orc/features/settings/settings_tab.dart';
import 'package:pro_orc/features/shared/project_detail_panel.dart';
import 'package:pro_orc/features/shell/glow_border_shell.dart';
import 'package:pro_orc/features/shell/orb_background.dart';
import 'package:pro_orc/features/skills/skills_tab.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({
    super.key,
    ActivationPolicyService? activationPolicyService,
  }) : activationPolicyService =
           activationPolicyService ?? const ActivationPolicyService();

  /// Shared instance passed down from main.dart so the whole app talks to
  /// the native activation-policy MethodChannel through one object. Defaults
  /// to a fresh instance for callers (e.g. widget tests) that don't wire one
  /// up explicitly — safe since the service is stateless.
  final ActivationPolicyService activationPolicyService;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with WindowListener, TrayListener {
  late final TrayService _trayService;
  final WindowGeometryService _geometryService = WindowGeometryService();

  int _selectedIndex = 0;

  /// Tab index active when a project detail view was opened, so the back
  /// button / closing the detail view returns to that tab instead of
  /// hard-jumping to index 0.
  int _tabIndexBeforeDetail = 0;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _trayService = TrayService(
      activationPolicyService: widget.activationPolicyService,
    );
    _trayService.init();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _checkOnboarding();
    });
  }

  /// Shows the onboarding wizard on first launch when scan dirs are
  /// still at the default value. Skips automatically for users who
  /// already configured custom scan directories or completed the wizard.
  Future<void> _checkOnboarding() async {
    final db = ref.read(appDatabaseProvider);
    final scanDirs = await db.getScanDirs();

    // Smart skip: if user has custom scan dirs, they don't need the wizard
    final home = Platform.environment['HOME']!;
    final isDefault =
        scanDirs.length == 1 && scanDirs.first == '$home/project_orchestration';

    final prefs = await SharedPreferences.getInstance();
    final wizardCompleted = prefs.getBool('onboarding_completed') ?? false;
    // Backwards compat: also check old key from launch_dialog.dart
    final oldDialogAsked = prefs.getBool('launch_at_login_asked') ?? false;

    if (wizardCompleted || oldDialogAsked || !isDefault) return;
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardingWizard(
        onComplete: () {
          ref.invalidate(watcherProvider);
          ref.invalidate(projectsProvider);
        },
      ),
    );

    await prefs.setBool('onboarding_completed', true);
    await prefs.setBool('launch_at_login_asked', true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _trayService.dispose();
    super.dispose();
  }

  // WindowListener overrides

  @override
  void onWindowClose() async {
    await windowManager.hide();
    await widget.activationPolicyService.setAccessory();
  }

  @override
  void onWindowMove() {
    _geometryService.save();
  }

  @override
  void onWindowResize() {
    _geometryService.save();
  }

  /// Tab selection handler used by [_SideNav]. Switching tabs while a
  /// project detail view is open closes that view (returns to the normal
  /// `IndexedStack`) and switches tab in one step.
  void _onSelectTab(int index) {
    setState(() {
      _selectedIndex = index;
      ref.read(openProjectDetailProvider.notifier).close();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep projectsProvider alive for the reactive watcher chain.
    // Unused local variable intentional — provider must be watched.
    ref.watch(projectsProvider);

    // 010-vault-status-writer Wave 5: fire the automatic vault-sync trigger
    // on every new resolved project list. `ref.listen` (not `ref.watch`) so
    // this fires exactly once per new list rather than re-running the whole
    // ShellScreen build for every emission-that-hasn't-actually-changed —
    // consistent with projectsProvider's own value-equality-aware
    // ProjectModel comparisons upstream (2026-08-20 process-storm fix). Each
    // project's syncIfDue() call is independently fire-and-forget
    // (unawaited) rather than sequentially awaited, so one slow/stuck write
    // never blocks the others — Wave 3's per-project in-flight Set already
    // handles overlap safety if a tick fires again before a prior write for
    // the same project finishes.
    //
    // N-5 fix (review re-round nit): `membership` is already read once
    // below and used both to skip the syncIfDue() call for Archiv projects
    // AND to pass the known archived status into syncIfDue's `isArchived`
    // parameter — previously syncIfDue() still ran its own `_isArchived` DB
    // query internally for every non-Archiv project despite the caller
    // already knowing the answer, i.e. ~90 redundant queries per watcher
    // tick at real-world project counts (the exact fan-out shape the
    // 2026-08-20 process-storm postmortem warns against).
    ref.listen(projectsProvider, (previous, next) {
      final projects = next.value;
      if (projects == null) return;
      final membership = ref.read(membershipProvider);
      final notifier = ref.read(vaultStatusProvider.notifier);
      for (final project in projects) {
        final isArchived = membership[project.folderId] == kArchiveGroupId;
        if (isArchived) continue;
        unawaited(notifier.syncIfDue(project, isArchived: isArchived));
      }
    });

    final colors = Theme.of(context).extension<AppColors>()!;
    final openProject = ref.watch(openProjectDetailProvider);

    if (openProject != null) {
      // Remember which tab was active so "back" returns there instead of
      // hard-jumping to index 0. Recorded here (not in the setter) because
      // the provider can also be set from card onTap callbacks in the tabs
      // themselves, outside of this widget's control.
      _tabIndexBeforeDetail = _selectedIndex;
    }

    return GlowBorderShell(
      child: Stack(
        children: [
          const Positioned.fill(child: OrbBackground()),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Row(
                children: [
                  _SideNav(
                    selectedIndex: _selectedIndex,
                    onSelect: _onSelectTab,
                    colors: colors,
                  ),
                  Expanded(
                    child: openProject != null
                        ? ProjectDetailPanel(
                            key: ValueKey(openProject.folderId),
                            project: openProject,
                            onBack: () {
                              ref
                                  .read(openProjectDetailProvider.notifier)
                                  .close();
                              setState(
                                () => _selectedIndex = _tabIndexBeforeDetail,
                              );
                            },
                          )
                        : IndexedStack(
                            index: _selectedIndex,
                            children: const [
                              ProjectsTab(),
                              ClaudeToolsTab(),
                              AgentsTab(),
                              SkillsTab(),
                              HarnessTab(),
                              LearningTab(),
                              SettingsTab(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom side navigation — full control over icon weight and text style
// ---------------------------------------------------------------------------

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.selectedIndex,
    required this.onSelect,
    required this.colors,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AppColors colors;

  static const _items = <({IconData icon, String label})>[
    (icon: LucideIcons.folderKanban100, label: 'Projekte'),
    (icon: LucideIcons.brain100, label: 'Tools'),
    (icon: LucideIcons.bot100, label: 'Agents'),
    (icon: LucideIcons.sparkles100, label: 'Skills'),
    (icon: LucideIcons.slidersHorizontal100, label: 'Harness'),
    (icon: LucideIcons.graduationCap100, label: 'Learning'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Image.asset(
              'assets/images/tray_icon.png',
              width: 24,
              height: 24,
              color: colors.cyan.withValues(alpha: 0.6),
            ),
          ),
          // Nav items
          for (int i = 0; i < _items.length; i++)
            _NavItem(
              icon: _items[i].icon,
              label: _items[i].label,
              selected: selectedIndex == i,
              accent: colors.cyan,
              dimColor: colors.textDim,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          // Settings
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _NavItem(
              icon: LucideIcons.settings100,
              label: 'Settings',
              selected: selectedIndex == _items.length,
              accent: colors.cyan,
              dimColor: colors.textDim,
              onTap: () => onSelect(_items.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.dimColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color dimColor;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    final color = active ? widget.accent : widget.dimColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 68,
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: color, size: 22),
              if (widget.selected) ...[
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
