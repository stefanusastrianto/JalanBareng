import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'config.dart';
import 'models.dart';
import 'services/notifications.dart';
import 'services/resolver.dart';

/// Satu-satunya sumber data aplikasi. Firestore menyimpan salinan di HP,
/// jadi semua data tetap bisa dibuka tanpa sinyal dan sinkron saat online.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  final FirebaseFirestore db = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get tripRef => db.collection('trips').doc(Config.tripId);
  CollectionReference<Map<String, dynamic>> col(String name) => tripRef.collection(name);

  User? user;
  String get email => (user?.email ?? '').toLowerCase();

  Map<String, dynamic>? trip;
  bool tripLoaded = false;
  bool tripMissing = false;
  String? accessError;
  bool fromCache = false;
  String? dataError;

  List<Item> items = [];
  List<Expense> expenses = [];
  List<Member> members = [];
  List<Msg> messages = [];
  List<Media> media = [];
  List<Recap> recaps = [];
  List<String> skippedAssets = [];

  /// Rute yang diminta dari notifikasi, mis. "recap:2026-12-18" atau "recap:trip".
  String? pendingRoute;
  void openRoute(String? r) {
    if (r == null || r.isEmpty) return;
    pendingRoute = r;
    notifyListeners();
  }

  bool busy = false;
  String typing = '';
  String? focusDay;

  final List<StreamSubscription> _subs = [];
  bool _colsOn = false;
  Timer? _notifTimer;

  // ---------- lifecycle ----------
  void begin(User u) {
    user = u;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _colsOn = false;
    tripLoaded = false;
    _subs.add(tripRef.snapshots(includeMetadataChanges: true).listen((s) {
      trip = s.data();
      tripLoaded = true;
      tripMissing = !s.exists && !s.metadata.isFromCache;
      fromCache = s.metadata.isFromCache;
      accessError = null;
      if (s.exists) _listenCollections();
      notifyListeners();
    }, onError: (Object e) {
      tripLoaded = true;
      accessError = e.toString();
      notifyListeners();
    }));
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _colsOn = false;
    user = null;
    trip = null;
    items = [];
    expenses = [];
    members = [];
    messages = [];
    media = [];
    recaps = [];
    skippedAssets = [];
    tripLoaded = false;
    notifyListeners();
  }

  void _listenCollections() {
    if (_colsOn) return;
    _colsOn = true;
    _subs.add(col('items').snapshots().listen((q) {
      dataError = null;
      items = q.docs.map((d) => Item(d.id, d.data())).toList();
      notifyListeners();
      _notifTimer?.cancel();
      _notifTimer = Timer(const Duration(seconds: 3), () => NotificationService.I.reschedule(this));
      PlaceResolver.I.schedule();
    }, onError: (Object e) {
      dataError = 'Agenda tidak bisa dibaca: $e. Cek aturan Firestore (README langkah 3).';
      notifyListeners();
    }));
    _subs.add(col('expenses').snapshots().listen((q) {
      expenses = q.docs.map((d) => Expense(d.id, d.data())).toList();
      notifyListeners();
    }));
    _subs.add(col('members').snapshots().listen((q) {
      members = q.docs.map((d) => Member(d.id, d.data())).toList();
      notifyListeners();
    }));
    _subs.add(col('media').snapshots().listen((q) {
      media = q.docs.map((d) => Media(d.id, d.data())).toList()..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      notifyListeners();
    }));
    _subs.add(col('recaps').snapshots().listen((q) {
      recaps = q.docs.map((d) => Recap(d.id, d.data())).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }));
    if (email.isNotEmpty) {
      _subs.add(col('prefs').doc(email).snapshots().listen((d) {
        skippedAssets = ((d.data()?['skippedAssets'] as List?) ?? const []).map((e) => e.toString()).toList();
        notifyListeners();
      }, onError: (_) {}));
    }
    _subs.add(col('messages').orderBy('createdAt', descending: true).limit(120).snapshots().listen((q) {
      messages = q.docs.map((d) => Msg(d.id, d.data())).toList().reversed.toList();
      notifyListeners();
    }));
  }

  // ---------- derived ----------
  String get adminEmail => str(trip?['adminEmail']).toLowerCase();
  bool get isAdmin => email.isNotEmpty && email == adminEmail;
  String get tripName => str(trip?['name']).isEmpty ? 'Jalan Bareng' : str(trip?['name']);
  String get start => str(trip?['start']);
  String get end => str(trip?['end']);
  String get geminiModel => str(trip?['geminiModel']).isEmpty ? Config.geminiModelDefault : str(trip?['geminiModel']);
  List<String> get syncedEmailIds => ((trip?['syncedEmailIds'] as List?) ?? const []).map((e) => e.toString()).toList();

  Member? get me {
    for (final m in members) {
      if (m.email == email) return m;
    }
    return null;
  }

  String get myName {
    final m = me;
    if (m != null && m.name.isNotEmpty) return m.name;
    return user?.displayName ?? 'Anggota';
  }

  String nameOfEmail(String e) {
    final low = e.toLowerCase();
    for (final m in members) {
      if (m.email == low && m.name.isNotEmpty) return m.name;
    }
    return e.isEmpty ? 'Seseorang' : e.split('@').first;
  }

  bool get isViewer => me?.role == 'pengamat';

  List<Item> sorted([Iterable<Item>? src]) {
    final l = (src ?? items).toList();
    l.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      final o = a.order.compareTo(b.order);
      if (o != 0) return o;
      return a.createdAt.compareTo(b.createdAt);
    });
    return l;
  }

  List<Item> itemsOn(String day) => sorted(items.where((i) => i.date == day));

  List<String> tripDays() {
    final set = <String>{...items.map((i) => i.date).where((d) => d.isNotEmpty)};
    if (start.isNotEmpty && end.isNotEmpty) {
      var d = parseIso(start);
      final e = parseIso(end);
      var n = 0;
      while (!d.isAfter(e) && n < 120) {
        set.add(isoDate(d));
        d = DateTime(d.year, d.month, d.day + 1);
        n++;
      }
    }
    final l = set.toList()..sort();
    return l;
  }

  List<String> activeDays() => tripDays().where((d) => items.any((i) => i.date == d)).toList();

  String cityFor(String day) {
    final map = (trip?['dayCities'] as Map?) ?? const {};
    final v = map[day];
    if (v is String && v.isNotEmpty) return v;
    String? last;
    for (final d in tripDays()) {
      if (d.compareTo(day) > 0) break;
      final txt = items.where((i) => i.date == d).map((i) => '${i.title} ${i.location} ${i.detail}').join(' ');
      String? found;
      var pos = -1;
      kCities.forEach((k, c) {
        final re = c.re;
        if (re == null) return;
        final m = re.firstMatch(txt);
        if (m != null && m.start >= pos) {
          found = k;
          pos = m.start;
        }
      });
      if (found != null) last = found;
      if (d == day) {
        if (RegExp(r'-12-2[45]$').hasMatch(d)) return 'natal';
        return last ?? 'jalan';
      }
    }
    return last ?? 'jalan';
  }

  String realCity(String day) {
    final c = cityFor(day);
    if (kCities[c]?.re != null) return c;
    final days = tripDays().where((x) => x.compareTo(day) < 0).toList().reversed;
    for (final d in days) {
      final k = cityFor(d);
      if (kCities[k]?.re != null) return k;
    }
    return c;
  }

  String cityLabel(String day) => kCities[cityFor(day)]?.label ?? '';
  String realCityLabel(String day) => kCities[realCity(day)]?.label ?? '';

  List<Msg> get pending => messages.where((m) => m.role == 'user' && !m.processed).toList();
  int get todoBookings => items.where((i) => i.needsBooking && !i.booked).length;

  // ---------- media ----------
  List<Media> mediaOn(String day) => media.where((m) => m.date == day).toList();
  List<Media> mediaForItem(String itemId) => media.where((m) => m.itemId == itemId).toList();
  Set<String> get myUploadedAssets => media.where((m) => m.by == email && m.assetId.isNotEmpty).map((m) => m.assetId).toSet();

  /// Agenda yang sedang berlangsung pada jam itu: agenda terakhir yang mulai sebelum (atau 15 menit setelah) jam foto.
  String matchItem(String day, int minute) {
    Item? best;
    for (final i in itemsOn(day)) {
      final m = mins(i.time);
      if (m == null) continue;
      if (m <= minute + 15) best = i;
    }
    return best?.id ?? '';
  }

  bool inTrip(DateTime t) {
    if (start.length < 10 || end.length < 10) return false;
    final d = isoDate(t);
    return d.compareTo(start) >= 0 && d.compareTo(end) <= 0;
  }

  Future<void> skipAssets(Iterable<String> ids) async {
    final all = {...skippedAssets, ...ids}.toList();
    await col('prefs').doc(email).set({'skippedAssets': all}, SetOptions(merge: true));
  }

  // ---------- writes ----------
  Future<String> addItem(Map<String, dynamic> data) async {
    final ref = await col('items').add(data);
    return ref.id;
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) => col('items').doc(id).update(data);
  Future<void> setItem(String id, Map<String, dynamic> data) => col('items').doc(id).set(data);
  Future<void> deleteItemDoc(String id) => col('items').doc(id).delete();

  Future<String> addExpense(Map<String, dynamic> data) async => (await col('expenses').add(data)).id;
  Future<void> updateExpense(String id, Map<String, dynamic> data) => col('expenses').doc(id).update(data);
  Future<void> deleteExpense(String id) => col('expenses').doc(id).delete();

  Future<String> addMessage(Map<String, dynamic> data) async => (await col('messages').add(data)).id;
  Future<void> updateMessage(String id, Map<String, dynamic> data) => col('messages').doc(id).update(data);

  Future<void> updateTrip(Map<String, dynamic> data) => tripRef.update(data);

  /// Hapus agenda dan tinggalkan catatan di chat supaya bisa dibatalkan.
  Future<void> deleteItem(Item i) async {
    await deleteItemDoc(i.id);
    await addMessage({
      'role': 'assistant',
      'author': email,
      'authorName': myName,
      'text': '$myName menghapus agenda ${i.title} (${dayLabel(i.date)}).',
      'actions': [
        {'op': 'delete', 'id': i.id, 'label': 'Agenda dihapus: ${i.title}', 'snapshot': i.d}
      ],
      'processed': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ---------- members ----------
  Future<void> saveMember(Member? m, String name, String mail, String phone, String role) async {
    final data = {'name': name, 'email': mail.toLowerCase().trim(), 'phone': phone, 'role': role};
    if (m == null) {
      await col('members').add({...data, 'createdAt': DateTime.now().millisecondsSinceEpoch});
    } else {
      await col('members').doc(m.id).update(data);
      if (m.email.isNotEmpty && m.email != data['email']) {
        await tripRef.update({'memberEmails': FieldValue.arrayRemove([m.email])});
      }
    }
    if ((data['email'] as String).isNotEmpty) {
      await tripRef.update({'memberEmails': FieldValue.arrayUnion([data['email']])});
    }
  }

  Future<void> deleteMember(Member m) async {
    await col('members').doc(m.id).delete();
    if (m.email.isNotEmpty) await tripRef.update({'memberEmails': FieldValue.arrayRemove([m.email])});
  }

  Future<void> makeAdmin(Member m) => tripRef.update({'adminEmail': m.email});

  // ---------- files (foto e-tiket / struk, disimpan kecil di Firestore agar tersedia offline) ----------
  Future<String?> saveFile(String name, String mime, Uint8List bytes) async {
    if (bytes.length > 700 * 1024) return null;
    final ref = await col('files').add({
      'name': name,
      'mime': mime,
      'data': base64Encode(bytes),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'by': email,
    });
    return ref.id;
  }

  Future<Map<String, dynamic>?> getFile(String id) async {
    final s = await col('files').doc(id).get();
    return s.data();
  }

  // ---------- import from the web version ----------
  /// Impor data dari versi web (assets/seed.json). Aman diulang: agenda dan pengeluaran ditulis
  /// berdasarkan ID-nya, daftar anggota dan admin tidak diubah bila trip sudah ada.
  /// Ditulis bertahap (8 per paket) supaya tidak melewati batas pengecekan aturan Firestore.
  Future<String> importSeed() async {
    final raw = await rootBundle.loadString('assets/seed.json');
    final seed = jsonDecode(raw) as Map<String, dynamic>;
    final t = Map<String, dynamic>.from(seed['trip'] as Map);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await tripRef.get();
    if (!existing.exists) {
      await tripRef.set({
        ...t,
        'memberEmails': [email],
        'adminEmail': email,
        'geminiModel': Config.geminiModelDefault,
        'createdAt': now,
      });
    } else {
      final old = existing.data() ?? {};
      final ids = {...((old['syncedEmailIds'] as List?) ?? const []), ...((t['syncedEmailIds'] as List?) ?? const [])}.toList();
      await tripRef.update({
        'name': t['name'],
        'start': t['start'],
        'end': t['end'],
        'dayCities': t['dayCities'],
        'syncedEmailIds': ids,
      });
    }

    final writes = <void Function(WriteBatch)>[];
    final hasMembers = (await col('members').limit(1).get()).docs.isNotEmpty;
    if (!hasMembers) {
      final seedMembers = (seed['members'] as List).cast<Map>();
      for (var k = 0; k < seedMembers.length; k++) {
        final m = Map<String, dynamic>.from(seedMembers[k]);
        final isAdminSeed = m['role'] == 'admin';
        final data = {
          'name': isAdminSeed ? (user?.displayName?.split(' ').first ?? m['name']) : m['name'],
          'email': isAdminSeed ? email : '',
          'phone': '',
          'role': 'anggota',
          'createdAt': now + k,
        };
        writes.add((b) => b.set(col('members').doc(), data));
      }
    }
    final items = (seed['items'] as Map);
    items.forEach((id, v) {
      final data = Map<String, dynamic>.from(v as Map);
      writes.add((b) => b.set(col('items').doc(id as String), data));
    });
    final exps = (seed['expenses'] as Map);
    exps.forEach((id, v) {
      final data = {...Map<String, dynamic>.from(v as Map), 'createdBy': email};
      writes.add((b) => b.set(col('expenses').doc(id as String), data));
    });
    for (var k = 0; k < writes.length; k += 8) {
      final batch = db.batch();
      for (final w in writes.skip(k).take(8)) {
        w(batch);
      }
      await batch.commit();
    }
    final msg = 'Data trip diimpor dari versi web: ${items.length} agenda dan ${exps.length} pengeluaran.';
    await col('messages').add({
      'role': 'assistant',
      'author': email,
      'authorName': 'Jalan Bareng',
      'text': msg,
      'actions': [],
      'processed': true,
      'createdAt': now,
    });
    return msg;
  }

  Future<void> createEmptyTrip(String name, String startDate, String endDate) async {
    await tripRef.set({
      'name': name,
      'start': startDate,
      'end': endDate,
      'memberEmails': [email],
      'adminEmail': email,
      'geminiModel': Config.geminiModelDefault,
      'syncedEmailIds': [],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await col('members').add({
      'name': user?.displayName?.split(' ').first ?? 'Admin',
      'email': email,
      'phone': '',
      'role': 'anggota',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void setBusy(bool b, [String t = '']) {
    busy = b;
    typing = t;
    notifyListeners();
  }
}
