import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'common.dart';

/// Lembar "Trip saya": pindah trip atau buat trip baru.
Future<void> openTripSwitcher(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: C.surface,
      builder: (c) => const _TripSwitcher(),
    );

class _TripSwitcher extends StatelessWidget {
  const _TripSwitcher();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (c, _) {
        final s = AppState.I;
        final groups = <String, List<TripInfo>>{'now': [], 'soon': [], 'past': []};
        for (final t in s.myTrips) {
          groups[t.phase]!.add(t);
        }
        groups['past']!.sort((a, b) => b.start.compareTo(a.start));
        const titles = {'now': 'Sedang berjalan', 'soon': 'Akan datang', 'past': 'Selesai'};
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          const Text('Trip saya', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final k in ['now', 'soon', 'past'])
            if (groups[k]!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(titles[k]!.toUpperCase(), style: const TextStyle(color: C.muted, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 1)),
              ),
              for (final t in groups[k]!)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  color: t.id == s.tripId ? C.toscaSoft : C.sunk,
                  child: ListTile(
                    leading: Icon(k == 'now' ? Icons.luggage : (k == 'soon' ? Icons.event_outlined : Icons.history), color: C.tosca),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([t.range, '${t.memberCount} anggota', if (t.adminEmail == s.email) 'Anda admin'].where((x) => x.isNotEmpty).join(' · ')),
                    trailing: t.id == s.tripId ? const Icon(Icons.check_circle, color: C.tosca) : null,
                    onTap: () {
                      s.openTrip(t.id);
                      Navigator.pop(context);
                    },
                  ),
                ),
            ],
          const SizedBox(height: 12),
          if (s.canCreateTrips)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                openCreateTrip(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Buat trip baru'),
            )
          else
            const Text('Untuk membuat trip baru, minta pemilik aplikasi menambahkan email Anda sebagai pembuat trip.',
                style: TextStyle(color: C.muted, fontSize: 12.5)),
        ]);
      },
    );
  }
}

Future<void> openCreateTrip(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: C.surface,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: CreateTripForm(onDone: () => Navigator.pop(c))),
      ),
    );

/// Formulir trip baru: nama, tanggal, kota tujuan. Jadwal diisi lewat chat sesudahnya.
class CreateTripForm extends StatefulWidget {
  final VoidCallback? onDone;
  const CreateTripForm({super.key, this.onDone});
  @override
  State<CreateTripForm> createState() => _CreateTripFormState();
}

class _CreateTripFormState extends State<CreateTripForm> {
  final name = TextEditingController();
  final dest = TextEditingController();
  DateTimeRange? range;
  bool busy = false;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDateRange: range,
      helpText: 'Tanggal trip',
      saveText: 'Simpan',
    );
    if (r != null) setState(() => range = r);
  }

  Future<void> _create() async {
    if (name.text.trim().isEmpty || range == null) {
      toast(context, 'Isi nama trip dan tanggalnya dulu');
      return;
    }
    setState(() => busy = true);
    try {
      await AppState.I.createTrip(
        name: name.text.trim(),
        start: isoDate(range!.start),
        end: isoDate(range!.end),
        destinations: dest.text.trim(),
      );
      if (mounted) toast(context, 'Trip dibuat. Buka Chat untuk mengisi jadwal.');
      widget.onDone?.call();
    } catch (e) {
      if (mounted) toast(context, 'Gagal membuat trip: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l, [String? h]) => InputDecoration(labelText: l, hintText: h, border: const OutlineInputBorder(), isDense: true);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Trip baru', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Setelah dibuat, kirim itinerary di Chat (ketik rencana, foto/PDF jadwal, atau e-tiket). Jadwal, kota per hari, dan lokasi Google Maps disusun otomatis.',
          style: TextStyle(color: C.muted, fontSize: 12.5)),
      const SizedBox(height: 14),
      TextField(controller: name, textCapitalization: TextCapitalization.sentences, decoration: deco('Nama trip', 'mis. Liburan Bali Lebaran')),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _pickDates,
        icon: const Icon(Icons.date_range),
        label: Text(range == null ? 'Pilih tanggal mulai – selesai' : '${dayLabel(isoDate(range!.start))} – ${dayLabel(isoDate(range!.end))}'),
      ),
      const SizedBox(height: 10),
      TextField(controller: dest, decoration: deco('Kota tujuan (opsional)', 'mis. Denpasar, Ubud, Nusa Penida')),
      const SizedBox(height: 14),
      FilledButton(onPressed: busy ? null : _create, child: Text(busy ? 'Membuat…' : 'Buat trip')),
    ]);
  }
}
