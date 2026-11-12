import 'package:flutter/material.dart';

String str(dynamic v) => v == null ? '' : v.toString();
int? intOrNull(dynamic v) {
  if (v == null || v == '') return null;
  if (v is int) return v;
  if (v is num) return v.round();
  return parseRupiah(v.toString());
}

class TypeInfo {
  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  const TypeInfo(this.label, this.icon, this.color, this.bg);
}

const kTypes = <String, TypeInfo>{
  'kereta': TypeInfo('Kereta', Icons.train_outlined, Color(0xFF3E9FD8), Color(0xFFE2F2FC)),
  'pesawat': TypeInfo('Pesawat', Icons.flight_outlined, Color(0xFF3E9FD8), Color(0xFFE2F2FC)),
  'mobil': TypeInfo('Mobil / Grab', Icons.directions_car_outlined, Color(0xFF0E9C8A), Color(0xFFDDF4EF)),
  'hotel': TypeInfo('Hotel', Icons.hotel_outlined, Color(0xFF6A55D8), Color(0xFFEDE8FF)),
  'makan': TypeInfo('Makan', Icons.restaurant_outlined, Color(0xFFC97A00), Color(0xFFFFF0D6)),
  'wisata': TypeInfo('Wisata', Icons.photo_camera_outlined, Color(0xFFF2704F), Color(0xFFFFE9E2)),
  'ibadah': TypeInfo('Ibadah', Icons.church_outlined, Color(0xFFC2456E), Color(0xFFFCE7EE)),
  'istirahat': TypeInfo('Istirahat', Icons.weekend_outlined, Color(0xFF0E9C8A), Color(0xFFDDF4EF)),
  'tujuan': TypeInfo('Pindah kota', Icons.place_outlined, Color(0xFFF2704F), Color(0xFFFFE9E2)),
  'lainnya': TypeInfo('Lainnya', Icons.more_horiz, Color(0xFF667D7A), Color(0xFFEEF4F2)),
};
TypeInfo typeOf(String t) => kTypes[t] ?? kTypes['lainnya']!;
String catOf(String t) => kTypes.containsKey(t) ? t : 'lainnya';

class CityInfo {
  final String label;
  final RegExp? re;
  const CityInfo(this.label, [this.re]);
}

final kCities = <String, CityInfo>{
  'bandung': CityInfo('Bandung', RegExp(r'bandung|lembang|ciwidey|dago', caseSensitive: false)),
  'cirebon': CityInfo('Cirebon', RegExp(r'cirebon|kasepuhan|trusmi', caseSensitive: false)),
  'kuningan': CityInfo('Kuningan', RegExp(r'kuningan|linggarjati|ciremai|cilimus', caseSensitive: false)),
  'solo': CityInfo('Solo', RegExp(r'\bsolo\b|surakarta', caseSensitive: false)),
  'klaten': CityInfo('Klaten', RegExp(r'klaten|prambanan', caseSensitive: false)),
  'jogja': CityInfo('Yogyakarta', RegExp(r'jogja|yogya', caseSensitive: false)),
  'jakarta': CityInfo('Jakarta', RegExp(r'jakarta|gambir|pasar senen|halim', caseSensitive: false)),
  'natal': const CityInfo('Natal'),
  'istirahat': const CityInfo('Santai'),
  'pulang': const CityInfo('Perjalanan pulang'),
  'jalan': const CityInfo('Dalam perjalanan'),
};

class Item {
  final String id;
  final Map<String, dynamic> d;
  Item(this.id, this.d);
  String get title => str(d['title']).isEmpty ? '(tanpa judul)' : str(d['title']);
  String get date => str(d['date']);
  String get time => str(d['time']);
  String get endTime => str(d['endTime']);
  String get type => catOf(str(d['type']));
  String get location => str(d['location']);
  String get detail => str(d['detail']);
  String get bookingCode => str(d['bookingCode']);
  String get bookingName => str(d['bookingName']);
  String get bookingNote => str(d['bookingNote']);
  String get bookedVia => str(d['bookedVia']);
  String get bookedBy => str(d['bookedBy']);
  String get placeId => str(d['placeId']);
  String get fileId => str(d['fileId']);
  int? get cost => intOrNull(d['cost']);
  bool get booked => d['booked'] == true;
  num get order => (d['order'] is num) ? d['order'] as num : 9999;
  num get createdAt => (d['createdAt'] is num) ? d['createdAt'] as num : 0;
  bool get needsBooking {
    final v = d['needsBooking'];
    if (v is bool) return v;
    return ['kereta', 'pesawat', 'hotel'].contains(type) ||
        (type == 'mobil' && RegExp(r'sewa|rental', caseSensitive: false).hasMatch(str(d['title'])));
  }

  bool get isOpen => ['hotel', 'makan', 'wisata'].contains(type) && location.isEmpty && !booked;
}

class Expense {
  final String id;
  final Map<String, dynamic> d;
  Expense(this.id, this.d);
  int get amount => intOrNull(d['amount']) ?? 0;
  String get date => str(d['date']);
  String get merchant => str(d['merchant']);
  String get category => catOf(str(d['category']));
  String get paidBy => str(d['paidBy']);
  String get note => str(d['note']);
  String get itemId => str(d['itemId']);
  String get via => str(d['via']);
  String get fileId => str(d['fileId']);
  num get createdAt => (d['createdAt'] is num) ? d['createdAt'] as num : 0;
}

class Member {
  final String id;
  final Map<String, dynamic> d;
  Member(this.id, this.d);
  String get name => str(d['name']);
  String get email => str(d['email']).toLowerCase();
  String get phone => str(d['phone']);
  String get role => str(d['role']).isEmpty ? 'anggota' : str(d['role']);
}

class Msg {
  final String id;
  final Map<String, dynamic> d;
  Msg(this.id, this.d);
  String get role => str(d['role']);
  String get author => str(d['author']);
  String get authorName => str(d['authorName']);
  String get text => str(d['text']);
  String get contextLabel => str(d['contextLabel']);
  bool get processed => d['processed'] != false;
  bool get undone => d['undone'] == true;
  List<Map<String, dynamic>> get actions =>
      ((d['actions'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  List<Map<String, dynamic>> get attachments =>
      ((d['attachments'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic>? get context => d['context'] is Map ? Map<String, dynamic>.from(d['context'] as Map) : null;
  num get createdAt => (d['createdAt'] is num) ? d['createdAt'] as num : 0;
}

// ---------- date & number helpers ----------
const kHari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const kBulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String two(int n) => n.toString().padLeft(2, '0');
String isoDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseIso(String s) {
  final p = s.split('-');
  if (p.length < 3) return DateTime.now();
  return DateTime(int.tryParse(p[0]) ?? 2026, int.tryParse(p[1]) ?? 1, int.tryParse(p[2]) ?? 1);
}

String dayLabel(String s) {
  final d = parseIso(s);
  return '${kHari[d.weekday - 1]}, ${d.day} ${kBulan[d.month - 1]}';
}

String shortDay(String s) {
  final d = parseIso(s);
  return '${d.day} ${kBulan[d.month - 1]}';
}

int? mins(String t) {
  final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(t);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

String normTime(dynamic t) {
  final m = mins(str(t));
  if (m == null) return '';
  return '${two(m ~/ 60)}:${two(m % 60)}';
}

num orderFor(String t) => mins(t) ?? 1200;

String rp(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}Rp$b';
}

String rpShort(num n) {
  final a = n.abs();
  final sign = n < 0 ? '-' : '';
  if (a >= 1000000) {
    final v = (a / 1000000);
    final txt = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2).replaceAll('.', ',');
    return '${sign}Rp$txt jt';
  }
  return '${sign}Rp${(a / 1000).round()} rb';
}

/// "1,5jt" -> 1500000, "800rb" -> 800000, "1.300.000" -> 1300000
int? parseRupiah(String raw) {
  final r = raw.trim().toLowerCase();
  if (r.isEmpty) return null;
  final mult = RegExp(r'jt|juta').hasMatch(r)
      ? 1000000
      : RegExp(r'rb|ribu|\dk\b').hasMatch(r)
          ? 1000
          : 0;
  if (mult > 0) {
    var s = r.replaceAll(RegExp(r'[^\d.,]'), '');
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (!RegExp(r'^\d+\.\d{1,2}$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    }
    final n = double.tryParse(s);
    return n == null ? null : (n * mult).round();
  }
  final digits = r.replaceAll(RegExp(r'[^\d]'), '');
  return digits.isEmpty ? null : int.parse(digits);
}

String waNumber(String p) {
  var d = p.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0')) d = '62${d.substring(1)}';
  return d;
}
