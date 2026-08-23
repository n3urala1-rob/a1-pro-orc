import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/features/shell/glass_dialog.dart';
import 'package:pro_orc/providers/database_provider.dart';
import 'package:pro_orc/providers/vault_link_statuses_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Batch confirmation dialog for pending vault-hub links (FR-004, Surface 2
/// Variant V2 of `docs/design/vault-sync-mockups.html`).
///
/// One row per project needing a decision: a fuzzy-match suggestion shows
/// the candidate hub + confidence percentage; a no-candidate project shows
/// the static "wird neu angelegt: project/`<slug>`.md" text instead (auto-
/// create is not a choice — it's the writer's fallback behavior, so that
/// row has no Accept/Reject, only an implicit "OK" via the batch footer).
/// Per-row Accept persists immediately via `setVaultHubSlug`; Reject leaves
/// the project unlinked (re-offered next time the dialog opens, per FR-002's
/// "one-time" wording applying only to an ACCEPTED link, not a rejected one).
class VaultLinkConfirmationDialog extends ConsumerStatefulWidget {
  const VaultLinkConfirmationDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VaultLinkConfirmationDialog(),
    );
  }

  @override
  ConsumerState<VaultLinkConfirmationDialog> createState() =>
      _VaultLinkConfirmationDialogState();
}

class _VaultLinkConfirmationDialogState
    extends ConsumerState<VaultLinkConfirmationDialog> {
  /// Rows accepted this session but not yet persisted — batched until the
  /// footer's "Alle N bestätigen" is pressed, matching the mockup's "einmalig
  /// bestätigen, danach automatisch" framing (a single confirming action for
  /// the whole batch, not one DB write per row click).
  final Set<String> _accepted = {};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final pending = ref.watch(vaultPendingLinksProvider);

    return GlassDialog(
      maxWidth: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vault-Zuordnungen bestätigen',
            style: TextStyle(
              color: colors.textPri,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pending.length} offene Vorschläge · einmalig bestätigen, danach automatisch',
            style: TextStyle(color: colors.textDim, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          if (pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Keine offenen Zuordnungen.',
                style: TextStyle(color: colors.textSec, fontSize: 13),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final status in pending)
                      _MatchRow(
                        status: status,
                        accepted: _accepted.contains(status.folderId),
                        onAccept: () =>
                            setState(() => _accepted.add(status.folderId)),
                        onReject: () =>
                            setState(() => _accepted.remove(status.folderId)),
                        colors: colors,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(
                  'Schließen',
                  style: TextStyle(color: colors.textSec, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_saving || pending.isEmpty)
                    ? null
                    : () => _confirmBatch(pending),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.cyan,
                  foregroundColor: colors.bgBase,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text('Alle ${pending.length} bestätigen'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Persists every accepted [VaultLinkKind.pendingSuggestion] row's
  /// suggested slug via `setVaultHubSlug`, and does nothing for rejected
  /// rows (they simply stay unlinked and are re-offered next time) or
  /// [VaultLinkKind.willAutoCreate] rows (auto-create needs no persisted
  /// link — the writer resolves it fresh on each write).
  Future<void> _confirmBatch(List<VaultLinkStatus> pending) async {
    setState(() => _saving = true);
    final db = ref.read(appDatabaseProvider);
    try {
      for (final status in pending) {
        if (status.kind != VaultLinkKind.pendingSuggestion) continue;
        if (!_accepted.contains(status.folderId)) continue;
        await db.setVaultHubSlug(status.folderId, status.hubSlug);
      }
      ref.invalidate(vaultLinkStatusesProvider);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.status,
    required this.accepted,
    required this.onAccept,
    required this.onReject,
    required this.colors,
  });

  final VaultLinkStatus status;
  final bool accepted;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isNoMatch = status.kind == VaultLinkKind.willAutoCreate;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colors.bgElev.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isNoMatch ? colors.violet : colors.emerald,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.displayName,
                  style: TextStyle(
                    color: colors.textPri,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isNoMatch
                      ? 'wird neu angelegt: project/${status.folderId}.md'
                      : '→ project/${status.hubSlug}.md',
                  style: TextStyle(
                    color: colors.textDim,
                    fontSize: 11,
                    fontFamily: 'SF Mono',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!isNoMatch)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.emerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${((status.confidence ?? 0) * 100).round()}%',
                style: TextStyle(
                  color: colors.emeraldHi,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.violet.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Neu',
                style: TextStyle(
                  color: colors.violetHi,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!isNoMatch) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 14,
                tooltip: accepted ? 'Akzeptiert' : 'Akzeptieren',
                icon: Icon(
                  LucideIcons.check100,
                  color: accepted ? colors.emeraldHi : colors.textDim,
                ),
                onPressed: accepted ? onReject : onAccept,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
