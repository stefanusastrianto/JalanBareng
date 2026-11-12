import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models.dart';
import '../store.dart';

/// Jembatan ke kode Android (Media3) untuk kompres video dan merakit video recap.
class VideoNative {
  static const _ch = MethodChannel('jalanbareng/video');

  static Future<String> compress(String input, String output, int width, int height) async {
    final r = await _ch.invokeMethod<String>('compress', {'input': input, 'output': output, 'width': width, 'height': height});
    return r ?? output;
  }

  static Future<String> recap(String specJson) async {
    final r = await _ch.invokeMethod<String>('recap', {'spec': specJson});
    return r ?? '';
  }

  /// 0..100, atau -1 bila belum tersedia.
  static Future<int> progress() async {
    try {
      return await _ch.invokeMethod<int>('progress') ?? -1;
    } catch (_) {
      return -1;
    }
  }
}

/// Satu kandidat dari galeri HP.
class DeviceAsset {
  final AssetEntity a;
  DeviceAsset(this.a);
  String get id => a.id;
  bool get isVideo => a.type == AssetType.video;
  DateTime get taken => a.createDateTime;
  String get day => isoDate(taken);
}

/// Membaca galeri HP, mengunggah foto/video ke Firebase Storage, dan mencatatnya di timeline.
class MediaService extends ChangeNotifier {
  MediaService._();
  static final MediaService I = MediaService._();

  final FirebaseStorage storage = FirebaseStorage.instance;

  // status unggah
  final List<DeviceAsset> _queue = [];
  bool uploading = false;
  int total = 0;
  int done = 0;
  int failed = 0;
  String current = '';
  String? lastError;

  // hasil pemindaian galeri HP
  List<DeviceAsset> found = [];
  bool scanning = false;
  bool? permitted;

  int get newCount {
    final s = AppState.I;
    final skip = s.skippedAssets.toSet();
    final up = s.myUploadedAssets;
    return found.where((f) => !skip.contains(f.id) && !up.contains(f.id) && !_queue.any((q) => q.id == f.id)).length;
  }

  List<DeviceAsset> get newAssets {
    final s = AppState.I;
    final skip = s.skippedAssets.toSet();
    final up = s.myUploadedAssets;
    return found.where((f) => !skip.contains(f.id) && !up.contains(f.id)).toList();
  }

  Future<bool> requestPermission() async {
    final ps = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: true),
      ),
    );
    permitted = ps.hasAccess;
    notifyListeners();
    return ps.hasAccess;
  }

  /// Cari foto/video di HP yang diambil selama tanggal trip. [ask]=false: tidak memunculkan dialog izin.
  Future<void> scan({bool ask = true}) async {
    final s = AppState.I;
    if (s.start.length < 10 || s.end.length < 10 || scanning) return;
    if (!ask) {
      final st = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(type: RequestType.common, mediaLocation: true),
        ),
      );
      if (!st.hasAccess) {
        permitted = false;
        notifyListeners();
        return;
      }
    } else if (!await requestPermission()) {
      return;
    }
    permitted = true;
    scanning = true;
    notifyListeners();
    try {
      final from = parseIso(s.start);
      final e = parseIso(s.end);
      final to = DateTime(e.year, e.month, e.day, 23, 59, 59);
      final filter = FilterOptionGroup(
        createTimeCond: DateTimeCond(min: from, max: to),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: true)],
      );
      final paths = await PhotoManager.getAssetPathList(type: RequestType.common, onlyAll: true, filterOption: filter);
      final list = <DeviceAsset>[];
      if (paths.isNotEmpty) {
        final n = await paths.first.assetCountAsync;
        final assets = await paths.first.getAssetListRange(start: 0, end: n);
        for (final a in assets) {
          if (a.type != AssetType.image && a.type != AssetType.video) continue;
          if (!s.inTrip(a.createDateTime)) continue;
          list.add(DeviceAsset(a));
        }
      }
      found = list;
    } catch (e) {
      lastError = 'Gagal membaca galeri: $e';
    }
    scanning = false;
    notifyListeners();
  }

  void enqueue(List<DeviceAsset> list) {
    final have = {..._queue.map((q) => q.id), ...AppState.I.myUploadedAssets};
    for (final a in list) {
      if (!have.contains(a.id)) _queue.add(a);
    }
    total = done + failed + _queue.length;
    notifyListeners();
    _run();
  }

  Future<void> _run() async {
    if (uploading) return;
    uploading = true;
    lastError = null;
    notifyListeners();
    while (_queue.isNotEmpty) {
      final a = _queue.first;
      current = '${a.isVideo ? 'Video' : 'Foto'} ${shortDay(a.day)} ${two(a.taken.hour)}:${two(a.taken.minute)}';
      notifyListeners();
      try {
        await _uploadOne(a);
        done++;
      } catch (e) {
        failed++;
        lastError = e.toString();
      }
      _queue.removeAt(0);
      notifyListeners();
    }
    uploading = false;
    current = '';
    if (failed == 0) {
      total = 0;
      done = 0;
    }
    notifyListeners();
  }

  void resetCounters() {
    if (uploading) return;
    total = 0;
    done = 0;
    failed = 0;
    lastError = null;
    notifyListeners();
  }

  Future<void> _uploadOne(DeviceAsset da) async {
    final s = AppState.I;
    final a = da.a;
    final ref = s.col('media').doc();
    final id = ref.id;
    final taken = a.createDateTime;
    final day = isoDate(taken);
    final minute = taken.hour * 60 + taken.minute;
    double? lat;
    double? lng;
    try {
      final ll = await a.latlngAsync();
      final la = ll?.latitude;
      final lo = ll?.longitude;
      if (la != null && lo != null && (la != 0 || lo != 0)) {
        lat = la;
        lng = lo;
      }
    } catch (_) {}

    final thumb = await a.thumbnailDataWithSize(const ThumbnailSize(480, 480), quality: 75);
    if (thumb == null) throw Exception('Gagal membuat thumbnail');
    final thumbPath = 'trip/thumbs/$id.jpg';
    final thumbRef = storage.ref(thumbPath);
    await thumbRef.putData(thumb, SettableMetadata(contentType: 'image/jpeg'));
    final thumbUrl = await thumbRef.getDownloadURL();

    final file = await a.originFile ?? await a.file;
    if (file == null) throw Exception('File asli tidak ditemukan di HP');
    final tmp = await getTemporaryDirectory();
    String path;
    var w = a.orientatedWidth;
    var h = a.orientatedHeight;
    if (da.isVideo) {
      final portrait = h > w;
      // Maksimal 1280 px di sisi panjang (720p) supaya hemat kuota dan cepat diunggah.
      final tw = portrait ? 720 : 1280;
      final th = portrait ? 1280 : 720;
      final out = '${tmp.path}/up_$id.mp4';
      final useW = w > 0 && w < tw ? w : tw;
      final useH = h > 0 && h < th ? h : th;
      await VideoNative.compress(file.path, out, useW, useH);
      path = 'trip/media/$id.mp4';
      final r = storage.ref(path);
      await r.putFile(File(out), SettableMetadata(contentType: 'video/mp4'));
      final url = await r.getDownloadURL();
      try {
        File(out).deleteSync();
      } catch (_) {}
      await ref.set(_doc('video', taken, day, minute, lat, lng, url, thumbUrl, path, thumbPath, w, h, a.videoDuration.inMilliseconds, a.id));
    } else {
      final Uint8List? bytes = await FlutterImageCompress.compressWithFile(file.path, minWidth: 2048, minHeight: 2048, quality: 82);
      if (bytes == null) throw Exception('Gagal mengompres foto');
      path = 'trip/media/$id.jpg';
      final r = storage.ref(path);
      await r.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await r.getDownloadURL();
      await ref.set(_doc('photo', taken, day, minute, lat, lng, url, thumbUrl, path, thumbPath, w, h, 0, a.id));
    }
  }

  Map<String, dynamic> _doc(String type, DateTime taken, String day, int minute, double? lat, double? lng, String url, String thumbUrl,
      String path, String thumbPath, int w, int h, int durationMs, String assetId) {
    final s = AppState.I;
    return {
      'type': type,
      'takenAt': taken.millisecondsSinceEpoch,
      'date': day,
      'time': '${two(minute ~/ 60)}:${two(minute % 60)}',
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      'itemId': s.matchItem(day, minute),
      'url': url,
      'thumbUrl': thumbUrl,
      'path': path,
      'thumbPath': thumbPath,
      'w': w,
      'h': h,
      'durationMs': durationMs,
      'assetId': assetId,
      'by': s.email,
      'byName': s.myName,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Future<void> delete(Media m) async {
    for (final p in [m.path, m.thumbPath]) {
      if (p.isEmpty) continue;
      try {
        await storage.ref(p).delete();
      } catch (_) {}
    }
    await AppState.I.col('media').doc(m.id).delete();
  }

  Future<void> moveToItem(Media m, String itemId) => AppState.I.col('media').doc(m.id).update({'itemId': itemId});

  /// Unduh file media ke folder sementara (untuk dirakit jadi recap).
  Future<File> download(String storagePath, String localName) async {
    final tmp = await getTemporaryDirectory();
    final f = File('${tmp.path}/$localName');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    await storage.ref(storagePath).writeToFile(f);
    return f;
  }
}
