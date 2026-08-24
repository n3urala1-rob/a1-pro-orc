import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:pro_orc/data/services/headless_skill_runner.dart';

/// Thin seam around the `flutter_local_notifications` plugin API this
/// service actually calls — mirrors this codebase's `whichCommand`/
/// `ClaudeDetectionService` injection precedent so tests can fake the OS
/// notification center instead of touching it for real.
abstract class NotificationPlugin {
  Future<void> initialize();
  Future<bool?> requestPermissions();
  Future<void> show({required int id, String? title, String? body});
}

/// Production [NotificationPlugin] backed by the real
/// `FlutterLocalNotificationsPlugin` and macOS's User Notifications
/// Framework.
class LocalNotifierPlugin implements NotificationPlugin {
  LocalNotifierPlugin() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    // Permission flags false at init (FR-013: request at the point of the
    // first real completion, not at app startup) — requestPermissions()
    // below is called explicitly instead.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      macOS: darwinSettings,
      iOS: darwinSettings,
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  @override
  Future<bool?> requestPermissions() async {
    return await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> show({required int id, String? title, String? body}) {
    return _plugin.show(id: id, title: title, body: body);
  }
}

/// Fires a macOS local notification when a headless skill run reaches a
/// terminal state (success, failure, timeout, cancelled) — spec 011
/// FR-013/FR-014.
///
/// Requests notification permission (if not yet granted) at the point this
/// method is first called after a real completion — not at app startup.
/// On any failure (denied permission, plugin error), the failure is
/// swallowed (logged, never thrown) — the caller's own state update (last-
/// run status) always completes independent of whether the notification
/// itself succeeded (FR-014/SC-009: a denied permission degrades this one
/// FR, not the whole feature).
class SkillNotificationService {
  SkillNotificationService({NotificationPlugin? plugin})
    : _plugin = plugin ?? LocalNotifierPlugin();

  final NotificationPlugin _plugin;
  bool _permissionRequested = false;
  int _nextNotificationId = 0;

  Future<void> notifyRunCompleted({
    required String skillDisplayName,
    required String projectDisplayName,
    required SkillRunStatus status,
  }) async {
    try {
      await _plugin.initialize();
      if (!_permissionRequested) {
        _permissionRequested = true;
        await _plugin.requestPermissions();
      }
      await _plugin.show(
        id: _nextNotificationId++,
        title: _titleFor(status),
        body: '$skillDisplayName – $projectDisplayName',
      );
    } catch (e) {
      developer.log(
        'Failed to show skill-run completion notification: $e',
        name: 'skill_notification_service',
      );
    }
  }

  String _titleFor(SkillRunStatus status) {
    switch (status) {
      case SkillRunStatus.success:
        return 'Skill erfolgreich abgeschlossen';
      case SkillRunStatus.failure:
        return 'Skill fehlgeschlagen';
      case SkillRunStatus.timeout:
        return 'Skill wegen Zeitüberschreitung abgebrochen';
      case SkillRunStatus.cancelled:
        return 'Skill abgebrochen';
      case SkillRunStatus.running:
        // Not a terminal state — notifyRunCompleted is never called with
        // this value by any real caller, but a default keeps the switch
        // exhaustive and safe if it somehow were.
        return 'Skill-Status aktualisiert';
    }
  }
}
