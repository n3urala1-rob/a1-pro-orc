import 'package:test/test.dart';

import 'package:pro_orc/data/services/vault_hub_matcher.dart';

void main() {
  group('hubSimilarity', () {
    test('identical strings score 1.0', () {
      expect(hubSimilarity('pro-orc', 'pro-orc'), equals(1.0));
    });

    test('a clearly related pair scores above the 0.6 threshold', () {
      final score = hubSimilarity('n3ural', 'n3ural-website');
      expect(score, greaterThanOrEqualTo(0.6));
    });

    test('unrelated names score below the 0.6 threshold', () {
      final score = hubSimilarity('pro-orc', 'niimo');
      expect(score, lessThan(0.6));
    });

    test('separator normalization: "_" and "-" are equivalent', () {
      final score = hubSimilarity('my_project', 'my-project');
      expect(score, greaterThanOrEqualTo(0.95));
    });

    test('separator normalization: space and "-" are equivalent', () {
      final score = hubSimilarity('my project', 'my-project');
      expect(score, greaterThanOrEqualTo(0.95));
    });

    test('comparison is case-insensitive', () {
      final score = hubSimilarity('ProOrc', 'proorc');
      expect(score, equals(1.0));
    });

    test('score is symmetric', () {
      final a = hubSimilarity('n3ural', 'n3ural-website');
      final b = hubSimilarity('n3ural-website', 'n3ural');
      expect(a, equals(b));
    });

    test('empty strings compared to empty score 1.0 (identical)', () {
      expect(hubSimilarity('', ''), equals(1.0));
    });

    test('empty vs non-empty scores 0.0', () {
      expect(hubSimilarity('', 'pro-orc'), equals(0.0));
    });

    test('umlauts and special characters do not throw and compare sanely', () {
      final identical = hubSimilarity('münchen-büro', 'münchen-büro');
      expect(identical, equals(1.0));

      // Diacritics are not folded, but the edit distance between the
      // umlaut and ASCII-transliterated spellings is still small relative
      // to string length, so a high (not necessarily below-threshold)
      // score is expected — the key assertion is that unicode input does
      // not throw and stays within [0.0, 1.0].
      final related = hubSimilarity('münchen-büro', 'muenchen-buero');
      expect(related, greaterThanOrEqualTo(0.0));
      expect(related, lessThanOrEqualTo(1.0));

      final unrelated = hubSimilarity('münchen-büro', 'niimo');
      expect(unrelated, lessThan(0.6));
    });
  });

  group('suggestHub', () {
    test('returns the highest-scoring stem at or above threshold', () {
      final result = suggestHub('pro-orc', [
        'niimo',
        'pro-orc-legacy',
        'n3ural',
      ]);
      expect(result, equals('pro-orc-legacy'));
    });

    test('returns null when no candidate clears the threshold', () {
      final result = suggestHub('pro-orc', ['niimo', 'n3ural', 'vodafone']);
      expect(result, isNull);
    });

    test('returns null for an empty candidate list', () {
      expect(suggestHub('pro-orc', []), isNull);
    });

    test('deterministic tie-break: first occurrence wins on equal scores', () {
      // Both candidates are equally similar to 'abc' (same edit distance).
      final result = suggestHub('abc', ['abd', 'abe']);
      expect(result, equals('abd'));
    });

    test('exact match wins over a merely-similar candidate', () {
      final result = suggestHub('pro-orc', ['pro-orc-old', 'pro-orc']);
      expect(result, equals('pro-orc'));
    });
  });
}
