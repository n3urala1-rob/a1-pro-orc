import 'package:test/test.dart';

import 'package:pro_orc/data/services/headless_skill_runner.dart';
import 'package:pro_orc/data/services/skill_notification_service.dart';

class _FakeNotificationPlugin implements NotificationPlugin {
  int initializeCalls = 0;
  int requestPermissionsCalls = 0;
  bool? permissionResult = true;
  final List<({int id, String? title, String? body})> shownNotifications = [];
  bool throwOnShow = false;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<bool?> requestPermissions() async {
    requestPermissionsCalls++;
    return permissionResult;
  }

  @override
  Future<void> show({required int id, String? title, String? body}) async {
    if (throwOnShow) {
      throw StateError('permission denied (fake)');
    }
    shownNotifications.add((id: id, title: title, body: body));
  }
}

void main() {
  group('SkillNotificationService', () {
    test('a completed run triggers exactly one notification via the injected '
        'plugin', () async {
      final fake = _FakeNotificationPlugin();
      final service = SkillNotificationService(plugin: fake);

      await service.notifyRunCompleted(
        skillDisplayName: 'a1-progress',
        projectDisplayName: 'pro-orc',
        status: SkillRunStatus.success,
      );

      expect(fake.shownNotifications, hasLength(1));
      expect(fake.shownNotifications.single.body, contains('pro-orc'));
    });

    test('requests permission only once across multiple completions', () async {
      final fake = _FakeNotificationPlugin();
      final service = SkillNotificationService(plugin: fake);

      await service.notifyRunCompleted(
        skillDisplayName: 'a1-progress',
        projectDisplayName: 'pro-orc',
        status: SkillRunStatus.success,
      );
      await service.notifyRunCompleted(
        skillDisplayName: 'a1-checklist',
        projectDisplayName: 'pro-orc',
        status: SkillRunStatus.failure,
      );

      expect(fake.requestPermissionsCalls, equals(1));
      expect(fake.shownNotifications, hasLength(2));
    });

    test(
      'a denied/failed permission does not throw past this service',
      () async {
        final fake = _FakeNotificationPlugin()
          ..permissionResult = false
          ..throwOnShow = true;
        final service = SkillNotificationService(plugin: fake);

        await expectLater(
          service.notifyRunCompleted(
            skillDisplayName: 'a1-progress',
            projectDisplayName: 'pro-orc',
            status: SkillRunStatus.failure,
          ),
          completes,
        );
      },
    );

    test('renders a distinct title per terminal status', () async {
      final fake = _FakeNotificationPlugin();
      final service = SkillNotificationService(plugin: fake);

      for (final status in [
        SkillRunStatus.success,
        SkillRunStatus.failure,
        SkillRunStatus.timeout,
        SkillRunStatus.cancelled,
      ]) {
        await service.notifyRunCompleted(
          skillDisplayName: 'a1-progress',
          projectDisplayName: 'pro-orc',
          status: status,
        );
      }

      final titles = fake.shownNotifications.map((n) => n.title).toSet();
      expect(titles, hasLength(4));
    });
  });
}
