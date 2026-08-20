import 'package:test/test.dart';

import 'package:pro_orc/data/models/a1_data.dart';
import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/models/memory_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/project_type.dart';

// -----------------------------------------------------------------------
// 2026-08-20 process-storm-burst wave 4: ProjectModel needs value equality
// so FutureProvider.family (externalResourcesProvider, visionProvider,
// roadmapProvider) stop re-running their work on every rescan just because
// a fresh instance was constructed. These tests pin the equality contract
// down to field level, including nested models (git/memory/a1/mdFiles).
// -----------------------------------------------------------------------

ProjectModel _project({
  String folderId = 'foo',
  String displayName = 'Foo',
  String path = '/tmp/foo',
  ProjectType? projectType = ProjectType.code,
  String? description = 'A project',
  A1Data? a1,
  GitData? git,
  MemoryData? memory,
  bool isStale = false,
  List<String>? usedAgents,
  List<MdFileInfo>? mdFiles,
}) {
  return ProjectModel(
    folderId: folderId,
    displayName: displayName,
    path: path,
    projectType: projectType,
    description: description,
    a1: a1,
    git: git,
    memory: memory,
    isStale: isStale,
    usedAgents: usedAgents,
    mdFiles: mdFiles,
  );
}

void main() {
  group('GitData equality', () {
    test('equal when all fields match', () {
      final a = GitData(
        lastCommitMessage: 'fix: x',
        lastCommitHash: 'abc1234',
        lastCommitDate: DateTime(2026, 1, 1),
        githubUrl: 'https://github.com/o/r',
      );
      final b = GitData(
        lastCommitMessage: 'fix: x',
        lastCommitHash: 'abc1234',
        lastCommitDate: DateTime(2026, 1, 1),
        githubUrl: 'https://github.com/o/r',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when githubUrl differs', () {
      const a = GitData(githubUrl: 'https://github.com/o/r1');
      const b = GitData(githubUrl: 'https://github.com/o/r2');
      expect(a, isNot(equals(b)));
    });
  });

  group('MemoryData equality', () {
    test('equal when all fields match', () {
      final a = MemoryData(
        hasMemory: true,
        lastConsolidated: DateTime(2026, 1, 1),
        isStale: false,
      );
      final b = MemoryData(
        hasMemory: true,
        lastConsolidated: DateTime(2026, 1, 1),
        isStale: false,
      );
      expect(a, equals(b));
    });

    test('not equal when isStale differs', () {
      const a = MemoryData(hasMemory: true, isStale: false);
      const b = MemoryData(hasMemory: true, isStale: true);
      expect(a, isNot(equals(b)));
    });
  });

  group('A1Data equality (nested lists)', () {
    test('equal when milestones and phases match in order', () {
      const a = A1Data(
        milestones: [A1Milestone(name: 'M1', status: 'done')],
        phases: [
          A1Phase(
            name: 'M1-P1',
            checkedTasks: 3,
            totalTasks: 5,
            planPath: '/tmp/PLAN.md',
          ),
        ],
      );
      const b = A1Data(
        milestones: [A1Milestone(name: 'M1', status: 'done')],
        phases: [
          A1Phase(
            name: 'M1-P1',
            checkedTasks: 3,
            totalTasks: 5,
            planPath: '/tmp/PLAN.md',
          ),
        ],
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when a phase\'s checkedTasks differs', () {
      const a = A1Data(
        phases: [
          A1Phase(
            name: 'M1-P1',
            checkedTasks: 3,
            totalTasks: 5,
            planPath: '/tmp/PLAN.md',
          ),
        ],
      );
      const b = A1Data(
        phases: [
          A1Phase(
            name: 'M1-P1',
            checkedTasks: 4,
            totalTasks: 5,
            planPath: '/tmp/PLAN.md',
          ),
        ],
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when list lengths differ', () {
      const a = A1Data(
        milestones: [A1Milestone(name: 'M1', status: 'done')],
      );
      const b = A1Data(
        milestones: [
          A1Milestone(name: 'M1', status: 'done'),
          A1Milestone(name: 'M2', status: 'planning'),
        ],
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ProjectModel equality', () {
    test(
      'two separately-constructed instances with identical fields are '
      'equal — this is the case that broke family caching before the fix',
      () {
        final a = _project(
          git: const GitData(githubUrl: 'https://github.com/o/r'),
        );
        final b = _project(
          git: const GitData(githubUrl: 'https://github.com/o/r'),
        );

        expect(
          a,
          equals(b),
          reason:
              'two ProjectModel instances built from the same scan data must '
              'be == so FutureProvider.family keys hit the cache instead of '
              're-running detection on every rescan',
        );
        expect(a.hashCode, equals(b.hashCode));
      },
    );

    test('not equal when git data differs (must not mask a real content '
        'change behind a stale family-cache hit)', () {
      final a = _project(
        git: const GitData(githubUrl: 'https://github.com/o/r1'),
      );
      final b = _project(
        git: const GitData(githubUrl: 'https://github.com/o/r2'),
      );
      expect(a, isNot(equals(b)));
    });

    test(
      'not equal when mdFiles differ (resource_detector.dart reads this)',
      () {
        final a = _project(
          mdFiles: const [
            MdFileInfo(name: 'STATE.md', relativePath: 'STATE.md', path: '/x'),
          ],
        );
        final b = _project(mdFiles: const []);
        expect(a, isNot(equals(b)));
      },
    );

    test('not equal when path differs', () {
      final a = _project(path: '/tmp/a');
      final b = _project(path: '/tmp/b');
      expect(a, isNot(equals(b)));
    });

    test('not equal when displayName differs (renamed project)', () {
      final a = _project(displayName: 'Old Name');
      final b = _project(displayName: 'New Name');
      expect(a, isNot(equals(b)));
    });

    test('equal when both have null git/memory/a1/mdFiles/usedAgents', () {
      final a = _project();
      final b = _project();
      expect(a, equals(b));
    });

    test('usable as a Map key (hashCode consistency for family caching)', () {
      final a = _project();
      final b = _project();
      final map = {a: 'value'};

      expect(map[b], equals('value'));
    });
  });
}
