import 'dart:convert';

import 'package:http/http.dart' as http;

class MailMessage {
  final String id;
  final String subject;
  final String from;
  final String date;
  final String body;
  MailMessage(this.id, this.subject, this.from, this.date, this.body);
}

/// Membaca email booking lewat Gmail API (izin baca saja).
class Gmail {
  static const query =
      'newer_than:6m -category:promotions -category:social (kai OR "kereta api" OR whoosh OR kcic OR traveloka OR tiket.com OR agoda OR "booking.com" OR pegipegi OR hotel OR resort OR reservation OR reservasi OR "booking confirmation" OR "konfirmasi pemesanan" OR "e-tiket" OR "e-ticket" OR invoice OR "bukti pembayaran")';

  static Future<List<String>> searchIds(Map<String, String> headers, {int max = 30}) async {
    final uri = Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages', {'q': query, 'maxResults': '$max'});
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) throw Exception('Gmail ${res.statusCode}');
    final list = ((jsonDecode(res.body) as Map)['messages'] as List?) ?? const [];
    return list.map((m) => (m as Map)['id'].toString()).toList();
  }

  static Future<MailMessage> get(Map<String, String> headers, String id) async {
    final uri = Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages/$id', {'format': 'full'});
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    if (res.statusCode >= 400) throw Exception('Gmail ${res.statusCode}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final payload = Map<String, dynamic>.from((j['payload'] as Map?) ?? const {});
    final hs = ((payload['headers'] as List?) ?? const []).cast<Map>();
    String h(String name) {
      for (final x in hs) {
        if (x['name']?.toString().toLowerCase() == name) return x['value']?.toString() ?? '';
      }
      return '';
    }

    var plain = '';
    var html = '';
    void walk(Map p) {
      final mime = p['mimeType']?.toString() ?? '';
      final data = (p['body'] as Map?)?['data']?.toString();
      if (data != null && data.isNotEmpty) {
        final txt = _decode(data);
        if (mime == 'text/plain' && plain.isEmpty) plain = txt;
        if (mime == 'text/html' && html.isEmpty) html = txt;
      }
      for (final c in ((p['parts'] as List?) ?? const [])) {
        if (c is Map) walk(c);
      }
    }

    walk(payload);
    var body = plain.trim().isNotEmpty ? plain : _stripHtml(html);
    body = body.replaceAll(RegExp(r'[ \t ]+'), ' ').replaceAll(RegExp(r'\n\s*\n+'), '\n');
    if (body.length > 7000) body = body.substring(0, 7000);
    return MailMessage(id, h('subject'), h('from'), h('date'), body);
  }

  static String _decode(String data) {
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</tr>|</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"');
}
