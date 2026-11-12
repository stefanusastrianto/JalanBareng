import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../models.dart';
import '../store.dart';

/// Pengingat lokal di HP. Dijadwalkan di perangkat, jadi tetap muncul tanpa internet.
class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int scheduledCount = 0;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('jadwal', 'Pengingat jadwal',
        channelDescription: 'Pengingat agenda dan ringkasan hari berikutnya',
        importance: Importance.high,
        priority: Priority.high),
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(Config.timezone));
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> showNow(String title, String body) async {
    await init();
    await _plugin.show(999999, title, body, _details);
  }

  int _id(String s) => s.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x3fffffff);

  tz.TZDateTime _at(String date, int minutes) {
    final d = parseIso(date);
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
  }

  Future<void> _schedule(String key, String title, String body, tz.TZDateTime when) async {
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(_id(key), title, body, when, _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    scheduledCount++;
  }

  /// Jadwalkan ulang semua pengingat: malam sebelumnya 20.00, 3 jam dan 30 menit sebelum kereta/pesawat,
  /// 30 menit sebelum agenda lain yang punya jam.
  Future<void> reschedule(AppState s) async {
    try {
      await init();
      await _plugin.cancelAll();
      scheduledCount = 0;
      final now = DateTime.now();
      final limit = now.add(const Duration(days: 45));
      for (final day in s.activeDays()) {
        final d = parseIso(day);
        if (d.isBefore(DateTime(now.year, now.month, now.day)) || d.isAfter(limit)) continue;
        final its = s.itemsOn(day);
        final lines = its.where((i) => i.time.isNotEmpty).map((i) => '${i.time} ${i.title}').take(4).join(' · ');
        final eve = parseIso(day).subtract(const Duration(days: 1));
        await _schedule('eve-$day', 'Besok: ${dayLabel(day)}', lines.isEmpty ? '${its.length} agenda. Buka aplikasi untuk detail.' : lines,
            _at(isoDate(eve), 20 * 60));
        for (final i in its) {
          final m = mins(i.time);
          if (m == null) continue;
          final code = i.bookingCode.isNotEmpty ? ' · kode ${i.bookingCode}' : '';
          if (i.type == 'kereta' || i.type == 'pesawat') {
            await _schedule('3h-${i.id}', '3 jam lagi: ${i.title}', 'Berangkat ${i.time}${i.location.isNotEmpty ? ' dari ${i.location}' : ''}$code. Siapkan KTP.',
                _at(day, m - 180));
          }
          await _schedule('30m-${i.id}', '30 menit lagi: ${i.title}', '${i.time}${i.location.isNotEmpty ? ' · ${i.location}' : ''}$code', _at(day, m - 30));
          if (scheduledCount > 120) return;
        }
      }
    } catch (_) {
      // Pengingat bersifat bantuan; kegagalan tidak boleh mengganggu aplikasi.
    }
  }
}
