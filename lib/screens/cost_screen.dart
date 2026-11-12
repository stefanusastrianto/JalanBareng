import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';
import 'sheets.dart';

/// Tab Biaya: rencana vs realisasi, rencana bisa diubah langsung.
class CostScreen extends StatefulWidget {
  const CostScreen({super.key});
  @override
  State<CostScreen> createState() => _CostScreenState();
}

class _CostScreenState extends State<CostScreen> {
  String seg = 'days';

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final real = s.expenses.fold<int>(0, (a, e) => a + e.amount);
    final plan = s.items.fold<int>(0, (a, i) => a + (i.cost ?? 0));
    final paidBy = <String, int>{};
    for (final e in s.expenses) {
      if (e.itemId.isNotEmpty) paidBy[e.itemId] = (paidBy[e.itemId] ?? 0) + e.amount;
    }
    final paidItems = s.items.where((i) => paidBy.containsKey(i.id)).toList();
    final planPaid = paidItems.fold<int>(0, (a, i) => a + (i.cost ?? 0));
    final realPaid = paidItems.fold<int>(0, (a, i) => a + paidBy[i.id]!);
    final left = s.items.where((i) => !paidBy.containsKey(i.id)).fold<int>(0, (a, i) => a + (i.cost ?? 0));
    final proj = real + left;
    final scale = (plan > proj ? plan : proj).clamp(1, 1 << 40).toDouble();
    final diff = planPaid - realPaid;
    final other = real - realPaid;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RENCANA VS REALISASI', style: TextStyle(fontSize: 11.5, letterSpacing: 1.2, color: C.muted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(children: [
              _num('Rencana total', rp(plan), C.ink),
              _num('Sudah dibayar', rp(real), C.tosca),
              _num('Proyeksi akhir', rp(proj), proj > plan ? C.bad : C.ink),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 12,
                child: Row(children: [
                  for (final part in [
                    [(real / scale * 1000).round(), C.tosca],
                    [(left / scale * 1000).round(), const Color(0xFFBFE8DE)],
                    [((1 - (real + left) / scale) * 1000).round(), C.sunk],
                  ])
                    if ((part[0] as int) > 0) Expanded(flex: part[0] as int, child: Container(color: part[1] as Color)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            const Wrap(spacing: 14, children: [
              _Legend(C.tosca, 'Sudah dibayar'),
              _Legend(Color(0xFFBFE8DE), 'Rencana yang belum dibayar'),
            ]),
            const SizedBox(height: 8),
            Text(
              paidItems.isEmpty
                  ? 'Belum ada pembayaran yang tercatat. Kirim struk atau email booking lewat Chat.'
                  : '${paidItems.length} agenda sudah dibayar: rencananya ${rp(planPaid)}, realisasinya ${rp(realPaid)} (${diff >= 0 ? 'hemat ${rpShort(diff)}' : 'lebih ${rpShort(-diff)}'}).'
                      '${other > 0 ? ' Ada ${rp(other)} pengeluaran lain di luar agenda.' : ''} Sisa rencana yang belum dibayar ${rp(left)}.',
              style: const TextStyle(color: C.muted, fontSize: 12.5),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'days', label: Text('Per hari')),
            ButtonSegment(value: 'cats', label: Text('Kategori')),
            ButtonSegment(value: 'pays', label: Text('Pembayaran')),
          ],
          selected: {seg},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => seg = v.first),
        ),
        const SizedBox(height: 12),
        if (seg == 'days') ..._days(context, s, paidBy),
        if (seg == 'cats') _cats(s),
        if (seg == 'pays') ..._pays(context, s),
      ],
    );
  }

  Widget _num(String label, String value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: C.muted, fontWeight: FontWeight.w700)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color))),
        ]),
      );

  List<Widget> _days(BuildContext context, AppState s, Map<String, int> paidBy) {
    final today = isoDate(DateTime.now());
    final extra = s.expenses.where((e) => e.itemId.isEmpty).toList();
    final out = <Widget>[
      const Text('Ketuk angka rencana untuk mengubahnya. Realisasi terisi otomatis dari struk dan email booking.',
          style: TextStyle(color: C.muted, fontSize: 12.5)),
      const SizedBox(height: 8),
    ];
    for (final d in s.tripDays()) {
      final its = s.itemsOn(d);
      final ex = extra.where((e) => e.date == d).toList();
      if (its.isEmpty && ex.isEmpty) continue;
      final dPlan = its.fold<int>(0, (a, i) => a + (i.cost ?? 0));
      final dReal = its.fold<int>(0, (a, i) => a + (paidBy[i.id] ?? 0)) + ex.fold<int>(0, (a, e) => a + e.amount);
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(children: [
          Text(dayLabel(d), style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          Text('rencana ${rpShort(dPlan)}${dReal > 0 ? ' · bayar ${rpShort(dReal)}' : ''}', style: const TextStyle(fontSize: 12, color: C.muted)),
        ]),
      ));
      out.add(Container(
        decoration: cardBox(),
        child: Column(children: [
          for (final i in its)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                TypeIcon(i.type, size: 34),
                const SizedBox(width: 10),
                Expanded(child: Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  PlanField(i, enabled: !s.isViewer),
                  const SizedBox(height: 2),
                  paidBy[i.id] != null
                      ? Text('dibayar ${rp(paidBy[i.id]!)}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: (i.cost != null && paidBy[i.id]! > i.cost!) ? C.bad : C.good))
                      : Text(d.compareTo(today) < 0 ? 'tidak ada catatan bayar' : 'belum dibayar', style: const TextStyle(fontSize: 11.5, color: C.muted)),
                ]),
              ]),
            ),
          for (final e in ex)
            ListTile(
              onTap: () => openExpense(context, e),
              leading: TypeIcon(e.category, size: 34),
              title: Text(e.merchant.isEmpty ? 'Pengeluaran lain' : e.merchant),
              subtitle: Text('di luar rencana${e.paidBy.isEmpty ? '' : ' · dibayar ${e.paidBy}'}'),
              trailing: Text(rp(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ));
    }
    return out;
  }

  Widget _cats(AppState s) {
    final est = <String, int>{};
    final real = <String, int>{};
    for (final i in s.items) {
      est[i.type] = (est[i.type] ?? 0) + (i.cost ?? 0);
    }
    for (final e in s.expenses) {
      real[e.category] = (real[e.category] ?? 0) + e.amount;
    }
    final keys = {...est.keys, ...real.keys}.where((k) => (est[k] ?? 0) + (real[k] ?? 0) > 0).toList()
      ..sort((a, b) => ((est[b] ?? 0) + (real[b] ?? 0)).compareTo((est[a] ?? 0) + (real[a] ?? 0)));
    return Container(
      decoration: cardBox(),
      child: Column(children: [
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              TypeIcon(k, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(typeOf(k).label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: (est[k] ?? 0) == 0 ? ((real[k] ?? 0) > 0 ? 1 : 0) : ((real[k] ?? 0) / est[k]!).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: C.sunk,
                      color: (real[k] ?? 0) > (est[k] ?? 0) && (est[k] ?? 0) > 0 ? C.coral : C.tosca,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(rp(real[k] ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('dari ${rp(est[k] ?? 0)}', style: const TextStyle(fontSize: 11.5, color: C.muted)),
              ]),
            ]),
          ),
      ]),
    );
  }

  List<Widget> _pays(BuildContext context, AppState s) {
    final byDay = <String, List<Expense>>{};
    for (final e in s.expenses) {
      byDay.putIfAbsent(e.date, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) {
      return [const Text('Belum ada pembayaran. Kirim struk atau email booking lewat Chat.', style: TextStyle(color: C.muted))];
    }
    return [
      for (final d in days) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            Text('Dibayar ${d.isEmpty ? 'tanpa tanggal' : dayLabel(d)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(rp(byDay[d]!.fold<int>(0, (a, e) => a + e.amount)), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        Container(
          decoration: cardBox(),
          child: Column(children: [
            for (final e in byDay[d]!)
              Builder(builder: (_) {
                Item? it;
                for (final i in s.items) {
                  if (i.id == e.itemId) it = i;
                }
                return ListTile(
                  onTap: () => openExpense(context, e),
                  leading: TypeIcon(e.category, size: 34),
                  title: Text(e.merchant.isEmpty ? typeOf(e.category).label : e.merchant),
                  subtitle: Wrap(spacing: 6, children: [
                    if (it != null) Pill('untuk ${dayLabel(it.date)}${it.time.isEmpty ? '' : ' · ${it.time}'}', fg: const Color(0xFF2A7DB0), bg: C.skySoft),
                    if (e.paidBy.isNotEmpty) Text('dibayar ${e.paidBy}', style: const TextStyle(fontSize: 12)),
                  ]),
                  trailing: Text(rp(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                );
              }),
          ]),
        ),
      ],
    ];
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend(this.color, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11.5, color: C.muted)),
      ]);
}

/// Angka rencana biaya yang bisa diubah langsung. Format: 1.500.000, 1,5jt, atau 800rb.
class PlanField extends StatefulWidget {
  final Item item;
  final bool enabled;
  const PlanField(this.item, {super.key, this.enabled = true});
  @override
  State<PlanField> createState() => _PlanFieldState();
}

class _PlanFieldState extends State<PlanField> {
  late final TextEditingController ctl = TextEditingController(text: _fmt(widget.item.cost));
  final focus = FocusNode();

  static String _fmt(int? v) => v == null ? '' : rp(v).replaceAll('Rp', '');

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(PlanField old) {
    super.didUpdateWidget(old);
    if (!focus.hasFocus && old.item.cost != widget.item.cost) ctl.text = _fmt(widget.item.cost);
  }

  Future<void> _save() async {
    final v = parseRupiah(ctl.text);
    if (v == widget.item.cost) {
      ctl.text = _fmt(v);
      return;
    }
    await AppState.I.updateItem(widget.item.id, {'cost': v});
    ctl.text = _fmt(v);
    if (mounted) toast(context, 'Rencana ${widget.item.title}: ${v == null ? 'dikosongkan' : rp(v)}');
  }

  @override
  void dispose() {
    focus.dispose();
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        child: TextField(
          controller: ctl,
          focusNode: focus,
          enabled: widget.enabled,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.text,
          onSubmitted: (_) => focus.unfocus(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'rencana',
            prefixText: 'Rp ',
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: C.line)),
          ),
        ),
      );
}
