import 'dart:math';

/// Fuzzy-matches a project's folder name against candidate Obsidian vault
/// hub filename stems (e.g. 'pro-orc' for `project/pro-orc.md`), so an
/// unlinked project can be offered a one-time confirmation suggestion
/// instead of always falling through to auto-create. Pure functions, no I/O.

const double _matchThreshold = 0.6;

/// Normalized Levenshtein similarity in `[0.0, 1.0]`. Lowercases both
/// inputs and treats '-', '_', and ' ' as equivalent separators before
/// comparing, so 'my_project' and 'my-project' score as (near-)identical.
///
/// Normalized as `(lenA + lenB - distance) / (lenA + lenB)` (the standard
/// Levenshtein "ratio" formula, matching e.g. Python's `difflib`/
/// `python-Levenshtein` `ratio()`) rather than dividing by the longer
/// string's length — this is more forgiving of prefix-style relationships
/// like 'n3ural' vs. 'n3ural-website' (the spec's own worked example),
/// which a max-length normalization would score too low to ever suggest.
///
/// Two empty strings are treated as identical (1.0); one empty and one
/// non-empty string score 0.0 (maximal edit distance relative to length).
double hubSimilarity(String projectFolderName, String hubFilenameStem) {
  final a = _normalize(projectFolderName);
  final b = _normalize(hubFilenameStem);

  if (a.isEmpty && b.isEmpty) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;

  final distance = _levenshtein(a, b);
  final totalLen = a.length + b.length;
  return (totalLen - distance) / totalLen;
}

/// Returns the highest-scoring entry in [hubStems] at similarity >=
/// [_matchThreshold] (normalized Levenshtein via [hubSimilarity]), or
/// `null` if none clears the threshold. Ties are broken by first
/// occurrence in [hubStems].
String? suggestHub(String projectFolderName, List<String> hubStems) {
  String? best;
  double bestScore = -1;

  for (final stem in hubStems) {
    final score = hubSimilarity(projectFolderName, stem);
    if (score >= _matchThreshold && score > bestScore) {
      bestScore = score;
      best = stem;
    }
  }

  return best;
}

String _normalize(String input) {
  return input.toLowerCase().replaceAll(RegExp(r'[-_ ]'), '-');
}

/// Classic Wagner–Fischer edit distance, O(len(a) * len(b)) time and
/// O(min(len(a), len(b))) space.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Ensure `a` is the shorter string to minimize row width.
  if (a.length > b.length) {
    final tmp = a;
    a = b;
    b = tmp;
  }

  var previousRow = List<int>.generate(a.length + 1, (i) => i);
  final currentRow = List<int>.filled(a.length + 1, 0);

  for (var i = 1; i <= b.length; i++) {
    currentRow[0] = i;
    for (var j = 1; j <= a.length; j++) {
      final cost = a[j - 1] == b[i - 1] ? 0 : 1;
      currentRow[j] = min(
        min(currentRow[j - 1] + 1, previousRow[j] + 1),
        previousRow[j - 1] + cost,
      );
    }
    for (var j = 0; j <= a.length; j++) {
      previousRow[j] = currentRow[j];
    }
  }

  return previousRow[a.length];
}
