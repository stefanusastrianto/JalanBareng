import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'gemini.dart' show androidKeyHeaders;

class PlaceInfo {
  final String id;
  final String name;
  final String address;
  final double? rating;
  final int? ratingCount;
  final String mapsUri;
  final String? photoName;
  final String photoAuthor;
  PlaceInfo({
    required this.id,
    required this.name,
    required this.address,
    this.rating,
    this.ratingCount,
    required this.mapsUri,
    this.photoName,
    this.photoAuthor = '',
  });

  /// Bentuk asli respons Google (dipakai untuk cache sementara di HP).
  Map<String, dynamic> raw = const {};

  factory PlaceInfo.fromJson(Map<String, dynamic> j) => PlaceInfo._parse(j)..raw = j;

  factory PlaceInfo._parse(Map<String, dynamic> j) {
    final photos = (j['photos'] as List?) ?? const [];
    String? photo;
    var author = '';
    if (photos.isNotEmpty) {
      final p = photos.first as Map;
      photo = p['name']?.toString();
      final atts = (p['authorAttributions'] as List?) ?? const [];
      if (atts.isNotEmpty) author = (atts.first as Map)['displayName']?.toString() ?? '';
    }
    final id = j['id']?.toString() ?? '';
    return PlaceInfo(
      id: id,
      name: ((j['displayName'] as Map?)?['text'])?.toString() ?? '',
      address: j['formattedAddress']?.toString() ?? '',
      rating: (j['rating'] is num) ? (j['rating'] as num).toDouble() : null,
      ratingCount: (j['userRatingCount'] is num) ? (j['userRatingCount'] as num).toInt() : null,
      mapsUri: j['googleMapsUri']?.toString() ?? 'https://www.google.com/maps/place/?q=place_id:$id',
      photoName: photo,
      photoAuthor: author,
    );
  }
}

/// Google Places API (New). Data Google tidak disimpan di database bersama; hanya place ID yang disimpan.
/// Detail tempat disimpan sementara di HP (maks. 30 hari) supaya hemat kuota dan cepat dibuka.
class Places {
  static const _ttl = Duration(days: 30);
  static Map<String, dynamic>? _disk;
  static Timer? _saveTimer;

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/places_cache.json');

  static Future<void> _loadDisk() async {
    if (_disk != null) return;
    try {
      final f = await _file();
      _disk = f.existsSync() ? Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map) : {};
    } catch (_) {
      _disk = {};
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _disk!.removeWhere((k, v) => v is! Map || now - ((v['t'] as num?) ?? 0) > _ttl.inMilliseconds);
  }

  static void _remember(PlaceInfo p) {
    _detailCache[p.id] = p;
    if (_disk == null || p.raw.isEmpty) return;
    _disk![p.id] = {'t': DateTime.now().millisecondsSinceEpoch, 'j': p.raw};
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await (await _file()).writeAsString(jsonEncode(_disk));
      } catch (_) {}
    });
  }

  /// Detail yang sudah ada di memori (tanpa jaringan), untuk tampilan instan.
  static PlaceInfo? cached(String id) => _detailCache[id];

  static const _fields = 'id,displayName,formattedAddress,rating,userRatingCount,googleMapsUri,photos';
  static final Map<String, List<PlaceInfo>> _searchCache = {};
  static final Map<String, PlaceInfo> _detailCache = {};

  static bool get enabled => Config.placesKey.isNotEmpty;

  static Map<String, String> get _headers =>
      {'Content-Type': 'application/json', 'X-Goog-Api-Key': Config.placesKey, ...androidKeyHeaders()};

  static Future<List<PlaceInfo>> search(String query, {int max = 3}) async {
    if (!enabled || query.trim().isEmpty) return [];
    final key = '$query|$max';
    final hit = _searchCache[key];
    if (hit != null) return hit;
    final res = await http
        .post(Uri.parse('https://places.googleapis.com/v1/places:searchText'),
            headers: {..._headers, 'X-Goog-FieldMask': _fields.split(',').map((f) => 'places.$f').join(',')},
            body: jsonEncode({'textQuery': query, 'languageCode': 'id', 'regionCode': 'ID', 'maxResultCount': max}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) throw Exception('Google Places ${res.statusCode}');
    final list = ((jsonDecode(res.body) as Map)['places'] as List? ?? const [])
        .map((e) => PlaceInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _searchCache[key] = list;
    await _loadDisk();
    for (final p in list) {
      _remember(p);
    }
    return list;
  }

  static Future<PlaceInfo?> details(String id) async {
    if (!enabled || id.isEmpty) return null;
    final hit = _detailCache[id];
    if (hit != null) return hit;
    await _loadDisk();
    final d = _disk![id];
    if (d is Map && d['j'] is Map) {
      final p = PlaceInfo.fromJson(Map<String, dynamic>.from(d['j'] as Map));
      _detailCache[id] = p;
      return p;
    }
    final res = await http
        .get(Uri.parse('https://places.googleapis.com/v1/places/$id?languageCode=id'),
            headers: {..._headers, 'X-Goog-FieldMask': _fields})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) return null;
    final p = PlaceInfo.fromJson(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    _remember(p);
    return p;
  }

  static String photoUrl(String photoName, {int width = 480}) =>
      'https://places.googleapis.com/v1/$photoName/media?maxWidthPx=$width&key=${Config.placesKey}';

  static Map<String, String> get photoHeaders => androidKeyHeaders();
}
