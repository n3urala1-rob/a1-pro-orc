import 'package:test/test.dart';

import 'package:pro_orc/data/services/skill_run_concurrency_limiter.dart';

void main() {
  group('SkillRunConcurrencyLimiter', () {
    test(
      'per-project limit: a second run for the same project is rejected',
      () {
        final limiter = SkillRunConcurrencyLimiter();

        expect(limiter.canStart('proj-a'), isTrue);
        limiter.markStarted('proj-a');

        expect(limiter.canStart('proj-a'), isFalse);
      },
    );

    test('a different project is unaffected by another project running', () {
      final limiter = SkillRunConcurrencyLimiter();

      limiter.markStarted('proj-a');

      expect(limiter.canStart('proj-b'), isTrue);
    });

    test('system-wide limit: a third project is rejected once 2 are running, '
        'and canStart is true again after markFinished frees a slot', () {
      final limiter = SkillRunConcurrencyLimiter(maxSystemWide: 2);

      expect(limiter.canStart('proj-a'), isTrue);
      limiter.markStarted('proj-a');
      expect(limiter.canStart('proj-b'), isTrue);
      limiter.markStarted('proj-b');

      expect(limiter.canStart('proj-c'), isFalse);

      limiter.markFinished('proj-a');
      expect(limiter.canStart('proj-c'), isTrue);
    });

    test('reject, not queue: canStart is a synchronous boolean with no '
        'internal waiting — repeated false checks never change state on '
        'their own', () {
      final limiter = SkillRunConcurrencyLimiter();
      limiter.markStarted('proj-a');

      // Calling canStart repeatedly must never itself start queuing or
      // mutate state — only markStarted/markFinished do that.
      expect(limiter.canStart('proj-a'), isFalse);
      expect(limiter.canStart('proj-a'), isFalse);
      expect(limiter.canStart('proj-a'), isFalse);
      expect(limiter.runningCount, equals(1));
    });

    test('markFinished on a project with no in-flight run is a safe no-op', () {
      final limiter = SkillRunConcurrencyLimiter();
      expect(() => limiter.markFinished('never-started'), returnsNormally);
      expect(limiter.canStart('never-started'), isTrue);
    });

    test('FR-019 (no separate mechanism needed): the per-project limit alone '
        'blocks a second, different skill for the same project — no '
        'skill-identifier parameter exists on this limiter at all', () {
      final limiter = SkillRunConcurrencyLimiter();
      // The limiter's contract is folderId-only (no skillId parameter),
      // which is itself the structural proof no separate "different
      // skill, same project" mechanism exists — starting any skill for a
      // project occupies that project's only slot regardless of which
      // skill it was.
      limiter.markStarted('proj-a');
      expect(limiter.canStart('proj-a'), isFalse);
    });
  });
}
