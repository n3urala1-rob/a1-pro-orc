import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/quick_actions_service.dart';
import 'package:pro_orc/features/shared/quick_actions.dart';
import 'package:pro_orc/features/shared/skill_launcher_dialog.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Renders the quick-action button row at the bottom of
/// [ProjectDetailPanel]'s "Übersicht" tab.
///
/// `ConsumerWidget` (not `StatelessWidget`) so the "Jetzt synchronisieren"
/// action's disabled-while-syncing state (FR-014, via
/// `buildProjectQuickActions`'s `ref.watch(vaultStatusProvider)`) rebuilds
/// this row when a write starts/finishes for [project].
class QuickActionsSection extends ConsumerWidget {
  const QuickActionsSection({
    super.key,
    required this.project,
    required this.colors,
    required this.accent,
    required this.qa,
  });

  final ProjectModel project;
  final AppColors colors;
  final Color accent;
  final QuickActionsService qa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      ...buildProjectQuickActions(project, qa, ref, context),
      QuickAction(
        icon: LucideIcons.sparkles100,
        tooltip: 'Mit Skill starten',
        onPressed: () => SkillLauncherDialog.show(
          context,
          projectPath: project.path,
          projectName: project.displayName,
        ),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: actions
          .map(
            (a) =>
                _QuickActionButton(action: a, accent: accent, colors: colors),
          )
          .toList(),
    );
  }
}

/// Quick action button with icon + label.
class _QuickActionButton extends StatefulWidget {
  const _QuickActionButton({
    required this.action,
    required this.accent,
    required this.colors,
  });

  final QuickAction action;
  final Color accent;
  final AppColors colors;

  @override
  State<_QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<_QuickActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.action.disabled;
    final iconColor = disabled
        ? widget.colors.textDim.withValues(alpha: 0.35)
        : (_hovered ? widget.accent : widget.colors.textDim);
    final labelColor = disabled
        ? widget.colors.textDim.withValues(alpha: 0.35)
        : (_hovered ? widget.accent : widget.colors.textDim);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: disabled ? null : widget.action.onPressed,
          child: Container(
            width: 64,
            height: 52,
            decoration: BoxDecoration(
              color: !disabled && _hovered
                  ? widget.accent.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.action.icon, color: iconColor, size: 18),
                const SizedBox(height: 4),
                Text(
                  widget.action.tooltip,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
