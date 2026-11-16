import 'dart:async';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import '../models/bible_models.dart';
import 'bible_repository.dart';
import 'storage_service.dart';

class NotificationSlot {
  final String id;
  final String label;
  final int hour;
  final int minute;

  const NotificationSlot({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
  });

  int get totalMinutes => hour * 60 + minute;
}

class NotificationService extends ChangeNotifier {
  final BibleRepository repo;
  final StorageService storage;
  Timer? _timer;
  bool _isAppInForeground = true;

  NotificationService({required this.repo, required this.storage});

  VerseRef get activeVerse =>
      storage.currentVerseRef ?? repo.getDailyVerseRef();

  int get unreadCount => storage.unreadNotificationCount;

  bool get isAppInForeground => _isAppInForeground;

  void start() {
    _timer?.cancel();
    storage.currentVerseRef ??= repo.getDailyVerseRef();
    if (storage.lastRotationMs == 0) {
      storage.lastRotationMs = DateTime.now().millisecondsSinceEpoch;
    }
    _syncLauncherBadge(storage.unreadNotificationCount);
    _checkSchedule();
    _timer =
        Timer.periodic(const Duration(seconds: 15), (_) => _checkSchedule());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> setForeground(bool inForeground) async {
    _isAppInForeground = inForeground;
    if (inForeground && storage.unreadNotificationCount > 0) {
      await clearUnreadBadge();
    }
  }

  Future<void> clearUnreadBadge() async {
    if (storage.unreadNotificationCount == 0) {
      await _syncLauncherBadge(0);
      return;
    }
    storage.unreadNotificationCount = 0;
    await storage.save();
    await _syncLauncherBadge(0);
    notifyListeners();
  }

  List<NotificationSlot> get slots {
    final sorted = [...storage.scheduledTimes]..sort();
    return sorted.map((t) {
      final parts = t.split(':');
      final h = int.tryParse(parts[0]) ?? 8;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      final label = h < 12
          ? 'Morning Bread'
          : h < 15
              ? 'Midday Bread'
              : 'Afternoon Bread';
      return NotificationSlot(id: t, label: label, hour: h, minute: m);
    }).toList();
  }

  Future<void> _checkSchedule() async {
    final mode = storage.scheduleMode;
    if (mode == 'manual') return;

    if (mode == 'interval') {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final intervalMs = storage.rotationIntervalMinutes * 60 * 1000;
      if (intervalMs <= 0) return;

      if (storage.lastRotationMs == 0) {
        storage.lastRotationMs = nowMs;
        await storage.save();
        return;
      }

      if (nowMs - storage.lastRotationMs >= intervalMs) {
        await rotateVerseNow(
          notify: storage.dailyNotificationsEnabled &&
              storage.rotationHighPriorityNotification,
          slotLabel: 'Daily Bread',
        );
      }
      return;
    }

    if (mode == 'times') {
      if (!storage.dailyNotificationsEnabled) return;
      final activeSlots = slots;
      if (activeSlots.isEmpty) return;

      final now = DateTime.now();
      final todayPrefix =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final nowMinutes = now.hour * 60 + now.minute;

      NotificationSlot? dueSlot;
      for (final slot in activeSlots) {
        if (nowMinutes >= slot.totalMinutes) {
          dueSlot = slot;
        }
      }
      if (dueSlot == null) return;

      final slotKey = '$todayPrefix:${dueSlot.id}';
      if (storage.lastNotifiedSlotKey == slotKey) return;

      if (storage.lastNotifiedSlotKey.startsWith(todayPrefix)) {
        final lastId =
            storage.lastNotifiedSlotKey.substring(todayPrefix.length + 1);
        final lastIdx = activeSlots.indexWhere((s) => s.id == lastId);
        final dueIdx = activeSlots.indexWhere((s) => s.id == dueSlot!.id);
        if (dueIdx <= lastIdx) return;
      }

      storage.lastNotifiedSlotKey = slotKey;
      await rotateVerseNow(
        notify: storage.rotationHighPriorityNotification,
        slotLabel: dueSlot.label,
      );
    }
  }

  Future<VerseRef> rotateVerseNow({
    bool notify = false,
    String slotLabel = 'Bible of the Day',
  }) async {
    final next = repo.getNextRotatedVerse(
      topicId: storage.rotationTopic,
      current: storage.currentVerseRef,
    );
    storage.currentVerseRef = next;
    storage.lastRotationMs = DateTime.now().millisecondsSinceEpoch;

    if (notify) {
      if (!_isAppInForeground) {
        storage.unreadNotificationCount += 1;
      }
      await storage.save();
      await sendVerseNotification(slotLabel: slotLabel, verseRef: next);
      if (!_isAppInForeground) {
        await _syncLauncherBadge(storage.unreadNotificationCount);
      }
    } else {
      await storage.save();
    }

    notifyListeners();
    return next;
  }

  Future<bool> sendTestNotification(
      {bool simulateBackgroundBadge = false}) async {
    final ref = activeVerse;
    if (simulateBackgroundBadge) {
      storage.unreadNotificationCount += 1;
      await storage.save();
      await _syncLauncherBadge(storage.unreadNotificationCount);
      notifyListeners();
    }
    return sendVerseNotification(slotLabel: 'Bible of the Day', verseRef: ref);
  }

  Future<bool> sendVerseNotification({
    required String slotLabel,
    VerseRef? verseRef,
    int slotOffset = 0,
  }) async {
    final ref = verseRef ?? repo.getDailyVerseRef(slotOffset: slotOffset);
    final book = repo.getBook(ref.bookId);
    final text = await repo.getVerseText(
        storage.translationId, ref.bookId, ref.chapter, ref.verse);
    if (book == null || text == null || text.isEmpty) return false;

    final translation = repo.getTranslation(storage.translationId);
    final shortTag = translation != null ? ' (${translation.shortName})' : '';
    final refTitle =
        '${book.displayName(storage.translationId)} ${ref.chapter}:${ref.verse}';
    final prefix = slotLabel.isNotEmpty ? slotLabel : 'Daily Bread';
    final title = '$prefix • $refTitle$shortTag';

    return _dispatchDesktopNotification(title, text);
  }

  Future<bool> _dispatchDesktopNotification(String title, String body) async {
    if (Platform.isMacOS) {
      return _dispatchMacOSNotification(title, body);
    }
    if (Platform.isWindows) {
      return _dispatchWindowsNotification(title, body);
    }
    if (!Platform.isLinux) return false;

    try {
      final client = DBusClient.session();
      final object = DBusRemoteObject(
        client,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );
      await object.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          const DBusString('Daily Bread'),
          const DBusUint32(0),
          const DBusString('dialog-information'),
          DBusString(title),
          DBusString(body),
          DBusArray.string(const []),
          DBusDict.stringVariant({
            'urgency': DBusByte(2), // High / Critical priority
            'desktop-entry':
                const DBusString('daily-bread-bible_daily-bread-bible'),
          }),
          const DBusInt32(10000),
        ],
        replySignature: DBusSignature('u'),
      );
      await client.close();
      return true;
    } catch (e) {
      debugPrint('D-Bus notification failed: $e');
    }

    try {
      final res = await Process.run('notify-send', [
        '-u',
        'critical',
        '-i',
        'dialog-information',
        '-a',
        'Daily Bread',
        title,
        body,
      ]);
      if (res.exitCode == 0) return true;
    } catch (e) {
      debugPrint('notify-send failed: $e');
    }

    try {
      final iconPath =
          File('/snap/daily-bread-bible/current/meta/gui/daily-bread.png')
                  .existsSync()
              ? '/snap/daily-bread-bible/current/meta/gui/daily-bread.png'
              : 'dialog-information';
      final res = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.Notifications',
        '--object-path',
        '/org/freedesktop/Notifications',
        '--method',
        'org.freedesktop.Notifications.Notify',
        'Daily Bread',
        '@u 0',
        iconPath,
        title,
        body,
        '@as []',
        '{"urgency": <byte 2>, "desktop-entry": <"daily-bread-bible_daily-bread-bible">}',
        '10000',
      ]);
      if (res.exitCode != 0) {
        debugPrint('gdbus notification error: ${res.stderr}');
      }
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('gdbus notification failed: $e');
      return false;
    }
  }

  Future<bool> _dispatchMacOSNotification(String title, String body) async {
    try {
      final safeTitle = title.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final safeBody = body.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      final res = await Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "$safeTitle"',
      ]);
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('macOS notification failed: $e');
      return false;
    }
  }

  Future<bool> _dispatchWindowsNotification(String title, String body) async {
    try {
      String xmlEsc(String s) => s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
      final safeTitle = xmlEsc(title);
      final safeBody = xmlEsc(body);
      final psScript = '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
\$xml.LoadXml('<toast scenario="reminder"><visual><binding template="ToastGeneric"><text>$safeTitle</text><text>$safeBody</text></binding></visual></toast>')
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('com.dailybread.daily_bread').Show(\$toast)
''';
      final res = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', psScript],
      );
      return res.exitCode == 0;
    } catch (e) {
      debugPrint('Windows notification failed: $e');
      return false;
    }
  }

  Future<void> _syncLauncherBadge(int count) async {
    if (!Platform.isLinux) return;
    try {
      final client = DBusClient.session();
      final path = DBusObjectPath('/com/canonical/unity/launcherentry/1');
      final props = DBusDict.stringVariant({
        'count': DBusInt64(count),
        'count-visible': DBusBoolean(count > 0),
        'urgent': DBusBoolean(count > 0),
      });

      const appUris = [
        'application://daily-bread-bible_daily-bread-bible.desktop',
        'application://com.dailybread.daily_bread.desktop',
      ];
      for (final uri in appUris) {
        await client.emitSignal(
          path: path,
          interface: 'com.canonical.Unity.LauncherEntry',
          name: 'Update',
          values: [DBusString(uri), props],
        );
      }
      await client.close();
      return;
    } catch (_) {
      // Fallback to gdbus emit inside strict snap confinement if needed
    }

    try {
      final props =
          '{"count": <int64 $count>, "count-visible": <${count > 0}>, "urgent": <${count > 0}>}';
      await Process.run('gdbus', [
        'emit',
        '--session',
        '--object-path',
        '/com/canonical/unity/launcherentry/1',
        '--signal',
        'com.canonical.Unity.LauncherEntry.Update',
        'application://daily-bread-bible_daily-bread-bible.desktop',
        props,
      ]);
    } catch (_) {
      // Ignore in headless/test environments without session D-Bus
    }
  }
}
