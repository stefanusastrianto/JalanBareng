import 'package:flutter/material.dart';

import '../models.dart';
import '../services/auth.dart';
import '../services/notifications.dart';
import '../services/places.dart';
import '../services/recorder.dart';
import '../store.dart';
import 'common.dart';
import 'sheets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String? syncStatus;
  bool syncing = false;

  String _invite(String name) {
    final s = AppState.I;
    final range = s.start.isEmpty ? '' : ' (${shortDay(s.start)}–${shortDay(s.end)} ${parseIso(s.end).year})';
    return 'Halo${name.isEmpty ? '' : ' $name'}! Ini aplikasi jadwal "${s.tripName}"$range.\n\n'
        'Kamu bisa lihat agenda per hari, cek booking, dan kirim kabar atau foto struk lewat chat.\n\n'
        'Pasang aplikasinya dari file APK yang aku kirim, lalu masuk dengan akun Google kamu.';
  }

  Future<void> _sync() async {
    setState(() {
      syncing = true;
      syncStatus = 'Menghubungkan Gmail…';
    });
    try {
      final r = await Recorder.syncGmail((t) {
        if (mounted) setState(() => syncStatus = t);
      });
      syncStatus = r;
    } catch (e) {
      syncStatus = 'Sync gagal: $e';
    }
    if (mounted) setState(() => syncing = false);
  }

  Future<void> _editMember(Member? m) async {
    final name = TextEditingController(text: m?.name ?? '');
    final mail = TextEditingController(text: m?.email ?? '');
    final phone = TextEditingController(text: m?.phone ?? '');
    var role = m?.role ?? 'anggota';
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (c, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m == null ? 'Tambah anggota' : 'Ubah anggota', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: deco('Nama')),
            const SizedBox(height: 10),
            TextField(controller: mail, keyboardType: TextInputType.emailAddress, decoration: deco('Email akun Google (untuk login)')),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: deco('Nomor WhatsApp (untuk undangan)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: role == 'pengamat' ? 'pengamat' : 'anggota',
              decoration: deco('Peran'),
              items: const [
                DropdownMenuItem(value: 'anggota', child: Text('Anggota (chat dan ubah agenda)')),
                DropdownMenuItem(value: 'pengamat', child: Text('Hanya melihat')),
              ],
              onChanged: (v) => set(() => role = v ?? role),
            ),
            const SizedBox(height: 14),
            Row(children: [
              if (m != null && m.email != AppState.I.email) ...[
                deleteButton(() async {
                  Navigator.pop(c);
                  await AppState.I.deleteMember(m);
                }),
                const SizedBox(width: 8),
                if (m.email.isNotEmpty && m.email != AppState.I.adminEmail)
                  TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        await AppState.I.makeAdmin(m);
                      },
                      child: const Text('Jadikan admin')),
              ],
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  if (name.text.trim().isEmpty) return;
                  Navigator.pop(c);
                  await AppState.I.saveMember(m, name.text.trim(), mail.text.trim(), phone.text.trim(), role);
                },
                child: const Text('Simpan'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _editTrip() async {
    final s = AppState.I;
    final name = TextEditingController(text: s.tripName);
    final start = TextEditingController(text: s.start);
    final end = TextEditingController(text: s.end);
    final model = TextEditingController(text: s.geminiModel);
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ubah trip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: deco('Nama trip')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: start, decoration: deco('Mulai (YYYY-MM-DD)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: end, decoration: deco('Selesai (YYYY-MM-DD)'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: model, decoration: deco('Model Gemini (mis. gemini-flash-latest)')),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                Navigator.pop(c);
                await s.updateTrip({
                  'name': name.text.trim(),
                  'start': start.text.trim(),
                  'end': end.text.trim(),
                  'geminiModel': model.text.trim(),
                });
              },
              child: const Text('Simpan'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final members = s.members.toList()..sort((a, b) => (b.email == s.adminEmail ? 1 : 0).compareTo(a.email == s.adminEmail ? 1 : 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.tripName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              if (s.isAdmin) OutlinedButton(onPressed: _editTrip, child: const Text('Ubah trip')),
            ]),
            const SizedBox(height: 4),
            Text('Admin: ${s.nameOfEmail(s.adminEmail)}. Admin mengatur anggota dan tanggal trip. Semua anggota bisa menambah, mengubah, dan menghapus agenda.',
                style: const TextStyle(color: C.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text('Masuk sebagai ${s.email}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
        SectionTitle('Anggota trip', trailing: s.isAdmin ? TextButton(onPressed: () => _editMember(null), child: const Text('+ Anggota')) : null),
        Container(
          decoration: cardBox(),
          child: Column(children: [
            for (final m in members)
              ListTile(
                leading: CircleAvatar(backgroundColor: C.toscaSoft, child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
                title: Text('${m.name}${m.email == s.email ? ' (Anda)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  m.email == s.adminEmail ? 'Admin' : (m.role == 'pengamat' ? 'Hanya melihat' : 'Anggota'),
                  m.email.isEmpty ? 'email belum diisi' : m.email,
                ].join(' · ')),
                trailing: s.isAdmin
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        if (m.phone.isNotEmpty && m.email != s.email)
                          IconButton(
                              tooltip: 'Undang lewat WhatsApp',
                              onPressed: () => openUrl('https://wa.me/${waNumber(m.phone)}?text=${Uri.encodeComponent(_invite(m.name))}'),
                              icon: const Icon(Icons.chat_outlined, color: Color(0xFF25A35A))),
                        IconButton(onPressed: () => _editMember(m), icon: const Icon(Icons.edit_outlined)),
                      ])
                    : null,
              ),
          ]),
        ),
        if (s.isAdmin) ...[
          const SizedBox(height: 8),
          const Text('Anggota baru perlu email akun Google-nya didaftarkan di sini sebelum bisa masuk.', style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25A35A)),
            onPressed: () => openUrl('https://wa.me/?text=${Uri.encodeComponent(_invite(''))}'),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Bagikan undangan ke WhatsApp'),
          ),
        ],
        const SectionTitle('Sync email'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Baca email booking terbaru (KAI, hotel, Traveloka, dll.) dari Gmail Anda, lalu catat booking dan harganya. Email yang sudah pernah dibaca dilewati.',
                style: TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: syncing || s.isViewer ? null : _sync,
              icon: syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.mail_outline),
              label: Text(syncing ? 'Menyinkronkan…' : 'Sync Gmail sekarang'),
            ),
            if (syncStatus != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(syncStatus!)),
          ]),
        ),
        const SectionTitle('Pengingat'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: cardBox(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                'Pengingat otomatis di HP ini: malam sebelumnya pukul 20.00, 3 jam dan 30 menit sebelum kereta, 30 menit sebelum agenda lain. '
                'Terjadwal sekarang: ${NotificationService.I.scheduledCount}.',
                style: const TextStyle(fontSize: 12.5, color: C.muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton(
                  onPressed: () async {
                    await NotificationService.I.requestPermission();
                    await NotificationService.I.reschedule(s);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Aktifkan / jadwalkan ulang')),
              TextButton(
                  onPressed: () => NotificationService.I.showNow('Tes pengingat', 'Pengingat Jalan Bareng berfungsi.'),
                  child: const Text('Tes notifikasi')),
            ]),
          ]),
        ),
        const SectionTitle('Lainnya'),
        Container(
          decoration: cardBox(),
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Model AI'),
              subtitle: Text('${s.geminiModel} (Gemini)'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Google Places'),
              subtitle: Text(Places.enabled ? 'Aktif: foto dan rating tempat' : 'Belum aktif: PLACES_API_KEY belum diisi'),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Tambah agenda manual'),
              onTap: () => openForm(context, null, null),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Keluar'),
              onTap: () async {
                AppState.I.stop();
                await AuthService.I.signOut();
              },
            ),
          ]),
        ),
      ],
    );
  }
}
