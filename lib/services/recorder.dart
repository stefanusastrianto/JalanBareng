import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';
import '../store.dart';
import 'auth.dart';
import 'gemini.dart';
import 'gmail.dart';

Uint8List base64DecodeSafe(String data) {
  try {
    return base64Decode(data);
  } catch (_) {
    return Uint8List(0);
  }
}

/// Mesin pencatat: pesan chat, e-tiket, struk, dan email dicocokkan dengan itinerary oleh Gemini,
/// lalu hasilnya diterapkan ke data trip. Setiap perubahan bisa dibatalkan dari chat.
class Recorder {
  static AppState get s => AppState.I;
  static int now() => DateTime.now().millisecondsSinceEpoch;

  static String _itineraryTable() => s.sorted().map((i) => [
        i.id,
        i.date,
        i.time.isEmpty ? '-' : i.time,
        i.type,
        i.title,
        i.location.isEmpty ? '-' : i.location,
        i.needsBooking ? 'perlu booking' : 'tidak perlu booking',
        i.needsBooking ? (i.booked ? 'SUDAH' : 'BELUM') : '-',
        i.bookingCode.isEmpty ? '-' : i.bookingCode,
        i.bookingName.isEmpty ? '-' : i.bookingName,
        i.cost?.toString() ?? '-',
      ].join(' | ')).join('\n');

  static String _expenseTable() {
    final l = s.expenses.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rows = l.take(40).map((e) => [e.date, e.amount, e.merchant, e.category, e.paidBy.isEmpty ? '-' : e.paidBy].join(' | '));
    return rows.isEmpty ? '(belum ada)' : rows.join('\n');
  }

  static String buildPrompt(String text, {String docText = '', bool hasFiles = false, Map<String, dynamic>? ctx, String sender = ''}) {
    final recent = s.messages.reversed.take(8).toList().reversed.map((m) {
      final who = m.role == 'assistant' ? 'Asisten' : (m.authorName.isEmpty ? 'Anggota' : m.authorName);
      final t = m.text.length > 400 ? m.text.substring(0, 400) : m.text;
      return '$who: $t';
    }).join('\n');
    var ctxLine = '';
    if (ctx != null && str(ctx['itemId']).isNotEmpty) {
      ctxLine = 'Pesan ini dikirim dari halaman agenda id ${ctx['itemId']} (${ctx['label']}); anggap pesan merujuk ke agenda itu kecuali jelas menyebut yang lain.';
    } else if (ctx != null && str(ctx['day']).isNotEmpty) {
      ctxLine = 'Pesan ini dikirim dari halaman hari ${ctx['day']} (${ctx['label']}); agenda baru tanpa tanggal masuk ke hari itu.';
    }
    return '''Kamu pencatat perjalanan untuk trip keluarga "${s.tripName}" (${s.start} s.d. ${s.end}). Anggota menulis di chat grup; tugasmu mencocokkan kabar mereka dengan itinerary dan mencatat perubahan. Semua anggota boleh mengubah agenda.
Hari ini ${isoDate(DateTime.now())}. Pengirim pesan: ${sender.isEmpty ? s.myName : sender}.
$ctxLine

ITINERARY (id | tanggal | jam | jenis | judul | lokasi | perlu booking | status | kode | atas nama | rencana biaya):
${_itineraryTable()}

PENGELUARAN TERCATAT (tanggal | jumlah | tempat | kategori | dibayar oleh):
${_expenseTable()}

Jenis yang valid: ${kTypes.keys.join(', ')}.
${recent.isEmpty ? '' : '\nPERCAKAPAN TERAKHIR:\n$recent\n'}
PESAN BARU: """${text.isEmpty ? '(tanpa teks, hanya lampiran)' : text}"""
${docText.isEmpty ? '' : '\nISI DOKUMEN / EMAIL:\n"""$docText"""\n'}${hasFiles ? '\nAda file terlampir (e-tiket, screenshot, struk, atau PDF). Baca dengan teliti.\n' : ''}
Aturan:
- Cocokkan ke agenda yang sudah ada berdasarkan tanggal, jenis, dan kota/nama tempat. Contoh: "hotel di bandung tanggal 17" cocok dengan agenda hotel tanggal 2026-12-17. Jangan membuat agenda baru jika ada yang cocok.
- "booked": tandai sudah dibooking. Isi bookingCode, bookingName (atas nama), note bila ada. Jika dokumen menunjukkan tempat atau penyedia yang BERBEDA dari rencana, isi juga title dengan nama sebenarnya, location dengan nama + alamat, time dengan jam check-in/berangkat, endTime dengan jam tiba, dan detail singkat (kelas, kursi, check-out, telepon).
- "update": ubah field agenda (title, date, time, endTime, location, detail, type, cost) jika pesan meminta atau menyebut info baru. "cost" adalah RENCANA biaya; ubah hanya bila pesan jelas meminta mengubah rencana/budget.
- "add": agenda baru yang benar-benar belum ada (isi date, time, type, title, location, detail, needsBooking, booked, bookingCode, bookingName, cost).
- "delete": hapus agenda yang ada jika pesan memintanya secara jelas.
- "unbook": jika booking dibatalkan.
- "expense": catat BIAYA NYATA yang sudah dibayar: struk, nota, bukti transfer, tagihan, email/dokumen booking yang menyebut jumlah dibayar, atau pesan seperti "makan siang 285 ribu saya yang bayar". fields: amount (bilangan bulat rupiah, total akhir termasuk pajak/servis), date (YYYY-MM-DD tanggal transaksi), merchant, category (jenis valid; restoran = makan, tiket kereta = kereta, Grab/bensin/tol/sewa mobil = mobil), paidBy (nama pembayar bila disebut), note, itemId (id agenda yang cocok atau kosong). Satu transaksi = satu expense. Jangan mencatat ulang yang sudah ada di PENGELUARAN TERCATAT. Tulisan "Paid" tanpa jumlah bukan expense.
- Email atau dokumen yang tidak terkait trip ini (tanggal di luar periode trip) diabaikan.
- Jika pesan hanya pertanyaan atau obrolan, jawab dari itinerary tanpa aksi.
- Jangan mengarang kode, nama, alamat, atau harga. Jika ragu agenda mana yang dimaksud, jangan beraksi dan tanyakan di reply.
- id harus persis dari tabel.

Balas HANYA JSON:
{"reply":"balasan singkat untuk grup dalam bahasa Indonesia; sebut apa yang dicatat atau jawabannya","actions":[{"op":"booked|update|add|delete|unbook|expense","id":"(untuk booked/update/delete/unbook)","fields":{}}]}''';
  }

  static const _allowed = ['title', 'date', 'time', 'endTime', 'location', 'detail', 'cost', 'type', 'bookingCode', 'bookingName', 'needsBooking', 'booked'];
  static const _label = {
    'title': 'judul', 'date': 'tanggal', 'time': 'jam', 'endTime': 'jam tiba', 'location': 'lokasi', 'detail': 'catatan',
    'cost': 'rencana biaya', 'type': 'jenis', 'bookingCode': 'kode', 'bookingName': 'atas nama', 'needsBooking': 'perlu booking', 'booked': 'status',
  };

  static Map<String, dynamic> _clean(Map f) {
    final o = <String, dynamic>{};
    for (final k in _allowed) {
      if (!f.containsKey(k)) continue;
      var v = f[k];
      if (k == 'time' || k == 'endTime') {
        v = normTime(v);
      } else if (k == 'cost') {
        v = intOrNull(v);
      } else if (k == 'date') {
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str(v))) continue;
      } else if (k == 'type') {
        if (!kTypes.containsKey(v)) continue;
      } else if (k == 'needsBooking' || k == 'booked') {
        v = v == true;
      } else {
        final t = str(v);
        v = t.length > 200 ? t.substring(0, 200) : t;
      }
      o[k] = v;
    }
    return o;
  }

  static Future<List<Map<String, dynamic>>> applyActions(dynamic actions, String via, String? fileId, String actor, String actorName) async {
    final done = <Map<String, dynamic>>[];
    if (actions is! List) return done;
    for (final raw in actions) {
      if (raw is! Map) continue;
      final a = Map<String, dynamic>.from(raw);
      final op = str(a['op']);
      final f = (a['fields'] is Map) ? Map<String, dynamic>.from(a['fields'] as Map) : a;
      try {
        if (op == 'expense') {
          final amount = intOrNull(f['amount']);
          if (amount == null || amount <= 0) continue;
          Item? linked;
          for (final i in s.items) {
            if (i.id == str(f['itemId'])) linked = i;
          }
          final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str(f['date'])) ? str(f['date']) : (linked?.date ?? isoDate(DateTime.now()));
          final data = <String, dynamic>{
            'amount': amount,
            'date': date,
            'merchant': str(f['merchant']),
            'category': kTypes.containsKey(f['category']) ? f['category'] : (linked?.type ?? 'lainnya'),
            'paidBy': str(f['paidBy']).isEmpty ? actorName : str(f['paidBy']),
            'note': str(f['note']),
            'itemId': linked?.id,
            'via': via,
            'createdBy': actor,
            'createdAt': now(),
            if (fileId != null) 'fileId': fileId,
          };
          final id = await s.addExpense(data);
          done.add({'op': 'expense', 'id': id, 'label': 'Pengeluaran ${rp(amount)} · ${data['merchant']} (${shortDay(date)}), dibayar ${data['paidBy']}'});
          continue;
        }
        final c = _clean(f);
        if (op == 'add') {
          final data = <String, dynamic>{
            'title': 'Agenda', 'date': s.start.isEmpty ? isoDate(DateTime.now()) : s.start, 'type': 'lainnya', 'time': '', 'endTime': '', 'location': '', 'detail': '',
            ...c, 'createdAt': now(), 'createdBy': actor,
          };
          data['order'] = orderFor(str(data['time']));
          if (data['booked'] == true) {
            data.addAll({'bookedBy': actor, 'bookedVia': via, 'bookedAt': now()});
            if (fileId != null) data['fileId'] = fileId;
          }
          final id = await s.addItem(data);
          done.add({'op': 'add', 'id': id, 'label': 'Agenda baru: ${data['title']} (${shortDay(str(data['date']))}${str(data['time']).isEmpty ? '' : ' ${data['time']}'})'});
          continue;
        }
        Item? it;
        for (final i in s.items) {
          if (i.id == str(a['id'])) it = i;
        }
        if (it == null) continue;
        if (op == 'delete') {
          await s.deleteItemDoc(it.id);
          done.add({'op': 'delete', 'id': it.id, 'label': 'Agenda dihapus: ${it.title} (${shortDay(it.date)})', 'snapshot': it.d});
          continue;
        }
        Map<String, dynamic> patch;
        if (op == 'booked') {
          patch = {...c, 'booked': true, 'bookedBy': actor, 'bookedVia': via, 'bookedAt': now()};
          if (str(f['note']).isNotEmpty) patch['bookingNote'] = str(f['note']);
          if (fileId != null && it.fileId.isEmpty) patch['fileId'] = fileId;
        } else if (op == 'unbook') {
          patch = {'booked': false};
        } else if (op == 'update') {
          patch = c;
        } else {
          continue;
        }
        if (patch.isEmpty) continue;
        if (patch.containsKey('time')) patch['order'] = orderFor(str(patch['time']));
        if (patch.containsKey('location') && patch['location'] != it.location) patch['placeId'] = '';
        final prev = <String, dynamic>{for (final k in patch.keys) k: it.d[k]};
        await s.updateItem(it.id, patch);
        final label = op == 'booked'
            ? '${str(patch['title']).isEmpty ? it.title : patch['title']} (${shortDay(it.date)}) sudah dibooking${str(patch['bookingCode']).isEmpty ? '' : ', kode ${patch['bookingCode']}'}'
            : op == 'unbook'
                ? '${it.title}: booking dibatalkan'
                : '${it.title} diperbarui: ${c.entries.map((e) => '${_label[e.key] ?? e.key} ${e.key == 'cost' ? rp((e.value as int?) ?? 0) : e.value}').join(', ')}';
        done.add({'op': op, 'id': it.id, 'prev': prev, 'label': label});
      } catch (_) {
        // satu aksi gagal tidak menghentikan aksi lain
      }
    }
    return done;
  }

  static Future<void> undo(Msg m) async {
    for (final a in m.actions.reversed) {
      final op = str(a['op']);
      final id = str(a['id']);
      if (op == 'add') {
        await s.deleteItemDoc(id);
      } else if (op == 'expense') {
        await s.deleteExpense(id);
      } else if (op == 'delete' && a['snapshot'] is Map) {
        await s.setItem(id, Map<String, dynamic>.from(a['snapshot'] as Map));
      } else if (a['prev'] is Map) {
        await s.updateItem(id, Map<String, dynamic>.from(a['prev'] as Map));
      }
    }
    await s.updateMessage(m.id, {'undone': true, 'undoneBy': s.email});
  }

  /// Kirim pesan ke chat dan langsung catat dengan Gemini. Jika gagal karena kuota atau sinyal,
  /// pesan tetap tersimpan dengan status "menunggu dicatat".
  static Future<String?> send(String text, List<AiFile> files, {Map<String, dynamic>? ctx}) async {
    if (s.busy) return 'Tunggu pesan sebelumnya selesai dicatat.';
    s.setBusy(true, files.isEmpty ? '' : 'Menyimpan lampiran…');
    final attachments = <Map<String, dynamic>>[];
    String? firstFile;
    for (final f in files) {
      String? id;
      if (f.mime.startsWith('image/')) {
        try {
          id = await s.saveFile(f.name, f.mime, f.bytes);
        } catch (_) {}
      }
      firstFile ??= id;
      attachments.add({'name': f.name, 'mime': f.mime, 'fileId': id});
    }
    final msgId = await s.addMessage({
      'role': 'user',
      'author': s.email,
      'authorName': s.myName,
      'text': text,
      'attachments': attachments,
      'context': ctx,
      'contextLabel': ctx?['label'],
      'processed': false,
      'createdAt': now(),
    });
    final err = await _process(msgId, text, files, ctx, s.email, s.myName, firstFile);
    s.setBusy(false);
    return err;
  }

  static Future<String?> _process(String msgId, String text, List<AiFile> files, Map<String, dynamic>? ctx, String author, String authorName, String? fileId,
      {String docText = '', String? viaOverride}) async {
    s.setBusy(true, 'Mencatat dan mencocokkan dengan jadwal…');
    try {
      final res = await Gemini.json(buildPrompt(text, docText: docText, hasFiles: files.isNotEmpty, ctx: ctx, sender: authorName), files: files);
      final via = viaOverride ??
          (files.isNotEmpty ? (files.any((f) => f.mime == 'application/pdf') ? 'dokumen PDF' : 'foto/screenshot') : 'chat');
      final map = res is Map ? res : const {};
      final actions = await applyActions(map['actions'], via, fileId, author, authorName);
      await s.addMessage({
        'role': 'assistant',
        'author': author,
        'authorName': 'Asisten',
        'text': str(map['reply']).isEmpty ? 'Tercatat.' : str(map['reply']),
        'actions': actions,
        'replyTo': msgId,
        'processed': true,
        'createdAt': now(),
      });
      await s.updateMessage(msgId, {'processed': true});
      return null;
    } on AiError catch (e) {
      if (!e.retryable) {
        await s.addMessage({
          'role': 'assistant', 'author': author, 'authorName': 'Asisten', 'text': 'Belum bisa mencatat: ${e.message}',
          'actions': [], 'replyTo': msgId, 'processed': true, 'createdAt': now(),
        });
        await s.updateMessage(msgId, {'processed': true});
      }
      return e.message;
    } catch (e) {
      return 'Gagal mencatat: $e';
    } finally {
      s.setBusy(false);
    }
  }

  /// Catat ulang pesan yang tertunda. Lampiran foto diambil dari salinan di database.
  static Future<String?> processPending() async {
    for (final m in s.pending) {
      final files = <AiFile>[];
      String? fileId;
      for (final a in m.attachments) {
        final id = str(a['fileId']);
        if (id.isEmpty) continue;
        final f = await s.getFile(id);
        if (f == null) continue;
        fileId ??= id;
        files.add(AiFile(str(f['name']), str(f['mime']), base64DecodeSafe(str(f['data']))));
      }
      final err = await _process(m.id, m.text, files, m.context, m.author, m.authorName, fileId);
      if (err != null) return err;
    }
    return null;
  }

  /// Baca email booking terbaru dari Gmail dan catat yang terkait trip.
  static Future<String> syncGmail(void Function(String) progress) async {
    final headers = await AuthService.I.gmailHeaders();
    if (headers == null) return 'Izin membaca Gmail tidak diberikan.';
    progress('Mencari email booking…');
    final ids = await Gmail.searchIds(headers);
    final seen = s.syncedEmailIds.toSet();
    final fresh = ids.where((id) => !seen.contains(id)).toList();
    if (fresh.isEmpty) return 'Tidak ada email booking baru.';
    var recorded = 0;
    for (var k = 0; k < fresh.length; k += 3) {
      final chunk = fresh.sublist(k, k + 3 > fresh.length ? fresh.length : k + 3);
      progress('Membaca email ${k + 1}–${k + chunk.length} dari ${fresh.length}…');
      final mails = <MailMessage>[];
      for (final id in chunk) {
        try {
          mails.add(await Gmail.get(headers, id));
        } catch (_) {}
      }
      if (mails.isEmpty) continue;
      final doc = mails.map((m) => '--- EMAIL ${m.id}\nDari: ${m.from}\nTanggal: ${m.date}\nSubjek: ${m.subject}\n${m.body}').join('\n\n');
      final msgId = await s.addMessage({
        'role': 'user', 'author': s.email, 'authorName': s.myName,
        'text': 'Sync Gmail: ${mails.map((m) => m.subject).join(' · ')}',
        'attachments': [], 'processed': false, 'createdAt': now(),
      });
      final err = await _process(msgId, 'Baca email-email berikut. Catat booking dan biaya yang terkait trip ini saja.', const [], null, s.email, s.myName, null,
          docText: doc, viaOverride: 'email Gmail');
      if (err != null) return 'Berhenti di tengah sync: $err';
      recorded += mails.length;
      await s.updateTrip({'syncedEmailIds': [...s.syncedEmailIds, ...chunk]});
    }
    return '$recorded email baru dibaca. Hasilnya ada di Chat.';
  }

  static Future<String> daySummary(String day) async {
    final lines = s.itemsOn(day).map((i) {
      final b = i.needsBooking ? (i.booked ? ' | SUDAH dibooking${i.bookingCode.isEmpty ? '' : ' kode ${i.bookingCode}'}' : ' | BELUM dibooking') : '';
      return '- ${i.time.isEmpty ? '(tanpa jam)' : i.time} | ${typeOf(i.type).label} | ${i.title}${i.location.isEmpty ? '' : ' | lokasi ${i.location}'}$b';
    }).join('\n');
    return Gemini.text('''Tulis ringkasan agenda satu hari untuk grup WhatsApp keluarga yang sedang liburan, bahasa Indonesia santai.
Hari: ${dayLabel(day)} ${day.substring(0, 4)} (${s.cityLabel(day)}). Trip: ${s.tripName}.
Agenda:
$lines

Aturan: maksimal 10 baris, urut jam. Untuk kereta atau pesawat sarankan jam berangkat dari penginapan dengan cadangan waktu wajar dan ingatkan bawa KTP. Sebut kode booking yang perlu disiapkan. Jika ada yang BELUM dibooking, beri satu baris pengingat. Jangan menyebut biaya. Jangan mengarang. Tanpa markdown.''');
  }
}
