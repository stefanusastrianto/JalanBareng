import 'dart:convert';

import 'package:http/http.dart' as http;

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

  factory PlaceInfo.fromJson(Map<String, dynamic> j) {
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

/// Google Places API (New). Data Google tidak disimpan di database; hanya place ID yang disimpan.
class Places {
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
    for (final p in list) {
      _detailCache[p.id] = p;
    }
    return list;
  }

  static Future<PlaceInfo?> details(String id) async {
    if (!enabled || id.isEmpty) return null;
    final hit = _detailCache[id];
    if (hit != null) return hit;
    final res = await http
        .get(Uri.parse('https://places.googleapis.com/v1/places/$id?languageCode=id'),
            headers: {..._headers, 'X-Goog-FieldMask': _fields})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) return null;
    final p = PlaceInfo.fromJson(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
    _detailCache[id] = p;
    return p;
  }

  static String photoUrl(String photoName, {int width = 480}) =>
      'https://places.googleapis.com/v1/$photoName/media?maxWidthPx=$width&key=${Config.placesKey}';

  static Map<String, String> get photoHeaders => androidKeyHeaders();
}
