import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

import 'package:pro_orc/data/models/git_data.dart';
import 'package:pro_orc/data/models/project_model.dart';
import 'package:pro_orc/data/models/project_type.dart';

ProjectModel _project() {
  return ProjectModel(
    folderId: 'foo',
    displayName: 'Foo',
    path: '/tmp/definitely-not-a-real-project-path-xyz',
    projectType: ProjectType.code,
    git: const GitData(githubUrl: 'https://github.com/o/r'),
  );
}

void main() {
  group('FutureProvider.family caching with ProjectModel keys '
      '(2026-08-20 process-storm-burst wave 4)', () {
    test('two content-identical-but-distinct ProjectModel instances share '
        'the same family cache entry — the body runs only once', () async {
      var runCount = 0;
      // Mirrors the shape of externalResourcesProvider/visionProvider/
      // roadmapProvider: FutureProvider.family<T, ProjectModel>. Before
      // ProjectModel had value equality, Riverpod's family lookup used
      // identity, so every rescan's fresh ProjectModel instance was a
      // cache MISS and re-ran this body (re-spawning e.g. the vercel
      // CLI) even when nothing about the project actually changed.
      final probeProvider = FutureProvider.family<int, ProjectModel>((
        ref,
        project,
      ) async {
        runCount++;
        return runCount;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Two SEPARATE instances built from identical field values —
      // exactly what happens across two rescans of an unchanged
      // project.
      final a = _project();
      final b = _project();
      expect(
        identical(a, b),
        isFalse,
        reason: 'test setup: these must be distinct instances',
      );
      expect(a, equals(b), reason: 'test setup: must be value-equal');

      final resultA = await container.read(probeProvider(a).future);
      final resultB = await container.read(probeProvider(b).future);

      expect(runCount, equals(1), reason: 'body must run only once');
      expect(
        resultB,
        equals(resultA),
        reason:
            'probeProvider(b) must reuse probeProvider(a)\'s cached '
            'result instead of recomputing — this is exactly what '
            'ProjectModel value equality fixes for '
            'externalResourcesProvider/visionProvider/roadmapProvider',
      );
    });

    test('two ProjectModel instances that differ in content get separate '
        'family cache entries (equality must not over-collapse)', () async {
      var runCount = 0;
      final probeProvider = FutureProvider.family<int, ProjectModel>((
        ref,
        project,
      ) async {
        runCount++;
        return runCount;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final a = _project();
      final b = ProjectModel(
        folderId: a.folderId,
        displayName: a.displayName,
        path: a.path,
        projectType: a.projectType,
        git: const GitData(githubUrl: 'https://github.com/o/different'),
      );
      expect(a, isNot(equals(b)));

      await container.read(probeProvider(a).future);
      await container.read(probeProvider(b).future);

      expect(
        runCount,
        equals(2),
        reason:
            'a real content change (different git remote) must still '
            'trigger a fresh computation, not be masked by an '
            'over-broad equality',
      );
    });
  });
}
