import 'package:flutter_test/flutter_test.dart';
import 'package:pro_orc/data/services/watcher_service.dart';

void main() {
  group('isNoiseEvent', () {
    test('drops node_modules and build-cache churn', () {
      expect(
        isNoiseEvent('/Users/rob/code/app/node_modules/react/index.js'),
        isTrue,
      );
      expect(isNoiseEvent('/Users/rob/code/app/.next/trace'), isTrue);
      expect(isNoiseEvent('/Users/rob/code/app/.dart_tool/version'), isTrue);
    });

    test('drops .git object/pack churn', () {
      expect(
        isNoiseEvent('/Users/rob/code/app/.git/objects/ab/cdef123'),
        isTrue,
      );
      expect(isNoiseEvent('/Users/rob/code/app/.git/index'), isTrue);
    });

    test('keeps .git commit signals (HEAD and refs)', () {
      expect(isNoiseEvent('/Users/rob/code/app/.git/HEAD'), isFalse);
      expect(isNoiseEvent('/Users/rob/code/app/.git/logs/HEAD'), isFalse);
      expect(isNoiseEvent('/Users/rob/code/app/.git/refs/heads/main'), isFalse);
    });

    test('keeps ordinary project files', () {
      expect(isNoiseEvent('/Users/rob/code/app/lib/main.dart'), isFalse);
      expect(isNoiseEvent('/Users/rob/code/app/.planning/STATE.md'), isFalse);
    });

    test('keeps .a1/ roadmap and phase files under a scan dir', () {
      expect(isNoiseEvent('/Users/rob/code/app/.a1/roadmap.md'), isFalse);
      expect(
        isNoiseEvent('/Users/rob/code/app/.a1/phases/M1-P1-foo/PLAN.md'),
        isFalse,
      );
    });

    test('drops build/ output under a scan dir (2026-08-20 addition)', () {
      expect(isNoiseEvent('/Users/rob/code/app/build/macos/foo'), isTrue);
    });

    // --- ~/.claude/ allowlist (2026-08-20 process-storm-burst wave 3) -------
    //
    // Blacklist semantics under ~/.claude/ let an unbounded, ever-growing
    // set of high-churn directories through (measured: 483 changes under
    // plugins/cache/ in 2h). Switched to allowlist: only paths the
    // dashboard actually reads pass through.

    group('~/.claude/ noise (dropped)', () {
      test('drops plugins/cache/ churn', () {
        expect(
          isNoiseEvent(
            '/Users/rob/.claude/plugins/cache/some-plugin/abc123/index.js',
          ),
          isTrue,
        );
      });

      test('drops tool-results/', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/tool-results/result-42.json'),
          isTrue,
        );
      });

      test('drops subagents/', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/subagents/session-abc/state.json'),
          isTrue,
        );
      });

      test('drops file-history/', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/file-history/foo.dart.bak'),
          isTrue,
        );
      });

      test('drops shell-snapshots/', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/shell-snapshots/snap-1.json'),
          isTrue,
        );
      });

      test('drops todos/', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/todos/session-abc.json'),
          isTrue,
        );
      });

      test('drops any other cache/ dir under .claude', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/some-feature/cache/blob-1'),
          isTrue,
        );
      });

      test('drops session transcripts (.jsonl) anywhere under .claude', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/projects/-Users-rob/abc-123.jsonl'),
          isTrue,
        );
      });

      test('drops unrecognized top-level files under .claude', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/some-random-scratch-file.tmp'),
          isTrue,
        );
      });
    });

    group('~/.claude/ signal (still passes)', () {
      test('keeps Claude memory files (.md)', () {
        expect(
          isNoiseEvent(
            '/Users/rob/.claude/projects/-Users-rob/memory/MEMORY.md',
          ),
          isFalse,
        );
      });

      test('keeps skills/ changes', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/skills/my-skill/SKILL.md'),
          isFalse,
        );
      });

      test('keeps agents/ changes', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/agents/felix-flutter-engineer.md'),
          isFalse,
        );
      });

      test('keeps plugins/installed_plugins.json', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/plugins/installed_plugins.json'),
          isFalse,
        );
      });

      test('keeps plugins/known_marketplaces.json', () {
        expect(
          isNoiseEvent('/Users/rob/.claude/plugins/known_marketplaces.json'),
          isFalse,
        );
      });

      test('keeps settings.json', () {
        expect(isNoiseEvent('/Users/rob/.claude/settings.json'), isFalse);
      });
    });
  });
}
