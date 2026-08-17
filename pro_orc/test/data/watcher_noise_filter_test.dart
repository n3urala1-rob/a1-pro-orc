import 'package:flutter_test/flutter_test.dart';
import 'package:pro_orc/data/services/watcher_service.dart';

void main() {
  group('isNoiseEvent', () {
    test('drops Claude session transcripts (.jsonl)', () {
      expect(
        isNoiseEvent(
          '/Users/rob/.claude/projects/-Users-rob/abc-123.jsonl',
        ),
        isTrue,
      );
    });

    test('keeps Claude memory files (.md)', () {
      expect(
        isNoiseEvent(
          '/Users/rob/.claude/projects/-Users-rob/memory/MEMORY.md',
        ),
        isFalse,
      );
    });

    test('drops node_modules and build-cache churn', () {
      expect(
        isNoiseEvent('/Users/rob/code/app/node_modules/react/index.js'),
        isTrue,
      );
      expect(isNoiseEvent('/Users/rob/code/app/.next/trace'), isTrue);
      expect(
        isNoiseEvent('/Users/rob/code/app/.dart_tool/version'),
        isTrue,
      );
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
      expect(
        isNoiseEvent('/Users/rob/code/app/.git/refs/heads/main'),
        isFalse,
      );
    });

    test('keeps ordinary project files', () {
      expect(isNoiseEvent('/Users/rob/code/app/lib/main.dart'), isFalse);
      expect(
        isNoiseEvent('/Users/rob/code/app/.planning/STATE.md'),
        isFalse,
      );
    });
  });
}
