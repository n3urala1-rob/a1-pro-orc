class GitData {
  final String? lastCommitMessage;
  final String? lastCommitHash; // 7-char short SHA
  final DateTime? lastCommitDate;
  final String? githubUrl; // https://github.com/owner/repo

  const GitData({
    this.lastCommitMessage,
    this.lastCommitHash,
    this.lastCommitDate,
    this.githubUrl,
  });

  static const empty = GitData();

  bool get isEmpty =>
      lastCommitMessage == null &&
      lastCommitHash == null &&
      lastCommitDate == null &&
      githubUrl == null;

  /// Value equality — required so [ProjectModel]'s own value equality (used
  /// as a `FutureProvider.family` key by externalResourcesProvider,
  /// visionProvider, roadmapProvider) correctly detects when a project's git
  /// state changed between rescans, not just when its identity changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GitData &&
          lastCommitMessage == other.lastCommitMessage &&
          lastCommitHash == other.lastCommitHash &&
          lastCommitDate == other.lastCommitDate &&
          githubUrl == other.githubUrl);

  @override
  int get hashCode =>
      Object.hash(lastCommitMessage, lastCommitHash, lastCommitDate, githubUrl);
}
