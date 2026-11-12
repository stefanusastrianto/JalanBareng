import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models.dart';
import '../services/recorder.dart';
import '../store.dart';
import 'common.dart';
import 'scene.dart';
import 'sheets.dart';

/// Tab Jadwal: kotak sorotan hari terdekat + semua hari.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  String? summary;
  bool summarizing = false;

  String? _pickFocus(AppState s) {
    final days = s.activeDays();
    if (days.isEmpty) return null;
    final today = isoDate(DateTime.now());
    for (final d in days) {
      if (d.compareTo(today) >= 0) return d;
    }
    return days.last;
  }

  Future<void> _summary(String day) async {
    setState(() {
      summarizing = true;
      summary = null;
    });
    try {
      summary = await Recorder.daySummary(day);
    } catch (e) {
      summary = 'Ringkasan belum bisa dibuat: $e';
    }
    if (mounted) setState(() => summarizing = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final days = s.activeDays();
    if (s.focusDay == null || !days.contains(s.focusDay)) s.focusDay = _pickFocus(s);
    final day = s.focusDay;
    final today = isoDate(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (day != null) _focusBox(context, s, day, days, today),
        const SectionTitle('Semua hari'),
        for (final d in s.tripDays()) _dayBlock(context, s, d, today),
      ],
    );
  }

  Widget _focusBox(BuildContext context, AppState s, String day, List<String> days, String today) {
    final its = s.itemsOn(day);
    final idx = days.indexOf(day);
    final diff = parseIso(day).difference(parseIso(today)).inDays;
    final kicker = diff == 0 ? 'HARI INI' : diff == 1 ? 'BESOK' : diff > 1 ? 'BERIKUTNYA · $diff HARI LAGI' : 'SUDAH LEWAT';
    final open = its.where((i) => i.needsBooking && !i.booked).length;
    final now = DateTime.now();
    final nowM = now.hour * 60 + now.minute;
    var first = 0;
    if (day == today) {
      final k = its.indexWhere((i) => (mins(i.time) ?? i.order) >= nowM);
      first = k < 0 ? its.length - 1 : k;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: C.tosca, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(aspectRatio: 360 / 130, child: SvgPicture.string(sceneSvg(s.cityFor(day)), fit: BoxFit.cover)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kicker, style: const TextStyle(color: C.coral, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1.2)),
                Text(dayLabel(day), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text('${s.cityLabel(day)} · ${its.length} agenda${open > 0 ? ' · $open belum dibooking' : ''}', style: const TextStyle(color: C.muted)),
              ]),
            ),
            IconButton.outlined(onPressed: idx > 0 ? () => setState(() => s.focusDay = days[idx - 1]) : null, icon: const Icon(Icons.chevron_left)),
            IconButton.outlined(
                onPressed: idx >= 0 && idx < days.length - 1 ? () => setState(() => s.focusDay = days[idx + 1]) : null, icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 8),
          child: Column(children: [
            for (var k = 0; k < its.length; k++) _event(context, its[k], k == first, day == today && k < first, day == today),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!s.isViewer) FilledButton.tonal(onPressed: () => openDay(context, day), child: const Text('Tambah / ubah agenda hari ini')),
              OutlinedButton(onPressed: summarizing ? null : () => _summary(day), child: Text(summarizing ? 'Menyusun…' : 'Ringkasan WhatsApp')),
            ]),
            if (summary != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: cardBox(color: C.sunk, border: C.sunk, radius: 12),
                child: SelectableText(summary!),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: () => copyText(context, summary!), child: const Text('Salin')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25A35A)),
                    onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(summary!)}'),
                    child: const Text('Kirim ke WhatsApp')),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _event(BuildContext context, Item i, bool first, bool past, bool isToday) {
    final card = InkWell(
      onTap: () => openItem(context, i),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.all(first ? 14 : 12),
        decoration: BoxDecoration(
          gradient: first ? const LinearGradient(colors: [Color(0xFFE6F8F4), Color(0xFFFFF3EC)]) : null,
          color: first ? null : C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: first ? C.tosca : C.line, width: first ? 2 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TypeIcon(i.type),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (first)
                Text(isToday ? 'SEKARANG / BERIKUTNYA' : 'AGENDA PERTAMA',
                    style: const TextStyle(color: C.tosca, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              Text(i.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: first ? 16.5 : 14.5)),
              Text(
                  '${placeText(i)}${i.endTime.isNotEmpty ? ' · tiba ${i.endTime}' : ''}',
                  style: TextStyle(fontSize: 12.5, color: i.isOpen ? C.coral : C.muted, fontWeight: i.isOpen ? FontWeight.w700 : FontWeight.w400)),
              if (i.needsBooking) Padding(padding: const EdgeInsets.only(top: 6), child: bookingPill(i)),
              if (first && i.bookingCode.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Text(i.bookingCode, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 1.2)),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => copyText(context, i.bookingCode), child: const Text('Salin kode')),
                  ]),
                ),
              if (first && i.location.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                      onPressed: () => openUrl(mapsSearch(i.location)), icon: const Icon(Icons.near_me_outlined, size: 18), label: const Text('Arahkan')),
                ),
            ]),
          ),
        ]),
      ),
    );
    return Opacity(
      opacity: past ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, right: 6),
              child: Text(i.time.isEmpty ? '—' : i.time,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 12.5, color: first ? C.tosca : C.muted)),
            ),
          ),
          Expanded(child: card),
        ]),
      ),
    );
  }

  Widget _dayBlock(BuildContext context, AppState s, String d, String today) {
    final its = s.itemsOn(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(dayLabel(d), style: TextStyle(fontWeight: FontWeight.w800, color: d == today ? C.coral : C.ink)),
          const SizedBox(width: 6),
          Pill(s.cityLabel(d), fg: C.muted, bg: C.sunk),
          const Spacer(),
          if (!s.isViewer) TextButton(onPressed: () => openDay(context, d), child: const Text('Tambah / ubah')),
        ]),
        Container(
          decoration: cardBox(),
          clipBehavior: Clip.antiAlias,
          child: its.isEmpty
              ? const Padding(padding: EdgeInsets.all(12), child: Text('Belum ada agenda', style: TextStyle(color: C.muted)))
              : Column(children: [
                  for (var k = 0; k < its.length; k++) ...[
                    if (k > 0) const Divider(height: 1, color: C.line),
                    ListTile(
                      onTap: () => openItem(context, its[k]),
                      leading: TypeIcon(its[k].type),
                      title: Text(its[k].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (its[k].time.isNotEmpty) Pill(its[k].time, fg: Colors.white, bg: C.ink),
                        if (its[k].needsBooking) bookingPill(its[k]),
                        if (its[k].isOpen)
                          Text('${placeText(its[k])} · lihat saran', style: const TextStyle(color: C.coral, fontWeight: FontWeight.w700, fontSize: 12))
                        else if (its[k].location.isNotEmpty)
                          Text(its[k].location.split(',').first, style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ],
                ]),
        ),
      ]),
    );
  }
}
