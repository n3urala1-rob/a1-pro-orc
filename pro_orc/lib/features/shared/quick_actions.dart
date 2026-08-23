import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/services/quick_actions_service.dart';
import 'package:pro_orc/data/services/vault_status_writer.dart'
    show VaultWriteResult;
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Shared action definition for quick action buttons.
class QuickAction {
  const QuickAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.disabled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// True while this action is visibly (not merely functionally) disabled —
  /// e.g. a vault sync write already in flight for this project (FR-014).
  /// [buildQuickActionRow] renders a dimmed icon and passes `onPressed:
  /// null` to the underlying [IconButton] when true.
  final bool disabled;
}

/// Builds the standard quick action list for a project card.
///
/// [ref] is required (not optional) so the "Jetzt synchronisieren" action
/// (FR-014) can `ref.watch(vaultStatusProvider)` for this project's
/// disabled-while-syncing state and `ref.read(vaultStatusProvider.notifier)`
/// to fire `syncNow` — both call sites (`project_card.dart`,
/// `quick_actions_section.dart`) already build inside a `Consumer*` widget.
/// [context] is required so the sync action can surface feedback via
/// [ScaffoldMessenger] (M-5, review round 1): previously the button's tap
/// silently discarded `syncNow`'s result, so a project stuck in
/// "needs confirmation" (an unconfirmed fuzzy-match candidate) gave the
/// user zero explanation for why nothing happened.
List<QuickAction> buildProjectQuickActions(
  ProjectModel project,
  QuickActionsService qa,
  WidgetRef ref,
  BuildContext context,
) {
  // Archiv-group projects get no vault activity of any kind (FR-013) — the
  // action is omitted entirely rather than shown-but-disabled, since a
  // permanently-excluded state is not something the user can ever unblock
  // by waiting (unlike the in-flight disabled state), so a visible button
  // would just be confusing (spec Dependencies + Wave 4 brief).
  final membership = ref.watch(membershipProvider);
  final isArchived = membership[project.folderId] == kArchiveGroupId;

  return [
    QuickAction(
      icon: LucideIcons.folder100,
      tooltip: 'Finder',
      onPressed: () => qa.openInFinder(project.path),
    ),
    if (project.git?.githubUrl != null)
      QuickAction(
        icon: LucideIcons.externalLink100,
        tooltip: 'GitHub',
        onPressed: () => qa.openUrl(project.git!.githubUrl!),
      ),
    if (project.memory != null)
      QuickAction(
        icon: LucideIcons.moonStar100,
        tooltip: 'Claude Memory',
        onPressed: () => qa.openRemSleep(project.path),
      ),
    if (!isArchived)
      QuickAction(
        icon: LucideIcons.refreshCw100,
        tooltip: 'Jetzt synchronisieren',
        disabled: ref.watch(
          vaultStatusProvider.select((s) => s.contains(project.folderId)),
        ),
        onPressed: () => _syncNowWithFeedback(ref, context, project),
      ),
  ];
}

/// Fires `syncNow` and surfaces a snackbar for outcomes the user needs an
/// explanation for (M-5): a pending fuzzy-match confirmation (routes them
/// to the settings dialog) or a soft I/O failure. A successful write or the
/// unremarkable "already in flight"/archived cases show nothing — those are
/// either self-evident (the button re-enables) or don't need interrupting
/// the user.
void _syncNowWithFeedback(
  WidgetRef ref,
  BuildContext context,
  ProjectModel project,
) {
  unawaited(
    ref.read(vaultStatusProvider.notifier).syncNow(project).then((outcome) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      if (outcome.isNeedsConfirmation) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Zuordnung bestätigen — öffne Einstellungen → Vault-Sync, '
              'um den vorgeschlagenen Hub zu bestätigen.',
            ),
          ),
        );
        return;
      }

      final result = outcome.writeResult;
      if (result == VaultWriteResult.skippedIoError ||
          result == VaultWriteResult.skippedLocked ||
          result == VaultWriteResult.skippedOutsideRoot) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Synchronisierung fehlgeschlagen — Vault nicht erreichbar.',
            ),
          ),
        );
      }
    }),
  );
}

/// Builds a row of compact icon-only quick action buttons (for cards).
Widget buildQuickActionRow(List<QuickAction> actions, AppColors colors) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.start,
    children: actions
        .map(
          (a) => SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 15,
              icon: Icon(
                a.icon,
                color: a.disabled
                    ? colors.textDim.withValues(alpha: 0.35)
                    : colors.textDim,
              ),
              tooltip: a.tooltip,
              splashRadius: 16,
              onPressed: a.disabled ? null : a.onPressed,
            ),
          ),
        )
        .toList(),
  );
}
