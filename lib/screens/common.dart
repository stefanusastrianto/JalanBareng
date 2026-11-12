import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/gemini.dart';
import '../services/places.dart';
import '../services/recorder.dart';
import '../store.dart';

// ---------- palette (terang dan segar) ----------
class C {
  static const bg = Color(0xFFF5F9F8);
  static const surface = Colors.white;
  static const sunk = Color(0xFFEEF4F2);
  static const ink = Color(0xFF183230);
  static const muted = Color(0xFF667D7A);
  static const line = Color(0xFFE1EBE8);
  static const tosca = Color(0xFF0E9C8A);
  static const toscaSoft = Color(0xFFDDF4EF);
  static const coral = Color(0xFFF2704F);
  static const coralSoft = Color(0xFFFFE9E2);
  static const sky = Color(0xFF3E9FD8);
  static const skySoft = Color(0xFFE2F2FC);
  static const good = Color(0xFF1F9A5B);
  static const goodSoft = Color(0xFFE0F4E8);
  static const bad = Color(0xFFC4492B);
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

Future<void> openUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

String mapsSearch(String q) => 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}';

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, 'Disalin');
}

class TypeIcon extends StatelessWidget {
  final String type;
  final double size;
  const TypeIcon(this.type, {super.key, this.size = 38});
  @override
  Widget build(BuildContext context) {
    final t = typeOf(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(12)),
      child: Icon(t.icon, color: t.color, size: size * .55),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const Pill(this.text, {super.key, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
      );
}

Widget bookingPill(Item i) {
  if (!i.needsBooking) return const SizedBox.shrink();
  return i.booked
      ? Pill('✓ Sudah dibooking${i.bookingName.isEmpty ? '' : ' · a.n. ${i.bookingName}'}', fg: C.good, bg: C.goodSoft)
      : const Pill('Belum dibooking', fg: C.bad, bg: C.coralSoft);
}

String placeText(Item i) {
  if (i.location.isNotEmpty) return i.location;
  switch (i.type) {
    case 'makan':
      return 'Tempat makan belum ditentukan';
    case 'hotel':
      return 'Hotel belum dipilih';
    case 'wisata':
      return 'Tujuan wisata belum ditentukan';
  }
  return i.detail;
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(children: [
          Expanded(
              child: Text(text.toUpperCase(),
                  style: const TextStyle(fontSize: 11.5, letterSpacing: 1.2, color: C.muted, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

BoxDecoration cardBox({Color? border, double radius = 16, Color color = C.surface}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? C.line),
    );

// ---------- file picking ----------
String mimeFor(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

Future<List<AiFile>> pickFiles(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Foto struk atau e-tiket'), onTap: () => Navigator.pop(c, 'camera')),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Pilih dari galeri / screenshot'), onTap: () => Navigator.pop(c, 'gallery')),
        ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('File PDF atau gambar'), onTap: () => Navigator.pop(c, 'file')),
      ]),
    ),
  );
  final out = <AiFile>[];
  try {
    if (choice == 'camera') {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
      if (x != null) out.add(AiFile(x.name, 'image/jpeg', await x.readAsBytes()));
    } else if (choice == 'gallery') {
      final xs = await ImagePicker().pickMultiImage(maxWidth: 1600, imageQuality: 80);
      for (final x in xs) {
        out.add(AiFile(x.name, 'image/jpeg', await x.readAsBytes()));
      }
    } else if (choice == 'file') {
      const group = XTypeGroup(label: 'Dokumen', extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'], mimeTypes: ['application/pdf', 'image/*']);
      final xs = await openFiles(acceptedTypeGroups: [group]);
      for (final x in xs) {
        out.add(AiFile(x.name, mimeFor(x.name), await x.readAsBytes()));
      }
    }
  } catch (e) {
    if (context.mounted) toast(context, 'File tidak bisa dibuka: $e');
  }
  return out;
}

// ---------- Google Places card ----------
class RatingRow extends StatelessWidget {
  final PlaceInfo p;
  const RatingRow(this.p, {super.key});
  @override
  Widget build(BuildContext context) {
    if (p.rating == null) return const Text('Belum ada rating', style: TextStyle(fontSize: 12, color: C.muted));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5B400)),
      const SizedBox(width: 2),
      Text(p.rating!.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
      if (p.ratingCount != null) Text(' (${p.ratingCount})', style: const TextStyle(fontSize: 12, color: C.muted)),
    ]);
  }
}

class PlacePhoto extends StatelessWidget {
  final PlaceInfo p;
  final double width;
  final double height;
  final double radius;
  const PlacePhoto(this.p, {super.key, required this.width, required this.height, this.radius = 10});
  @override
  Widget build(BuildContext context) {
    final box = Container(width: width, height: height, color: C.toscaSoft, child: const Icon(Icons.image_outlined, color: C.tosca));
    if (p.photoName == null) return ClipRRect(borderRadius: BorderRadius.circular(radius), child: box);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: Places.photoUrl(p.photoName!, width: width > 200 ? 1200 : 400),
        cacheKey: 'gp:${p.photoName}',
        httpHeaders: Places.photoHeaders,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => box,
        errorWidget: (_, __, ___) => box,
      ),
    );
  }
}

/// Kartu tempat untuk agenda yang sudah punya lokasi: foto, rating Google, dan tautan ke Google Maps.
class PlaceCard extends StatefulWidget {
  final Item item;
  const PlaceCard(this.item, {super.key});
  @override
  State<PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<PlaceCard> {
  PlaceInfo? place;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final i = widget.item;
    try {
      if (i.placeId.isNotEmpty) {
        place = await Places.details(i.placeId);
      } else {
        final city = AppState.I.realCityLabel(i.date);
        final q = i.location.isNotEmpty ? i.location : i.title;
        final res = await Places.search(q.toLowerCase().contains(city.toLowerCase()) ? q : '$q $city', max: 1);
        if (res.isNotEmpty) {
          place = res.first;
          AppState.I.updateItem(i.id, {'placeId': place!.id});
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final fallbackUrl = mapsSearch(i.location.isNotEmpty ? i.location : i.title);
    if (!Places.enabled || (!loading && place == null)) {
      return OutlinedButton.icon(onPressed: () => openUrl(fallbackUrl), icon: const Icon(Icons.map_outlined), label: const Text('Buka di Google Maps'));
    }
    if (loading) return const LinearProgressIndicator(minHeight: 2);
    final p = place!;
    return InkWell(
      onTap: () => openUrl(p.mapsUri),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: cardBox(color: C.sunk, radius: 12, border: C.sunk),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PlacePhoto(p, width: 84, height: 72),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              RatingRow(p),
              const SizedBox(height: 2),
              Text(p.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: C.muted)),
              Text(p.photoAuthor.isEmpty ? 'Google Maps' : 'Foto: ${p.photoAuthor} · Google Maps',
                  style: const TextStyle(fontSize: 10, color: C.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Saran tempat nyata dari Google Places untuk agenda yang belum punya tempat.
class Suggestions extends StatefulWidget {
  final Item item;
  const Suggestions(this.item, {super.key});
  @override
  State<Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<Suggestions> {
  List<PlaceInfo>? list;
  bool loading = false;

  String _query() {
    final s = AppState.I;
    final i = widget.item;
    final city = s.realCityLabel(i.date);
    final same = s.itemsOn(i.date).where((x) => x.id != i.id && x.location.isNotEmpty).toList();
    Item? hotel;
    for (final x in same) {
      if (x.type == 'hotel') hotel = x;
    }
    if (hotel == null) {
      final before = s.sorted(s.items.where((x) => x.type == 'hotel' && x.location.isNotEmpty && x.date.compareTo(i.date) <= 0)).toList();
      if (before.isNotEmpty) hotel = before.last;
    }
    Item? spot;
    for (final x in same) {
      if (x.type == 'wisata' || x.type == 'ibadah') spot = x;
    }
    switch (i.type) {
      case 'hotel':
        return spot != null ? 'hotel keluarga dekat ${spot.location}' : 'hotel keluarga terbaik di $city';
      case 'makan':
        final near = spot?.location ?? hotel?.location;
        return near != null && near.isNotEmpty ? 'restoran keluarga dekat ${near.split(',').first} $city' : 'restoran khas $city untuk keluarga';
      default:
        return 'tempat wisata keluarga di $city';
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      list = await Places.search(_query(), max: 4);
    } catch (e) {
      if (mounted) toast(context, 'Saran belum bisa dimuat. Periksa koneksi.');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pick(PlaceInfo p) async {
    final i = widget.item;
    final title = i.type == 'hotel' ? p.name : (i.type == 'makan' ? 'Makan di ${p.name}' : p.name);
    final prev = {'title': i.d['title'], 'location': i.d['location'], 'placeId': i.d['placeId']};
    await AppState.I.updateItem(i.id, {'title': title, 'location': '${p.name}, ${p.address}', 'placeId': p.id});
    await AppState.I.addMessage({
      'role': 'assistant',
      'author': AppState.I.email,
      'authorName': 'Asisten',
      'text': '${AppState.I.myName} memilih ${p.name} untuk ${i.title} (${dayLabel(i.date)}).',
      'actions': [
        {'op': 'update', 'id': i.id, 'prev': prev, 'label': '${i.title} → ${p.name}'}
      ],
      'processed': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (mounted) {
      toast(context, 'Dipilih: ${p.name}');
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Places.enabled) {
      return OutlinedButton.icon(
          onPressed: () => openUrl(mapsSearch(_query())), icon: const Icon(Icons.search), label: const Text('Cari di Google Maps'));
    }
    if (list == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: loading ? null : _load,
          icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore),
          label: Text(loading ? 'Mencari…' : 'Cari saran tempat'),
        ),
      );
    }
    if (list!.isEmpty) return const Text('Belum ada saran yang cocok.', style: TextStyle(color: C.muted));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 236,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: list!.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (c, k) {
            final p = list![k];
            return Container(
              width: 190,
              padding: const EdgeInsets.all(8),
              decoration: cardBox(radius: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(onTap: () => openUrl(p.mapsUri), child: PlacePhoto(p, width: 174, height: 96)),
                const SizedBox(height: 6),
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                RatingRow(p),
                Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.muted)),
                const Spacer(),
                Row(children: [
                  Expanded(child: TextButton(onPressed: () => openUrl(p.mapsUri), child: const Text('Maps'))),
                  if (!AppState.I.isViewer) Expanded(child: FilledButton(onPressed: () => _pick(p), child: const Text('Pilih'))),
                ]),
              ]),
            );
          },
        ),
      ),
      const Text('Sumber: Google Maps', style: TextStyle(fontSize: 10, color: C.muted)),
    ]);
  }
}

// ---------- quick chat box (dipakai di lembar agenda dan hari) ----------
class QuickChat extends StatefulWidget {
  final String hint;
  final Map<String, dynamic> ctx;
  final VoidCallback onSent;
  const QuickChat({super.key, required this.hint, required this.ctx, required this.onSent});
  @override
  State<QuickChat> createState() => _QuickChatState();
}

class _QuickChatState extends State<QuickChat> {
  final ctl = TextEditingController();
  final files = <AiFile>[];

  Future<void> _send() async {
    final text = ctl.text.trim();
    if (text.isEmpty && files.isEmpty) {
      toast(context, 'Tulis pesan atau lampirkan file');
      return;
    }
    final f = List<AiFile>.from(files);
    final messenger = ScaffoldMessenger.of(context);
    widget.onSent();
    final err = await Recorder.send(text, f, ctx: widget.ctx);
    if (err != null) messenger.showSnackBar(SnackBar(content: Text(err), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (files.isNotEmpty)
        Wrap(spacing: 6, children: [
          for (var k = 0; k < files.length; k++)
            InputChip(label: Text(files[k].name, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => files.removeAt(k))),
        ]),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: C.tosca, width: 1.5)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
              onPressed: () async {
                final f = await pickFiles(context);
                setState(() => files.addAll(f));
              },
              icon: const Icon(Icons.attach_file)),
          Expanded(
            child: TextField(
              controller: ctl,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(hintText: widget.hint, border: InputBorder.none, isDense: true),
            ),
          ),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
        ]),
      ),
    ]);
  }
}

/// Gambar lampiran (e-tiket/struk) yang tersimpan di database, tersedia offline.
class StoredImage extends StatelessWidget {
  final String fileId;
  const StoredImage(this.fileId, {super.key});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: AppState.I.getFile(fileId),
      builder: (c, snap) {
        final f = snap.data;
        if (f == null) return const SizedBox.shrink();
        if (!str(f['mime']).startsWith('image/')) return Text('Lampiran: ${f['name']}');
        final bytes = base64Decode(str(f['data']));
        return GestureDetector(
          onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes)))),
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(bytes, height: 140, fit: BoxFit.cover)),
        );
      },
    );
  }
}
