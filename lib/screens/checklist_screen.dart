import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'sheets.dart';

class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final need = s.sorted(s.items.where((i) => i.needsBooking));
    final done = need.where((i) => i.booked).toList();
    final todo = need.where((i) => !i.booked).toList();
    final byDay = <String, List<Item>>{};
    for (final i in todo) {
      byDay.putIfAbsent(i.date, () => []).add(i);
    }
    final days = byDay.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(todo.isNotEmpty ? 'Booking yang perlu diurus' : 'Semua booking beres',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text('${done.length} dari ${need.length}'),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                  value: need.isEmpty ? 0 : done.length / need.length, minHeight: 10, backgroundColor: C.coralSoft, color: C.good),
            ),
            const SizedBox(height: 8),
            const Text('Dicocokkan dari kabar di Chat, e-tiket, struk, dan email. Ketuk Tandai untuk mengirim bukti booking.',
                style: TextStyle(color: C.muted, fontSize: 12.5)),
          ]),
        ),
        const SectionTitle('Belum dibooking'),
        if (days.isEmpty) const Text('Tidak ada. Semua booking yang dibutuhkan sudah tercatat.', style: TextStyle(color: C.muted)),
        for (final d in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Row(children: [
              Text(dayLabel(d), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Pill(s.cityLabel(d), fg: C.muted, bg: C.sunk),
              const Spacer(),
              Text('${byDay[d]!.length} belum', style: const TextStyle(color: C.coral, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          Container(
            decoration: cardBox(),
            child: Column(children: [for (final i in byDay[d]!) _row(context, s, i, false)]),
          ),
        ],
        const SectionTitle('Sudah dibooking'),
        Container(
          decoration: cardBox(),
          child: done.isEmpty
              ? const Padding(padding: EdgeInsets.all(12), child: Text('Belum ada.', style: TextStyle(color: C.muted)))
              : Column(children: [for (final i in done) _row(context, s, i, true)]),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, AppState s, Item i, bool ok) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
              color: ok ? C.good : null, border: Border.all(color: ok ? C.good : C.coral, width: 2), borderRadius: BorderRadius.circular(8)),
          child: ok ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                ok
                    ? '${dayLabel(i.date)}${i.bookingCode.isEmpty ? '' : ' · kode ${i.bookingCode}'}${i.bookingName.isEmpty ? '' : ' · a.n. ${i.bookingName}'}${i.bookedVia.isEmpty ? '' : ' · dari ${i.bookedVia}'}'
                    : '${i.time.isEmpty ? 'jam belum ada' : i.time}${i.location.isEmpty ? '' : ' · ${i.location.split(',').first}'}',
                style: const TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
        if (!s.isViewer) ...[
          ok
              ? TextButton(onPressed: () => openItem(context, i), child: const Text('Detail'))
              : FilledButton(style: FilledButton.styleFrom(backgroundColor: C.coral), onPressed: () => openItem(context, i), child: const Text('Tandai')),
          PopupMenuButton<String>(
            tooltip: 'Menu lain',
            onSelected: (v) async {
              if (v == 'delete') {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Hapus agenda?'),
                    content: Text('${i.title} (${dayLabel(i.date)}) akan dihapus. Bisa dibatalkan dari Chat.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus')),
                    ],
                  ),
                );
                if (yes == true) await s.deleteItem(i);
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Hapus agenda'))],
          ),
        ],
      ]),
    );
  }
}
