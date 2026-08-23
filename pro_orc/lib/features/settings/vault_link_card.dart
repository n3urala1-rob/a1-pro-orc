import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/features/shared/vault_link_confirmation_dialog.dart';
import 'package:pro_orc/providers/vault_link_statuses_provider.dart';
import 'package:pro_orc/theme/n3_colors.dart';

/// Expandable "Vault-Sync" status card for the settings tab (FR-003,
/// Surface 1 Variant V2 of `docs/design/vault-sync-mockups.html`).
///
/// Collapsed: "N von M verknüpft" summary line + progress bar. Expanded:
/// per-project link-state list (linked / pending confirmation /
/// will-auto-create) plus a button opening [VaultLinkConfirmationDialog]
/// when at least one project needs a decision.
class VaultLinkCard extends ConsumerStatefulWidget {
  const VaultLinkCard({super.key});

  @override
  ConsumerState<VaultLinkCard> createState() => _VaultLinkCardState();
}

class _VaultLinkCardState extends ConsumerState<VaultLinkCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final counts = ref.watch(vaultLinkCountsProvider);
    final statusesAsync = ref.watch(vaultLinkStatusesProvider);
    final pending = ref.watch(vaultPendingLinksProvider);

    final ratio = counts.total == 0 ? 0.0 : counts.linked / counts.total;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: TextStyle(color: colors.textSec, fontSize: 12),
                          children: [
                            TextSpan(
                              text: '${counts.linked} von ${counts.total}',
                              style: TextStyle(
                                color: colors.textPri,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const TextSpan(text: ' Projekten verknüpft'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 5,
                          width: 180,
                          color: colors.bgElev.withValues(alpha: 0.6),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: ratio.clamp(0.0, 1.0),
                            child: Container(color: colors.cyan),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? LucideIcons.chevronUp100
                      : LucideIcons.chevronDown100,
                  color: colors.textDim,
                  size: 16,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: colors.textDim.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                child: switch (statusesAsync) {
                  AsyncData(:final value) when value.isEmpty => Text(
                    'Keine Projekte gefunden.',
                    style: TextStyle(color: colors.textDim, fontSize: 12),
                  ),
                  AsyncData(:final value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final status in value.take(5))
                        _LinkRow(status: status, colors: colors),
                      if (pending.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: TextButton(
                            onPressed: () =>
                                VaultLinkConfirmationDialog.show(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              '${pending.length} Zuordnung${pending.length == 1 ? '' : 'en'} bestätigen →',
                              style: TextStyle(
                                color: colors.cyan,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  AsyncError() => Text(
                    'Zuordnungen konnten nicht geladen werden.',
                    style: TextStyle(color: colors.amber, fontSize: 12),
                  ),
                  _ => SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.cyan,
                    ),
                  ),
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.status, required this.colors});

  final VaultLinkStatus status;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final (pillIcon, pillColor, trailing) = switch (status.kind) {
      VaultLinkKind.linked => (
        LucideIcons.check100,
        colors.emeraldHi,
        'project/${status.hubSlug}.md',
      ),
      VaultLinkKind.pendingSuggestion => (
        LucideIcons.circleQuestionMark100,
        colors.amberHi,
        '${((status.confidence ?? 0) * 100).round()}% Übereinstimmung',
      ),
      VaultLinkKind.willAutoCreate => (
        LucideIcons.circleQuestionMark100,
        colors.amberHi,
        'wird neu angelegt',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              status.displayName,
              style: TextStyle(color: colors.textPri, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(LucideIcons.arrowRight100, color: colors.textDim, size: 11),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              trailing,
              style: TextStyle(
                color: status.kind == VaultLinkKind.linked
                    ? colors.cyan
                    : colors.violetHi,
                fontSize: 11,
                fontFamily: 'SF Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Icon(pillIcon, color: pillColor, size: 13),
        ],
      ),
    );
  }
}
