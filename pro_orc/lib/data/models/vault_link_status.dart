/// One project's vault-hub link state, computed for the Vault-Sync
/// settings card (FR-003) and batch confirmation dialog (FR-004).
enum VaultLinkKind {
  /// A confirmed `vaultHubSlug` already exists — no action needed.
  linked,

  /// No confirmed link, but [VaultLinkStatus.suggestedHubSlug] cleared the
  /// fuzzy-match threshold — needs one-time user confirmation.
  pendingSuggestion,

  /// No confirmed link and no fuzzy candidate — will auto-create a new hub
  /// using the project's own folderId on the next write.
  willAutoCreate,
}

/// Per-project vault-link status, eligible-only (Archiv-group projects are
/// filtered out by the provider before this model is built — FR-013: they
/// have no vault activity of any kind, so they are not even "pending").
class VaultLinkStatus {
  final String folderId;
  final String displayName;
  final VaultLinkKind kind;

  /// The confirmed hub slug ([VaultLinkKind.linked]) or the fuzzy-match
  /// suggestion ([VaultLinkKind.pendingSuggestion]); null for
  /// [VaultLinkKind.willAutoCreate].
  final String? hubSlug;

  /// Normalized Levenshtein similarity (0.0-1.0) for a
  /// [VaultLinkKind.pendingSuggestion] row's confidence badge; null
  /// otherwise.
  final double? confidence;

  const VaultLinkStatus({
    required this.folderId,
    required this.displayName,
    required this.kind,
    this.hubSlug,
    this.confidence,
  });
}
