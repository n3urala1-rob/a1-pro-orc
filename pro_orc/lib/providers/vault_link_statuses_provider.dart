import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pro_orc/data/db/tables/project_groups_table.dart'
    show kArchiveGroupId;
import 'package:pro_orc/data/models/vault_link_status.dart';
import 'package:pro_orc/providers/project_group_membership_provider.dart';
import 'package:pro_orc/providers/projects_provider.dart';
import 'package:pro_orc/providers/vault_status_provider.dart';

/// Per-project vault-link status for every ELIGIBLE (non-Archiv) project —
/// backs the Vault-Sync settings card's "N von M verknüpft" summary (FR-003)
/// and the batch confirmation dialog's row list (FR-004).
///
/// Archiv-group projects are filtered out before status is even computed
/// (FR-013: no vault activity of any kind), so they never appear as
/// "pending" here even though they technically have no confirmed link.
final vaultLinkStatusesProvider = FutureProvider<List<VaultLinkStatus>>((
  ref,
) async {
  final projects = await ref.watch(projectsProvider.future);
  final membership = ref.watch(membershipProvider);
  final notifier = ref.watch(vaultStatusProvider.notifier);

  final eligible = projects.where(
    (p) => membership[p.folderId] != kArchiveGroupId,
  );

  final statuses = <VaultLinkStatus>[];
  for (final project in eligible) {
    statuses.add(await notifier.linkStatusFor(project));
  }
  return statuses;
});

/// Derived counts for the settings card's "N von M verknüpft" summary.
class VaultLinkCounts {
  final int linked;
  final int total;

  const VaultLinkCounts({required this.linked, required this.total});
}

final vaultLinkCountsProvider = Provider<VaultLinkCounts>((ref) {
  final statuses = ref.watch(vaultLinkStatusesProvider).value ?? const [];
  final linked = statuses.where((s) => s.kind == VaultLinkKind.linked).length;
  return VaultLinkCounts(linked: linked, total: statuses.length);
});

/// Projects still needing a confirmation decision — feeds the batch dialog
/// (FR-004). Includes both fuzzy-match suggestions and no-candidate
/// auto-create previews (the dialog renders the latter as a dismiss-only
/// informational row per the mockup, not an Accept/Reject choice).
final vaultPendingLinksProvider = Provider<List<VaultLinkStatus>>((ref) {
  final statuses = ref.watch(vaultLinkStatusesProvider).value ?? const [];
  return statuses.where((s) => s.kind != VaultLinkKind.linked).toList();
});
