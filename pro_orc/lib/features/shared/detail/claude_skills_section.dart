import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/db/app_database.dart' show SkillRunTableData;
import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/features/shared/skill_run_result_dialog.dart';
import 'package:pro_orc/features/shell/glass_card.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/skill_run_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// One curated skill this section can launch — a fixed, code-owned
/// constant, not user-configurable (spec 011 FR-001: no UI to add, remove,
/// or reorder this set in this version).
class CuratedSkill {
  const CuratedSkill({
    required this.id,
    required this.displayName,
    required this.prompt,
    required this.icon,
  });

  final String id;
  final String displayName;

  /// The prompt text passed to `claude -p` for this skill.
  final String prompt;
  final IconData icon;
}

/// Planning-phase decision (wave plan brief): exactly these two curated
/// skills, both read-only status checks — a1-progress (checkpoint status
/// for the project) and a1-checklist (readiness check).
const List<CuratedSkill> kCuratedSkills = [
  CuratedSkill(
    id: 'a1-progress',
    displayName: 'a1-progress',
    prompt: '/a1-progress',
    icon: LucideIcons.chartBar100,
  ),
  CuratedSkill(
    id: 'a1-checklist',
    displayName: 'Checkpoint',
    prompt: '/a1-checklist',
    icon: LucideIcons.clipboardCheck100,
  ),
];

/// The "Claude-Skills" GlassCard section (spec 011 FR-001/FR-005), placed
/// in the Detail Panel's Vision tab immediately below the existing
/// [QuickActionsSection] row — a structurally separate section, never
/// additional entries within that row (Robert's approved Variant V2,
/// `docs/design/skill-buttons-mockups.html`).
///
/// Hidden entirely for a project in the "Archiv" group (FR-020/SC-010) —
/// simplest and consistent with [buildProjectQuickActions]'s own
/// Archiv-gated precedent (omitted, not shown-disabled).
class ClaudeSkillsSection extends ConsumerWidget {
  const ClaudeSkillsSection({
    super.key,
    required this.project,
    required this.colors,
  });

  final ProjectModel project;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(membershipProvider);
    final isArchived = membership[project.folderId] == kArchiveGroupId;
    if (isArchived) return const SizedBox.shrink();

    final runState = ref.watch(skillRunProvider);
    final accent = colors.amber;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles100, color: accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Claude-Skills',
                  style: TextStyle(
                    color: colors.textPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '— kostet Zeit & Budget',
                    style: TextStyle(color: colors.textDim, fontSize: 10.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kCuratedSkills
                  .map(
                    (skill) => _SkillButton(
                      project: project,
                      skill: skill,
                      colors: colors,
                      runState: runState,
                    ),
                  )
                  .toList(),
            ),
            for (final skill in kCuratedSkills)
              _SkillStatusRow(project: project, skill: skill, colors: colors),
          ],
        ),
      ),
    );
  }
}

/// The 64×52px skill button tile — same footprint as
/// [QuickActionsSection]'s icon buttons, but with the amber accent border
/// the mockup reserves for "this costs time/budget" actions. Idle → tap
/// starts immediately (FR-003, no confirmation dialog); running (any skill
/// for this project) → this button shows its own spinner if it's the one
/// running, or a dimmed "blocked" state if a different skill in the same
/// section is running (per-project concurrency limit is 1, reflected
/// honestly in the UI rather than relying only on the silent rejection).
class _SkillButton extends ConsumerWidget {
  const _SkillButton({
    required this.project,
    required this.skill,
    required this.colors,
    required this.runState,
  });

  final ProjectModel project;
  final CuratedSkill skill;
  final AppColors colors;
  final SkillRunState runState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = skillRunKey(project.folderId, skill.id);
    final thisRunning = runState.inFlightKeys.contains(key);
    final anyRunningForProject = runState.inFlightKeys.any(
      (k) => k.startsWith('${project.folderId}:'),
    );
    final blocked = anyRunningForProject && !thisRunning;

    final accent = colors.amber;
    final borderColor = thisRunning
        ? colors.cyanHi.withValues(alpha: 0.4)
        : accent.withValues(alpha: 0.28);
    final bgColor = thisRunning
        ? colors.cyanHi.withValues(alpha: 0.08)
        : accent.withValues(alpha: 0.06);
    final contentColor = blocked
        ? colors.textDim.withValues(alpha: 0.4)
        : (thisRunning ? colors.cyanHi : accent);

    return Semantics(
      button: true,
      enabled: !blocked,
      label: thisRunning ? '${skill.displayName} läuft' : skill.displayName,
      child: MouseRegion(
        cursor: blocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: blocked
              ? null
              : () => _handleTap(context, ref, thisRunning: thisRunning),
          child: Container(
            constraints: const BoxConstraints(minWidth: 88, minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
              color: bgColor,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thisRunning)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.cyanHi,
                    ),
                  )
                else
                  Icon(skill.icon, color: contentColor, size: 15),
                const SizedBox(height: 4),
                Text(
                  skill.displayName,
                  style: TextStyle(
                    color: contentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref, {
    required bool thisRunning,
  }) {
    // FR-003: a repeated tap on an already-running skill is a no-op at the
    // UI layer — the concurrency limiter is the authoritative guard, this
    // is just the accidental-double-click affordance.
    if (thisRunning) return;

    // Await + surface non-started outcomes (mirrors quick_actions.dart's
    // `_syncNowWithFeedback` M-5 precedent) — the Future and its
    // StartSkillOutcome were previously discarded entirely, so a rejected
    // or failed start looked identical to a successful one: nothing
    // happened and the user got no explanation.
    unawaited(
      ref
          .read(skillRunProvider.notifier)
          .start(project, skill.id, skill.prompt)
          .then((result) {
            if (!context.mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            if (messenger == null) return;

            final message = switch (result.outcome) {
              StartSkillOutcome.started => null,
              StartSkillOutcome.rejectedConcurrencyLimit =>
                'Bereits 2 Läufe aktiv — bitte warten, bis ein Lauf fertig ist.',
              StartSkillOutcome.claudeNotAvailable =>
                'Claude CLI nicht gefunden — bitte installieren und auf dem '
                    'PATH verfügbar machen.',
              StartSkillOutcome.spawnFailed =>
                'Start fehlgeschlagen — der Skill konnte nicht gestartet '
                    'werden.',
            };
            if (message == null) return;

            messenger.showSnackBar(SnackBar(content: Text(message)));
          }),
    );
  }
}

/// The permanently visible per-skill status line below the button row
/// (FR-005/FR-021): idle → "noch nicht ausgeführt"; running → elapsed
/// context + a functional "Abbrechen" button; terminal → "zuletzt gelaufen"
/// with the time and status, tappable to open [SkillRunResultDialog].
class _SkillStatusRow extends ConsumerWidget {
  const _SkillStatusRow({
    required this.project,
    required this.skill,
    required this.colors,
  });

  final ProjectModel project;
  final CuratedSkill skill;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = skillRunKey(project.folderId, skill.id);
    final runState = ref.watch(skillRunProvider);
    final running = runState.inFlightKeys.contains(key);
    final lastRun = runState.lastRunByKey[key];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (!running && lastRun != null)
                  ? () => SkillRunResultDialog.show(
                      context,
                      skill: skill,
                      project: project,
                      row: lastRun,
                    )
                  : null,
              child: Text(
                _statusLabel(running: running, lastRun: lastRun),
                style: TextStyle(
                  color: _statusColor(running: running, lastRun: lastRun),
                  fontSize: 11,
                  decoration: (!running && lastRun != null)
                      ? TextDecoration.underline
                      : null,
                  decorationColor: colors.textDim,
                ),
              ),
            ),
          ),
          if (running)
            TextButton(
              onPressed: () => ref
                  .read(skillRunProvider.notifier)
                  .cancel(project.folderId, skill.id),
              style: TextButton.styleFrom(
                foregroundColor: colors.textPri,
                backgroundColor: const Color(
                  0xFFF04444,
                ).withValues(alpha: 0.12),
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text(
                'Abbrechen',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel({required bool running, SkillRunTableData? lastRun}) {
    if (running) return '${skill.displayName} läuft…';
    if (lastRun == null) {
      return '${skill.displayName}: noch nicht ausgeführt';
    }
    final outcome = _germanStatus(lastRun.status);
    final time = _relativeTime(lastRun.completedAt ?? lastRun.startedAt);
    return '${skill.displayName}: zuletzt gelaufen $time — $outcome';
  }

  Color _statusColor({required bool running, SkillRunTableData? lastRun}) {
    if (running) return colors.cyanHi;
    if (lastRun == null) return colors.textDim;
    switch (lastRun.status) {
      case 'success':
        return colors.emeraldHi;
      case 'failure':
      case 'timeout':
        return const Color(0xFFFF6B6B);
      case 'cancelled':
        return colors.textDim;
      default:
        return colors.textDim;
    }
  }

  String _germanStatus(String status) {
    switch (status) {
      case 'success':
        return 'erfolgreich';
      case 'failure':
        return 'fehlgeschlagen';
      case 'timeout':
        return 'Zeitüberschreitung';
      case 'cancelled':
        return 'abgebrochen';
      default:
        return status;
    }
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
    return 'vor ${diff.inDays} Tagen';
  }
}
