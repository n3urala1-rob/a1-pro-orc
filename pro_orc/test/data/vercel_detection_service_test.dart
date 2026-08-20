import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_orc/data/services/vercel_detection_service.dart';

/// Injects a fixed [ProcessResult] regardless of the command invoked, so the
/// service's parsing logic can be exercised without a real `vercel` binary —
/// mirrors `gh_detection_service_test.dart`'s `_fixedRunner`.
VercelTeamsRunner _fixedRunner(ProcessResult result) {
  return (String command, List<String> args, {Duration? timeout}) async =>
      result;
}

/// Injects a runner that never completes within any reasonable timeout, to
/// simulate a hung `vercel` process.
VercelTeamsRunner _hangingRunner() {
  return (String command, List<String> args, {Duration? timeout}) async {
    await Future<void>.delayed(const Duration(seconds: 30));
    return ProcessResult(0, 0, '', '');
  };
}

/// Injects a runner that throws, simulating a process-launch failure.
VercelTeamsRunner _throwingRunner() {
  return (String command, List<String> args, {Duration? timeout}) async {
    throw ProcessException(command, args, 'simulated launch failure');
  };
}

void main() {
  group('VercelDetectionService', () {
    test(
      'isAvailable() returns true when which and whoami both succeed',
      () async {
        final service = VercelDetectionService(
          whichCommand: 'true', // exits 0 regardless of args
          vercelCommand: 'true',
        );

        final available = await service.isAvailable();

        expect(available, isTrue);
      },
    );

    test(
      'isAvailable() returns false when which fails (CLI not installed)',
      () async {
        final service = VercelDetectionService(
          whichCommand: 'false', // exits 1 regardless of args
          vercelCommand: 'true',
        );

        final available = await service.isAvailable();

        expect(available, isFalse);
      },
    );

    test(
      'isAvailable() returns false when whoami fails (not logged in)',
      () async {
        final service = VercelDetectionService(
          whichCommand: 'true',
          vercelCommand: 'false', // whoami subcommand also exits 1
        );

        final available = await service.isAvailable();

        expect(available, isFalse);
      },
    );

    test('isAvailable() actually kills a hung process instead of just giving '
        'up on awaiting it (2026-08-20 process-storm-burst wave 4)', () async {
      // isAvailable() calls `runProcessWithTimeout(whichCommand,
      // [vercelCommand], ...)` — using `sleep` as the executable and `30`
      // (seconds) as `vercelCommand` produces a real `sleep 30` child
      // process. Before this fix, isAvailable() called bare Process.run
      // with no timeout at all — this would have hung the whole test for
      // 30s. Routing through runProcessWithTimeout means the child is
      // SIGKILLed at teamsTimeout, so the call returns promptly instead.
      final service = VercelDetectionService(
        whichCommand: 'sleep',
        vercelCommand: '30',
        teamsTimeout: const Duration(milliseconds: 200),
      );

      final stopwatch = Stopwatch()..start();
      final available = await service.isAvailable();
      stopwatch.stop();

      expect(available, isFalse);
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            'a hung which/vercel process must be killed promptly, not '
            'left running for the full 30s sleep duration',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'isAvailable() returns false (no crash) for a nonexistent binary',
      () async {
        final service = VercelDetectionService(
          whichCommand: 'which_nonexistent_binary_xyz',
        );

        final available = await service.isAvailable();

        expect(available, isFalse);
      },
    );
  });

  group('VercelDetectionService.resolveTeamSlug() — '
      '2026-07-23-vercel-url-uses-orgid-not-slug', () {
    const orgId = 'team_yABWsykG53iYgFAWXpvnYn7m';
    const teamsListJson = '''
{
  "teams": [
    {
      "id": "team_yABWsykG53iYgFAWXpvnYn7m",
      "slug": "roberts-projects-fb13711c",
      "name": "Robert's projects",
      "current": true
    }
  ],
  "pagination": { "count": 1, "next": null, "prev": null }
}
''';

    test(
      'resolves the slug for a matching team id (real CLI output shape)',
      () async {
        final service = VercelDetectionService(
          whichCommand: 'true',
          vercelCommand: 'true',
          teamsRunner: _fixedRunner(ProcessResult(0, 0, teamsListJson, '')),
        );

        final slug = await service.resolveTeamSlug(orgId);

        expect(slug, equals('roberts-projects-fb13711c'));
      },
    );

    test('returns null when no team matches the given orgId', () async {
      final service = VercelDetectionService(
        whichCommand: 'true',
        vercelCommand: 'true',
        teamsRunner: _fixedRunner(ProcessResult(0, 0, teamsListJson, '')),
      );

      final slug = await service.resolveTeamSlug('team_does_not_exist');

      expect(slug, isNull);
    });

    test('returns null (no throw) when the CLI is unavailable '
        '(not installed / not logged in)', () async {
      final service = VercelDetectionService(
        whichCommand: 'false', // simulates `which vercel` failing
        teamsRunner: _fixedRunner(ProcessResult(0, 0, teamsListJson, '')),
      );

      final slug = await service.resolveTeamSlug(orgId);

      expect(slug, isNull);
    });

    test('returns null (no throw) when the process exits non-zero', () async {
      final service = VercelDetectionService(
        whichCommand: 'true',
        vercelCommand: 'true',
        teamsRunner: _fixedRunner(ProcessResult(0, 1, '', 'not logged in')),
      );

      final slug = await service.resolveTeamSlug(orgId);

      expect(slug, isNull);
    });

    test('returns null (no throw) on unparseable/garbage stdout', () async {
      final service = VercelDetectionService(
        whichCommand: 'true',
        vercelCommand: 'true',
        teamsRunner: _fixedRunner(
          ProcessResult(0, 0, 'not valid json at all', ''),
        ),
      );

      final slug = await service.resolveTeamSlug(orgId);

      expect(slug, isNull);
    });

    test('returns null (no throw) when the runner throws', () async {
      final service = VercelDetectionService(
        whichCommand: 'true',
        vercelCommand: 'true',
        teamsRunner: _throwingRunner(),
      );

      final slug = await service.resolveTeamSlug(orgId);

      expect(slug, isNull);
    });

    test('returns null (no throw, no hang) when the CLI process hangs — '
        'bounded by an explicit timeout, never blocks indefinitely', () async {
      final service = VercelDetectionService(
        whichCommand: 'true',
        vercelCommand: 'true',
        teamsRunner: _hangingRunner(),
        teamsTimeout: const Duration(milliseconds: 50),
      );

      final slug = await service.resolveTeamSlug(orgId);

      expect(slug, isNull);
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
