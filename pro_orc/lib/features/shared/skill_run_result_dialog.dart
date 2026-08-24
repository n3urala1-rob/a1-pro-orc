import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/db/app_database.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/features/shared/detail/claude_skills_section.dart'
    show CuratedSkill;
import 'package:pro_orc/features/shell/glass_dialog.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Modal result/error viewer for a completed headless skill run (spec 011
/// FR-012/FR-016) — reuses the project's established [GlassDialog] shape
/// (see [SkillLauncherDialog] for the header-with-close-button precedent).
/// Success and failure/timeout/cancelled share this ONE dialog shape,
/// differing only in the outcome label/color and the content substituted
/// in — no separate failure-only widget exists.
class SkillRunResultDialog extends StatefulWidget {
  const SkillRunResultDialog({
    super.key,
    required this.skill,
    required this.project,
    required this.row,
  });

  final CuratedSkill skill;
  final ProjectModel project;
  final SkillRunTableData row;

  static Future<void> show(
    BuildContext context, {
    required CuratedSkill skill,
    required ProjectModel project,
    required SkillRunTableData row,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          SkillRunResultDialog(skill: skill, project: project, row: row),
    );
  }

  @override
  State<SkillRunResultDialog> createState() => _SkillRunResultDialogState();
}

class _SkillRunResultDialogState extends State<SkillRunResultDialog> {
  String? _content;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    String? content;
    try {
      final file = File(widget.row.outputFilePath);
      if (await file.exists()) {
        content = await file.readAsString();
      }
    } catch (_) {
      // Swallowed — an unreadable output file renders as "kein Inhalt
      // verfügbar" below, never a crash.
    }
    if (mounted) {
      setState(() {
        _content = content;
        _loading = false;
      });
    }
  }

  bool get _isSuccess => widget.row.status == 'success';

  Color _outcomeColor(AppColors colors) {
    switch (widget.row.status) {
      case 'success':
        return colors.emeraldHi;
      case 'cancelled':
        return colors.textDim;
      default:
        return const Color(0xFFFF6B6B);
    }
  }

  String _outcomeLabel() {
    switch (widget.row.status) {
      case 'success':
        return 'erfolgreich';
      case 'failure':
        return 'fehlgeschlagen';
      case 'timeout':
        return 'Zeitüberschreitung';
      case 'cancelled':
        return 'abgebrochen';
      default:
        return widget.row.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final outcomeColor = _outcomeColor(colors);
    final completedAt = widget.row.completedAt;

    return GlassDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isSuccess
                    ? LucideIcons.circleCheck100
                    : LucideIcons.circleAlert100,
                color: outcomeColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.skill.displayName} — Ergebnis',
                  style: TextStyle(
                    color: colors.textPri,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.x100, color: colors.textDim, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.project.displayName} · '
            '${completedAt != null ? _formatDateTime(completedAt) : 'läuft'} · '
            '${_outcomeLabel()}',
            style: TextStyle(color: colors.textSec, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _buildOutputBlock(colors),
        ],
      ),
    );
  }

  Widget _buildOutputBlock(AppColors colors) {
    if (_loading) {
      return SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: colors.amber)),
      );
    }

    final content = _content;
    if (content == null || content.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Kein Inhalt verfügbar',
            style: TextStyle(color: colors.textDim, fontSize: 12),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: colors.bgElev.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: TextStyle(
            color: colors.textSec,
            fontSize: 11.5,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(local.day)}.${pad(local.month)}. ${pad(local.hour)}:${pad(local.minute)}';
  }
}
