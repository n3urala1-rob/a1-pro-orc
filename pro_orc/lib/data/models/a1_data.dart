/// Immutable models for the a1 roadmap/phase status of a project (M6 Wave 2).
///
/// a1 is the successor planning format to GSD. Where GSD lived in `.planning/`,
/// a1 lives in `.a1/`:
///   - `.a1/roadmap.md` — a milestone table (Milestone | Inhalt | Status).
///   - `.a1/phases/<name>/PLAN.md` — wave/task checkboxes (`- [x]` / `- [ ]`).
///
/// All read-only; the app never writes into `.a1/`.
library;

/// One milestone row from `.a1/roadmap.md`.
class A1Milestone {
  /// Milestone name (first table column), e.g. `M6 — Selbstlernendes OS`.
  final String name;

  /// Raw status text from the status column, e.g. `done (2026-07-05)` or
  /// `in_progress`.
  final String status;

  const A1Milestone({required this.name, required this.status});

  /// True when the status text indicates completion.
  bool get isDone => RegExp(
    r'\bdone\b|abgeschlossen|complete|shipped',
    caseSensitive: false,
  ).hasMatch(status);

  /// True when the status text indicates active work.
  bool get isActive => RegExp(
    r'in[_ -]?progress|building|wip|läuft|aktiv',
    caseSensitive: false,
  ).hasMatch(status);

  /// Value equality — see `GitData.operator==` for why this matters for
  /// `ProjectModel`'s own equality (used as a `FutureProvider.family` key).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is A1Milestone && name == other.name && status == other.status);

  @override
  int get hashCode => Object.hash(name, status);
}

/// Checkbox progress for one `.a1/phases/<name>/PLAN.md`.
class A1Phase {
  /// Phase directory name, e.g. `M6-learning-loop`.
  final String name;

  /// Number of checked (`- [x]`) checkboxes in the PLAN.md.
  final int checkedTasks;

  /// Total number of checkboxes (checked + unchecked).
  final int totalTasks;

  /// Absolute path to the PLAN.md.
  final String planPath;

  const A1Phase({
    required this.name,
    required this.checkedTasks,
    required this.totalTasks,
    required this.planPath,
  });

  /// Progress as 0-100, or null when there are no checkboxes to measure.
  int? get progress =>
      totalTasks == 0 ? null : (checkedTasks / totalTasks * 100).round();

  /// True when this phase has unfinished tasks — used to surface the "active"
  /// phase on the project card.
  bool get isActive => totalTasks > 0 && checkedTasks < totalTasks;

  /// Value equality — see `GitData.operator==` for why this matters for
  /// `ProjectModel`'s own equality (used as a `FutureProvider.family` key).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is A1Phase &&
          name == other.name &&
          checkedTasks == other.checkedTasks &&
          totalTasks == other.totalTasks &&
          planPath == other.planPath);

  @override
  int get hashCode => Object.hash(name, checkedTasks, totalTasks, planPath);
}

/// Aggregated a1 roadmap/phase state for a single project. Produced by
/// `A1Reader.read`.
class A1Data {
  /// Milestones from `.a1/roadmap.md`, in file order.
  final List<A1Milestone> milestones;

  /// Phase progress entries, sorted by phase name.
  final List<A1Phase> phases;

  const A1Data({this.milestones = const [], this.phases = const []});

  static const empty = A1Data();

  bool get isEmpty => milestones.isEmpty && phases.isEmpty;

  /// The first phase that still has unfinished tasks (the "current" phase), or
  /// null when every phase is complete or none has checkboxes.
  A1Phase? get activePhase {
    for (final phase in phases) {
      if (phase.isActive) return phase;
    }
    return null;
  }

  /// Aggregate progress across all phases with checkboxes (0-100), or null when
  /// there are no measurable phases. Used as the card fallback when a project
  /// has no GSD `.planning/`.
  int? get overallProgress {
    var checked = 0;
    var total = 0;
    for (final phase in phases) {
      checked += phase.checkedTasks;
      total += phase.totalTasks;
    }
    return total == 0 ? null : (checked / total * 100).round();
  }

  /// Value equality — see `GitData.operator==` for why this matters for
  /// `ProjectModel`'s own equality (used as a `FutureProvider.family` key).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is A1Data &&
          _listEquals(milestones, other.milestones) &&
          _listEquals(phases, other.phases));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(milestones), Object.hashAll(phases));
}

/// Element-wise list equality (order-sensitive) — avoids adding
/// `package:collection` as a direct dependency for this one comparison.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
