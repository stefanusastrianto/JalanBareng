import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../store.dart';

class AiFile {
  final String name;
  final String mime;
  final Uint8List bytes;
  AiFile(this.name, this.mime, this.bytes);
}

class AiError implements Exception {
  /// 'quota' = kuota habis (pesan disimpan dan bisa dicatat ulang), 'net' = tidak ada sinyal, lainnya = gagal permanen.
  final String code;
  final String message;
  AiError(this.code, this.message);
  bool get retryable => code == 'quota' || code == 'net' || code == 'busy';
  @override
  String toString() => message;
}

Map<String, String> androidKeyHeaders() {
  final sha = Config.androidCertSha1.replaceAll(RegExp(r'[\s:]'), '').toUpperCase();
  return sha.isEmpty ? {} : {'X-Android-Package': Config.androidPackage, 'X-Android-Cert': sha};
}

class Gemini {
  static Future<String> _call(String prompt, {List<AiFile> files = const [], bool json = false}) async {
    if (Config.geminiKey.isEmpty) throw AiError('config', 'Gemini API key belum diisi di build aplikasi.');
    final model = AppState.I.geminiModel;
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      for (final f in files)
        {
          'inline_data': {'mime_type': f.mime, 'data': base64Encode(f.bytes)}
        },
    ];
    final body = {
      'contents': [
        {'role': 'user', 'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0.2,
        if (json) 'responseMimeType': 'application/json',
      },
    };
    // Coba model pilihan dulu; kalau model itu sudah dihentikan Google, pakai alias "terbaru".
    final models = <String>[model, if (model != 'gemini-flash-latest') 'gemini-flash-latest'];
    late http.Response res;
    var used = model;
    outer:
    for (final m in models) {
      used = m;
      final u = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent');
      // Server Gemini kadang sibuk (503); coba ulang beberapa kali dengan jeda.
      for (final wait in const [0, 3, 8]) {
        if (wait > 0) await Future.delayed(Duration(seconds: wait));
        try {
          res = await http
              .post(u,
                  headers: {'Content-Type': 'application/json', 'x-goog-api-key': Config.geminiKey, ...androidKeyHeaders()},
                  body: jsonEncode(body))
              .timeout(const Duration(seconds: 120));
        } catch (_) {
          throw AiError('net', 'Tidak ada koneksi internet. Pesan disimpan dan bisa dicatat nanti.');
        }
        if (res.statusCode != 503 && res.statusCode != 500) break;
      }
      if (res.statusCode != 404) break outer;
    }
    if (res.statusCode == 503 || res.statusCode == 500) {
      throw AiError('busy', 'Server Gemini sedang sibuk. Pesan disimpan; coba "Catat sekarang" beberapa menit lagi.');
    }
    if (res.statusCode == 404) throw AiError('model', 'Model Gemini "$used" tidak ditemukan. Ganti nama model di tab Admin.');
    if (res.statusCode == 402) throw AiError('quota', 'Saldo/billing Gemini untuk kunci ini habis atau belum aktif. Pesan disimpan dan bisa dicatat nanti. Admin: cek kunci Gemini.');
    if (res.statusCode == 429) throw AiError('quota', 'Kuota harian Gemini sedang habis. Pesan disimpan dan bisa dicatat nanti.');
    if (res.statusCode >= 400) {
      final short = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
      throw AiError('http', 'Gemini menolak permintaan (${res.statusCode}): $short');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = (j['candidates'] as List?) ?? const [];
    if (cands.isEmpty) throw AiError('empty', 'Gemini tidak memberi jawaban untuk pesan ini.');
    final content = (cands.first as Map)['content'] as Map?;
    final ps = (content?['parts'] as List?) ?? const [];
    final text = ps.map((p) => (p as Map)['text']?.toString() ?? '').join();
    if (text.trim().isEmpty) throw AiError('empty', 'Gemini tidak memberi jawaban untuk pesan ini.');
    return text;
  }

  static Future<String> text(String prompt) => _call(prompt);

  static Future<dynamic> json(String prompt, {List<AiFile> files = const []}) async {
    final t = await _call(prompt, files: files, json: true);
    try {
      return jsonDecode(t);
    } catch (_) {
      final a = t.indexOf(RegExp(r'[\[{]'));
      final b = t.lastIndexOf(RegExp(r'[\]}]'));
      if (a >= 0 && b > a) {
        try {
          return jsonDecode(t.substring(a, b + 1));
        } catch (_) {}
      }
      throw AiError('json', 'Jawaban Gemini tidak terbaca rapi. Coba kirim ulang.');
    }
  }
}
