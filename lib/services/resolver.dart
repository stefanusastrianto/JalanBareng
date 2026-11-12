import 'dart:async';

import '../models.dart';
import '../store.dart';
import 'gemini.dart';
import 'places.dart';

/// Pencari lokasi pintar: menentukan tempat Google Maps untuk setiap agenda (sekali per isi agenda).
/// Hanya place ID yang disimpan di database; detailnya diambil dari Google saat ditampilkan.
class PlaceResolver {
  PlaceResolver._();
  static final PlaceResolver I = PlaceResolver._();

  Timer? _timer;
  bool _running = false;
  bool _again = false;
  final Set<String> _failed = {};

  static const _placeTypes = {'hotel', 'makan', 'wisata', 'ibadah', 'kereta', 'pesawat'};

  bool _needs(Item i) {
    if (!_placeTypes.contains(i.type)) return false;
    if (_failed.contains('${i.id}:${i.contentKey}')) return false;
    return i.placeKey != i.contentKey;
  }

  /// Dipanggil setiap kali daftar agenda berubah.
  void schedule() {
    final s = AppState.I;
    if (!Places.enabled || s.isViewer || s.user == null) return;
    if (!s.items.any(_needs)) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), run);
  }

  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final s = AppState.I;
        final todo = s.sorted(s.items.where(_needs)).take(25).toList();
        if (todo.isEmpty) break;
        final plans = await _plan(todo);
        for (final i in todo) {
          final pl = plans[i.id] ?? _fallbackPlan(i);
          try {
            await _apply(i, pl);
          } catch (_) {
            _failed.add('${i.id}:${i.contentKey}');
          }
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }

  /// Rencana pencarian tanpa AI: pakai lokasi atau judul + kota.
  Map<String, dynamic> _fallbackPlan(Item i) {
    final city = AppState.I.realCityLabel(i.date);
    if (i.isTransport) {
      if (i.from.isNotEmpty || i.to.isNotEmpty) return {'kind': 'route', 'from': i.from, 'to': i.to};
      return {'kind': 'none'};
    }
    if (i.location.isNotEmpty) return {'kind': 'place', 'query': i.location, 'confident': true};
    return {'kind': 'suggest', 'query': '${typeOf(i.type).label} keluarga di $city'};
  }

  Future<Map<String, Map<String, dynamic>>> _plan(List<Item> todo) async {
    final s = AppState.I;
    final lines = <String>[];
    for (final i in s.sorted()) {
      final night = s.realCityLabel(i.date);
      lines.add('${i.id} | ${i.date} ${i.time} | ${i.type} | ${i.title} | lokasi: ${i.location} | dari: ${i.from} | ke: ${i.to}'
          ' | detail: ${i.detail.length > 80 ? i.detail.substring(0, 80) : i.detail} | kota hari itu: $night');
    }
    final prompt = '''Kamu asisten perjalanan keluarga di Indonesia. Berikut seluruh itinerary (urut waktu):
${lines.join('\n')}

Untuk setiap ID TARGET berikut, tentukan tempat Google Maps yang dimaksud: ${todo.map((i) => i.id).join(', ')}

Aturan:
- kereta/pesawat → "kind":"route" dengan "from" dan "to" berupa nama stasiun/bandara lengkap + kota untuk dicari di Google Maps
  (mis. "Stasiun Kereta Cepat Halim Jakarta", "Stasiun Padalarang", "Stasiun Cirebon Kejaksan"). Pakai kolom dari/ke bila ada; bila kosong, simpulkan dari judul dan alur perjalanan.
- hotel/makan/wisata/ibadah yang menyebut nama tempat spesifik → "kind":"place", "query" = nama tempat + area/kota,
  "confident": true bila nama itu jelas menunjuk satu tempat, false bila bisa banyak tempat.
- agenda generik tanpa nama tempat (mis. "Makan", "Wisata", "Hotel Solo (belum dicari)", "Gereja Cirebon") → "kind":"suggest",
  "query" = apa yang dicari dan di dekat mana (mis. "restoran keluarga dekat Swiss-Belresort Dago Heritage Bandung", "gereja katolik di Cirebon").
- tidak butuh lokasi → "kind":"none".
Jawab JSON saja: {"items":[{"id":"...","kind":"...","query":"...","from":"...","to":"...","confident":true}]}''';
    try {
      final j = await Gemini.json(prompt);
      final out = <String, Map<String, dynamic>>{};
      final list = j is Map ? (j['items'] as List? ?? const []) : (j is List ? j : const []);
      for (final e in list) {
        if (e is! Map) continue;
        final id = str(e['id']);
        if (id.isNotEmpty) out[id] = Map<String, dynamic>.from(e);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _apply(Item i, Map<String, dynamic> pl) async {
    final s = AppState.I;
    final kind = str(pl['kind']);
    final upd = <String, dynamic>{'placeKey': i.contentKey};
    if (kind == 'route') {
      final from = str(pl['from']).isNotEmpty ? str(pl['from']) : i.from;
      final to = str(pl['to']).isNotEmpty ? str(pl['to']) : i.to;
      final a = from.isEmpty ? <PlaceInfo>[] : await Places.search(from, max: 1);
      final b = to.isEmpty ? <PlaceInfo>[] : await Places.search(to, max: 1);
      if (a.isEmpty && b.isEmpty) {
        upd['placeStatus'] = 'none';
      } else {
        upd['placeStatus'] = 'route';
        upd['fromPlaceId'] = a.isEmpty ? '' : a.first.id;
        upd['toPlaceId'] = b.isEmpty ? '' : b.first.id;
        if (i.from.isEmpty && from.isNotEmpty) upd['from'] = a.isEmpty ? from : a.first.name;
        if (i.to.isEmpty && to.isNotEmpty) upd['to'] = b.isEmpty ? to : b.first.name;
      }
    } else if (kind == 'place' || kind == 'suggest') {
      final q = str(pl['query']).isEmpty ? (i.location.isEmpty ? i.title : i.location) : str(pl['query']);
      final res = await Places.search(q, max: 3);
      if (res.isEmpty) {
        upd['placeStatus'] = 'none';
      } else if (kind == 'place' && (res.length == 1 || (pl['confident'] == true && _score(q, res[0]) > _score(q, res[1])))) {
        upd['placeStatus'] = 'ok';
        upd['placeId'] = res.first.id;
      } else {
        upd['placeStatus'] = 'pick';
        upd['pickReason'] = kind == 'place' ? 'ambiguous' : 'suggest';
        upd['placeOptions'] = res.map((p) => p.id).toList();
      }
    } else {
      upd['placeStatus'] = 'none';
    }
    // Jangan menimpa bila agenda sudah diubah orang lain selama pencarian.
    final now = s.items.where((x) => x.id == i.id).firstOrNull;
    if (now == null || now.contentKey != i.contentKey) return;
    // 'from'/'to' ikut mengubah sidik; simpan sidik baru supaya tidak dicari ulang.
    final merged = Item(i.id, {...i.d, ...upd});
    upd['placeKey'] = merged.contentKey;
    await s.updateItem(i.id, upd);
  }

  static const _stop = {'gereja', 'hotel', 'stasiun', 'restoran', 'rumah', 'makan', 'jalan', 'kota', 'kabupaten', 'kecamatan'};

  /// Seberapa banyak kata penting dari pencarian yang muncul di nama + alamat hasil (0..1).
  double _score(String q, PlaceInfo p) {
    final words = q.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 4 && !_stop.contains(w)).toSet();
    if (words.isEmpty) return 0;
    final hay = '${p.name} ${p.address}'.toLowerCase();
    return words.where(hay.contains).length / words.length;
  }

  /// Pengguna memilih salah satu opsi.
  Future<void> choose(Item i, PlaceInfo p) async {
    final s = AppState.I;
    final upd = <String, dynamic>{'placeStatus': 'ok', 'placeId': p.id, 'placeOptions': [], 'pickReason': ''};
    if (i.pickReason == 'suggest') {
      upd['title'] = switch (i.type) {
        'makan' => 'Makan di ${p.name}',
        _ => p.name,
      };
    }
    upd['location'] = '${p.name}, ${p.address}';
    final merged = Item(i.id, {...i.d, ...upd});
    upd['placeKey'] = merged.contentKey;
    final prev = {
      'title': i.d['title'],
      'location': i.d['location'],
      'placeId': i.d['placeId'],
      'placeStatus': i.d['placeStatus'],
      'placeOptions': i.d['placeOptions'],
      'pickReason': i.d['pickReason'],
      'placeKey': i.d['placeKey'],
    };
    await s.updateItem(i.id, upd);
    await s.addMessage({
      'role': 'assistant',
      'author': s.email,
      'authorName': 'Asisten',
      'text': '${s.myName} memilih ${p.name} untuk ${i.title} (${dayLabel(i.date)}).',
      'actions': [
        {'op': 'update', 'id': i.id, 'prev': prev, 'label': '${i.title} → ${p.name}'}
      ],
      'processed': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Minta dicarikan ulang (mis. bila pilihan tidak ada yang cocok).
  Future<void> retry(Item i) async {
    _failed.removeWhere((k) => k.startsWith('${i.id}:'));
    await AppState.I.updateItem(i.id, {'placeKey': '', 'placeStatus': ''});
  }
}
