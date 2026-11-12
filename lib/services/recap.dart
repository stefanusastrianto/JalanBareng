import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../store.dart';
import 'gemini.dart';
import 'media.dart';

class _Pick {
  final Media m;
  String caption;
  _Pick(this.m, [this.caption = '']);
}

/// Merakit video recap (per hari atau seluruh trip) dari foto/video yang sudah diunggah.
class RecapService extends ChangeNotifier {
  RecapService._();
  static final RecapService I = RecapService._();

  bool running = false;
  String status = '';
  double progress = 0; // 0..1
  String? error;
  String? lastPath;
  String? lastTitle;

  void _set(String st, double p) {
    status = st;
    progress = p;
    notifyListeners();
  }

  /// [day] = 'yyyy-mm-dd' untuk recap harian, null untuk seluruh trip. [musicPath] opsional (file audio dari HP).
  Future<String?> make({String? day, String? musicPath}) async {
    if (running) return null;
    final s = AppState.I;
    final all = day == null ? List<Media>.from(s.media) : s.mediaOn(day);
    all.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (all.isEmpty) {
      error = 'Belum ada foto/video ${day == null ? 'trip' : 'di ${dayLabel(day)}'}. Unggah dulu dari galeri HP.';
      notifyListeners();
      return null;
    }
    running = true;
    error = null;
    lastPath = null;
    try {
      final maxN = day == null ? 40 : 18;
      final days = s.tripDays();
      final defaultTitle = day == null
          ? s.tripName
          : 'Hari ${days.indexOf(day) + 1} · ${s.realCityLabel(day).isEmpty ? shortDay(day) : s.realCityLabel(day)}';
      var title = defaultTitle;

      // 1) Pilih momen terbaik.
      _set('Memilih momen terbaik…', 0.03);
      var picks = <_Pick>[];
      try {
        final r = await _aiPick(all, maxN, day);
        picks = r.$1;
        if (r.$2.trim().isNotEmpty) title = r.$2.trim();
      } catch (_) {
        picks = [];
      }
      if (picks.isEmpty) picks = _fallbackPick(all, maxN);
      picks.sort((a, b) => a.m.takenAt.compareTo(b.m.takenAt));
      _fillCaptions(picks, day == null);

      // 2) Unduh file aslinya.
      final files = <String>[];
      for (var k = 0; k < picks.length; k++) {
        _set('Mengunduh ${k + 1} dari ${picks.length}…', 0.08 + 0.37 * k / picks.length);
        final m = picks[k].m;
        final f = await MediaService.I.download(m.path, 'rc_${m.id}${m.isVideo ? '.mp4' : '.jpg'}');
        files.add(f.path);
      }

      // 3) Rakit video di HP.
      final portrait = picks.where((p) => p.m.portrait).length * 2 >= picks.length;
      final tmp = await getTemporaryDirectory();
      final out = '${tmp.path}/recap_${day ?? 'trip'}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final subtitle = day == null ? '${shortDay(s.start)} – ${shortDay(s.end)} ${s.end.substring(0, 4)}' : dayLabel(day);
      final items = <Map<String, dynamic>>[];
      var totalMs = 0;
      for (var k = 0; k < picks.length; k++) {
        final m = picks[k].m;
        final it = <String, dynamic>{'path': files[k], 'type': m.isVideo ? 'video' : 'photo'};
        if (m.isVideo) {
          final dur = m.durationMs <= 0 ? 4000 : m.durationMs;
          final len = dur < 4000 ? dur : 4000;
          final startMs = dur > 6000 ? (dur ~/ 2 - 2000) : 0;
          it['startMs'] = startMs;
          it['endMs'] = startMs + len;
          totalMs += len;
        } else {
          final ms = k == 0 ? 3200 : 2500;
          it['durationMs'] = ms;
          totalMs += ms;
        }
        if (k == 0) it['title'] = '$title\n$subtitle';
        if (picks[k].caption.isNotEmpty) it['caption'] = picks[k].caption;
        items.add(it);
      }
      final spec = {
        'output': out,
        'width': portrait ? 720 : 1280,
        'height': portrait ? 1280 : 720,
        'audio': true,
        if (musicPath != null && musicPath.isNotEmpty) 'music': musicPath,
        'items': items,
      };
      _set('Merakit video…', 0.47);
      final ok = await _render(spec);
      if (!ok) {
        // Coba lagi tanpa suara (beberapa HP menolak campuran foto + video bersuara).
        spec['audio'] = false;
        spec.remove('music');
        _set('Merakit ulang tanpa suara…', 0.5);
        if (!await _render(spec)) throw Exception(error ?? 'Gagal merakit video');
      }

      // 4) Simpan ke cloud supaya anggota lain bisa menonton.
      _set('Menyimpan ke cloud…', 0.92);
      final ref = s.col('recaps').doc();
      final path = 'trip/recaps/${ref.id}.mp4';
      final sref = FirebaseStorage.instance.ref(path);
      await sref.putFile(File(out), SettableMetadata(contentType: 'video/mp4'));
      final url = await sref.getDownloadURL();
      await ref.set({
        'scope': day == null ? 'trip' : 'day',
        'date': day ?? '',
        'title': title,
        'url': url,
        'path': path,
        'durationMs': totalMs,
        'count': picks.length,
        'by': s.email,
        'byName': s.myName,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      lastPath = out;
      lastTitle = title;
      _set('Selesai', 1);
      return out;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<bool> _render(Map<String, dynamic> spec) async {
    var finished = false;
    final timer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      if (finished) return;
      final p = await VideoNative.progress();
      if (p >= 0 && !finished) _set('Merakit video… $p%', 0.47 + 0.44 * p / 100);
    });
    try {
      await VideoNative.recap(jsonEncode(spec));
      return File(spec['output'] as String).existsSync();
    } catch (e) {
      error = 'Perakitan video gagal: $e';
      return false;
    } finally {
      finished = true;
      timer.cancel();
    }
  }

  List<_Pick> _fallbackPick(List<Media> all, int maxN) {
    if (all.length <= maxN) return all.map((m) => _Pick(m)).toList();
    final out = <_Pick>[];
    for (var k = 0; k < maxN; k++) {
      out.add(_Pick(all[(k * all.length / maxN).floor()]));
    }
    return out;
  }

  /// Caption default: nama agenda (atau hari) setiap kali berganti.
  void _fillCaptions(List<_Pick> picks, bool wholeTrip) {
    final s = AppState.I;
    var last = '';
    var lastDay = '';
    for (final p in picks) {
      final it = s.items.where((i) => i.id == p.m.itemId).firstOrNull;
      final label = it?.title ?? '';
      if (wholeTrip && p.m.date != lastDay) {
        final city = s.realCityLabel(p.m.date);
        if (p.caption.isEmpty) p.caption = '${shortDay(p.m.date)}${city.isEmpty ? '' : ' · $city'}';
        lastDay = p.m.date;
        last = label;
        continue;
      }
      if (p.caption.isEmpty && label.isNotEmpty && label != last) {
        p.caption = label.length > 30 ? '${label.substring(0, 29)}…' : label;
      }
      if (label.isNotEmpty) last = label;
    }
  }

  /// Minta Gemini memilih momen terbaik dari thumbnail. Mengembalikan (pilihan, judul).
  Future<(List<_Pick>, String)> _aiPick(List<Media> all, int maxN, String? day) async {
    final s = AppState.I;
    // Batasi kandidat supaya permintaan tidak terlalu besar.
    var cand = all;
    const maxCand = 60;
    if (cand.length > maxCand) {
      cand = [for (var k = 0; k < maxCand; k++) all[(k * all.length / maxCand).floor()]];
    }
    if (cand.length <= 4) return (cand.map((m) => _Pick(m)).toList(), '');
    final files = <AiFile>[];
    final lines = <String>[];
    final idxMap = <int, Media>{};
    for (var k = 0; k < cand.length; k++) {
      final m = cand[k];
      final res = await http.get(Uri.parse(m.thumbUrl)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) continue;
      files.add(AiFile('m$k.jpg', 'image/jpeg', res.bodyBytes));
      idxMap[files.length - 1] = m;
      final it = s.items.where((i) => i.id == m.itemId).firstOrNull;
      lines.add('[${files.length - 1}] ${m.isVideo ? 'VIDEO ${(m.durationMs / 1000).round()} dtk' : 'FOTO'} · ${shortDay(m.date)} ${m.time}'
          '${it == null ? '' : ' · agenda: ${it.title}'}');
      _set('Memilih momen terbaik… ${k + 1}/${cand.length}', 0.03 + 0.05 * k / cand.length);
    }
    final scope = day == null ? 'seluruh trip "${s.tripName}"' : 'hari ${dayLabel(day)} di ${s.realCityLabel(day)}';
    final prompt = '''Kamu editor video liburan keluarga. Pilih maksimal $maxN momen terbaik untuk video recap $scope.
Gambar terlampir berurutan sesuai nomor di daftar berikut:
${lines.join('\n')}

Aturan:
- Hindari foto mirip/duplikat, buram, screenshot, struk, tiket, dokumen.
- Utamakan wajah keluarga yang ceria, pemandangan, makanan khas, suasana tempat. Masukkan beberapa VIDEO bila ada.
- ${day == null ? 'Usahakan setiap hari terwakili.' : 'Ceritakan alur hari itu dari pagi ke malam.'}
- Urutkan kronologis.
- Beri "caption" singkat Bahasa Indonesia (maks 28 karakter) HANYA saat tempat/momen berganti; selain itu kosongkan.
- Beri "title" video yang hangat (maks 30 karakter).
Jawab JSON saja: {"title":"...","picks":[{"i":0,"caption":"..."}]}''';
    final j = await Gemini.json(prompt, files: files);
    if (j is! Map) return (<_Pick>[], '');
    final out = <_Pick>[];
    final used = <int>{};
    for (final p in (j['picks'] as List? ?? const [])) {
      if (p is! Map) continue;
      final i = intOrNull(p['i']);
      if (i == null || used.contains(i) || !idxMap.containsKey(i)) continue;
      used.add(i);
      out.add(_Pick(idxMap[i]!, str(p['caption'])));
      if (out.length >= maxN) break;
    }
    return (out, str(j['title']));
  }
}
