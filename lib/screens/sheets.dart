import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: C.surface,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), child: builder(c)),
      ),
    );

/// Lembar detail agenda: info booking, kartu Google Maps, saran tempat, kotak chat untuk mengubah, dan hapus.
Future<void> openItem(BuildContext context, Item i) {
  final s = AppState.I;
  final ask = i.needsBooking && !i.booked;
  return _sheet(context, (c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        TypeIcon(i.type),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${dayLabel(i.date)}${i.time.isEmpty ? '' : ' · ${i.time}'}${i.endTime.isEmpty ? '' : '–${i.endTime}'}',
                style: const TextStyle(color: C.muted)),
          ]),
        ),
      ]),
      const SizedBox(height: 10),
      if (i.needsBooking) bookingPill(i),
      if (i.bookingCode.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: cardBox(radius: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('KODE BOOKING', style: TextStyle(fontSize: 10.5, letterSpacing: 1, color: C.muted)),
                SelectableText(i.bookingCode, style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              ]),
            ),
            FilledButton(onPressed: () => copyText(c, i.bookingCode), child: const Text('Salin')),
          ]),
        ),
      ],
      if (i.detail.isNotEmpty || i.bookingNote.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text([i.detail, i.bookingNote].where((x) => x.isNotEmpty).join(' · '), style: const TextStyle(color: C.muted)),
      ],
      if (i.fileId.isNotEmpty) ...[const SizedBox(height: 10), StoredImage(i.fileId)],
      const SizedBox(height: 12),
      if (i.location.isNotEmpty || i.booked) PlaceCard(i),
      if (i.isOpen) ...[
        const Text('Saran di sekitar', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Suggestions(i),
      ],
      if (!s.isViewer) ...[
        const SizedBox(height: 16),
        Text(ask ? 'Kirim bukti booking atau ubah agenda ini' : 'Ubah agenda ini', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        QuickChat(
          hint: ask ? 'mis. sudah dibooking a.n. Stefanus, kode ABC123' : 'mis. ganti jam jadi 18.30',
          ctx: {'itemId': i.id, 'label': '${i.title} (${shortDay(i.date)})'},
          onSent: () => Navigator.pop(c),
        ),
        const SizedBox(height: 12),
        Row(children: [
          _DeleteButton(onConfirm: () async {
            Navigator.pop(c);
            await s.deleteItem(i);
          }),
          const Spacer(),
          TextButton(
              onPressed: () {
                Navigator.pop(c);
                openForm(context, i, null);
              },
              child: const Text('Edit manual')),
        ]),
      ],
    ]);
  });
}

class _DeleteButton extends StatefulWidget {
  final Future<void> Function() onConfirm;
  final String label;
  const _DeleteButton({required this.onConfirm, this.label = 'Hapus agenda'});
  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool armed = false;
  @override
  Widget build(BuildContext context) => armed
      ? FilledButton(style: FilledButton.styleFrom(backgroundColor: C.coral), onPressed: widget.onConfirm, child: const Text('Ketuk lagi untuk hapus'))
      : OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: C.bad), onPressed: () => setState(() => armed = true), child: Text(widget.label));
}

Widget deleteButton(Future<void> Function() onConfirm, {String label = 'Hapus'}) => _DeleteButton(onConfirm: onConfirm, label: label);

/// Lembar hari: tambah atau ubah agenda lewat kotak chat.
Future<void> openDay(BuildContext context, String day) {
  final its = AppState.I.itemsOn(day);
  return _sheet(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dayLabel(day), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(its.isEmpty ? 'Belum ada agenda.' : its.map((i) => '${i.time.isEmpty ? '' : '${i.time} '}${i.title}').join(' · '),
            style: const TextStyle(color: C.muted)),
        const SizedBox(height: 14),
        const Text('Tambah atau ubah agenda hari ini', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        QuickChat(
          hint: 'mis. tambah makan malam jam 19.00 di Nasi Jamblang Mang Dul',
          ctx: {'day': day, 'label': dayLabel(day)},
          onSent: () => Navigator.pop(c),
        ),
        const SizedBox(height: 8),
        TextButton(
            onPressed: () {
              Navigator.pop(c);
              openForm(context, null, day);
            },
            child: const Text('Tambah manual')),
      ]));
}

/// Form manual (cadangan jika AI sedang tidak bisa dipakai).
Future<void> openForm(BuildContext context, Item? item, String? day) {
  final s = AppState.I;
  final isNew = item == null;
  final d = item?.d ?? <String, dynamic>{'date': day ?? s.focusDay ?? s.start, 'type': 'lainnya'};
  final title = TextEditingController(text: str(d['title']));
  final date = TextEditingController(text: str(d['date']));
  final time = TextEditingController(text: str(d['time']));
  final end = TextEditingController(text: str(d['endTime']));
  final loc = TextEditingController(text: str(d['location']));
  final detail = TextEditingController(text: str(d['detail']));
  final code = TextEditingController(text: str(d['bookingCode']));
  final bname = TextEditingController(text: str(d['bookingName']));
  final cost = TextEditingController(text: intOrNull(d['cost']) == null ? '' : rp(intOrNull(d['cost'])!).replaceAll('Rp', ''));
  var type = catOf(str(d['type']));
  var need = item?.needsBooking ?? false;
  var booked = item?.booked ?? false;
  InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
  return _sheet(context, (c) => StatefulBuilder(
        builder: (c, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isNew ? 'Agenda baru' : 'Edit manual', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: deco('Judul')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: date, decoration: deco('Tanggal (YYYY-MM-DD)'))),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: type,
                decoration: deco('Jenis'),
                items: kTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.label))).toList(),
                onChanged: (v) => set(() => type = v ?? type),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: time, decoration: deco('Jam mulai (HH:MM)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: end, decoration: deco('Jam selesai'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: loc, decoration: deco('Lokasi (untuk Google Maps)')),
          const SizedBox(height: 10),
          TextField(controller: detail, decoration: deco('Catatan')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: code, decoration: deco('Kode booking'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: bname, decoration: deco('Atas nama'))),
          ]),
          CheckboxListTile(value: need, onChanged: (v) => set(() => need = v ?? false), title: const Text('Perlu dibooking'), contentPadding: EdgeInsets.zero),
          CheckboxListTile(value: booked, onChanged: (v) => set(() => booked = v ?? false), title: const Text('Sudah dibooking'), contentPadding: EdgeInsets.zero),
          TextField(controller: cost, keyboardType: TextInputType.number, decoration: deco('Rencana biaya (Rp)')),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date.text.trim())) {
                  toast(c, 'Judul dan tanggal (YYYY-MM-DD) wajib diisi');
                  return;
                }
                final data = <String, dynamic>{
                  'title': title.text.trim(),
                  'date': date.text.trim(),
                  'type': type,
                  'time': normTime(time.text),
                  'endTime': normTime(end.text),
                  'location': loc.text.trim(),
                  'detail': detail.text.trim(),
                  'bookingCode': code.text.trim(),
                  'bookingName': bname.text.trim(),
                  'needsBooking': need,
                  'booked': booked,
                  'cost': parseRupiah(cost.text),
                  'order': orderFor(normTime(time.text)),
                };
                if (booked && !(item?.booked ?? false)) data.addAll({'bookedBy': s.email, 'bookedVia': 'isian manual', 'bookedAt': DateTime.now().millisecondsSinceEpoch});
                if (item != null && data['location'] != item.location) data['placeId'] = '';
                Navigator.pop(c);
                if (isNew) {
                  await s.addItem({...data, 'createdAt': DateTime.now().millisecondsSinceEpoch, 'createdBy': s.email});
                } else {
                  await s.updateItem(item!.id, data);
                }
              },
              child: const Text('Simpan'),
            ),
          ]),
        ]),
      ));
}

Future<void> openExpense(BuildContext context, Expense e) {
  final s = AppState.I;
  final amount = TextEditingController(text: rp(e.amount).replaceAll('Rp', ''));
  final date = TextEditingController(text: e.date);
  final merchant = TextEditingController(text: e.merchant);
  final paid = TextEditingController(text: e.paidBy);
  Item? linked;
  for (final i in s.items) {
    if (i.id == e.itemId) linked = i;
  }
  InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
  return _sheet(context, (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pengeluaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (linked != null) ...[
          const SizedBox(height: 6),
          Text('Untuk: ${linked.title}, ${dayLabel(linked.date)}${linked.time.isEmpty ? '' : ' pukul ${linked.time}'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number, decoration: deco('Jumlah (Rp)'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: date, decoration: deco('Tanggal bayar'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: merchant, decoration: deco('Tempat / keterangan')),
        const SizedBox(height: 10),
        TextField(controller: paid, decoration: deco('Dibayar oleh')),
        if (e.fileId.isNotEmpty) ...[const SizedBox(height: 10), StoredImage(e.fileId)],
        const SizedBox(height: 8),
        Text('Dicatat dari ${e.via.isEmpty ? 'chat' : e.via}${e.note.isEmpty ? '' : ' · ${e.note}'}', style: const TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          if (!s.isViewer)
            deleteButton(() async {
              Navigator.pop(c);
              await s.deleteExpense(e.id);
            }),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
          if (!s.isViewer)
            FilledButton(
                onPressed: () async {
                  Navigator.pop(c);
                  await s.updateExpense(e.id, {
                    'amount': parseRupiah(amount.text) ?? e.amount,
                    'date': date.text.trim(),
                    'merchant': merchant.text.trim(),
                    'paidBy': paid.text.trim(),
                  });
                },
                child: const Text('Simpan')),
        ]),
      ]));
}
