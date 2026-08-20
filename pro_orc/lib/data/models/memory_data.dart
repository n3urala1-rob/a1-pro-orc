class MemoryData {
  final bool hasMemory;
  final DateTime? lastConsolidated;
  final bool isStale;

  const MemoryData({
    this.hasMemory = false,
    this.lastConsolidated,
    this.isStale = false,
  });

  static const empty = MemoryData();

  /// Value equality — see [GitData.operator==] for why this matters for
  /// [ProjectModel]'s own equality.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryData &&
          hasMemory == other.hasMemory &&
          lastConsolidated == other.lastConsolidated &&
          isStale == other.isStale);

  @override
  int get hashCode => Object.hash(hasMemory, lastConsolidated, isStale);
}
