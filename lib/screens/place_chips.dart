import 'package:flutter/material.dart';

import '../models.dart';
import '../services/places.dart';
import '../services/resolver.dart';
import '../store.dart';
import 'common.dart';
import 'sheets.dart';

/// Baris lokasi singkat di bawah agenda pada tab Jadwal:
/// chip tempat (foto, nama, rating → Google Maps), rute stasiun, atau pilihan yang perlu dipilih.
class PlaceLine extends StatelessWidget {
  final Item item;
  const PlaceLine(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    final i = item;
    switch (i.placeStatus) {
      case 'ok':
        if (i.placeId.isEmpty) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(top: 6), child: PlaceChip(i.placeId));
      case 'route':
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StationChip(i.fromPlaceId, i.from, icon: i.type == 'pesawat' ? Icons.flight_takeoff : Icons.trip_origin),
            const Icon(Icons.arrow_forward_rounded, size: 16, color: C.muted),
            StationChip(i.toPlaceId, i.to, icon: i.type == 'pesawat' ? Icons.flight_land : Icons.place),
          ]),
        );
      case 'pick':
        return Padding(padding: const EdgeInsets.only(top: 6), child: PickRow(i));
      case '':
        if (!Places.enabled || !{'hotel', 'makan', 'wisata', 'ibadah', 'kereta', 'pesawat'}.contains(i.type)) {
          return const SizedBox.shrink();
        }
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            SizedBox(width: 6),
            Text('Mencari lokasi di Google Maps…', style: TextStyle(fontSize: 11.5, color: C.muted)),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Ambil detail tempat (memori → cache HP → Google).
class _PlaceLoader extends StatelessWidget {
  final String id;
  final Widget Function(PlaceInfo? p, bool loading) builder;
  const _PlaceLoader(this.id, {required this.builder});
  @override
  Widget build(BuildContext context) {
    final hit = Places.cached(id);
    if (hit != null) return builder(hit, false);
    return FutureBuilder<PlaceInfo?>(
      future: Places.details(id),
      builder: (c, snap) => builder(snap.data, snap.connectionState != ConnectionState.done),
    );
  }
}

class PlaceChip extends StatelessWidget {
  final String id;
  const PlaceChip(this.id, {super.key});
  @override
  Widget build(BuildContext context) => _PlaceLoader(id, builder: (p, loading) {
        if (p == null) {
          return loading
              ? Container(height: 44, decoration: BoxDecoration(color: C.sunk, borderRadius: BorderRadius.circular(12)))
              : const SizedBox.shrink();
        }
        return InkWell(
          onTap: () => openUrl(p.mapsUri),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
            child: Row(children: [
              PlacePhoto(p, width: 40, height: 40),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  Row(children: [
                    RatingRow(p),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(p.address.split(',').take(2).join(','),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: C.muted)),
                    ),
                  ]),
                ]),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.map_outlined, size: 18, color: C.tosca)),
            ]),
          ),
        );
      });
}

class StationChip extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  const StationChip(this.id, this.label, {super.key, required this.icon});
  @override
  Widget build(BuildContext context) {
    Widget chip(String name, String? url) => InkWell(
          onTap: url == null ? null : () => openUrl(url),
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: C.skySoft, borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: C.sky),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.ink)),
              ),
            ]),
          ),
        );
    if (id.isEmpty) return label.isEmpty ? const SizedBox.shrink() : chip(label, mapsSearch(label));
    return _PlaceLoader(id, builder: (p, loading) => chip(p?.name ?? label, p?.mapsUri ?? mapsSearch(label)));
  }
}

/// Opsi tempat yang perlu dipilih, langsung di tab Jadwal.
class PickRow extends StatelessWidget {
  final Item item;
  const PickRow(this.item, {super.key});
  @override
  Widget build(BuildContext context) {
    final i = item;
    final viewer = AppState.I.isViewer;
    final ids = i.placeOptions;
    if (ids.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.touch_app_outlined, size: 15, color: C.coral),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            viewer
                ? 'Lokasi belum dipilih'
                : i.pickReason == 'suggest'
                    ? 'Saran dari Google Maps — pilih salah satu:'
                    : 'Lokasi yang mana? Pilih salah satu:',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.coral),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: viewer ? 150 : 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ids.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (c, k) => _Option(i, ids[k], viewer: viewer),
        ),
      ),
      if (!viewer)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            onPressed: () => openItem(context, i),
            child: const Text('Tidak ada yang cocok? Ketik nama tempatnya', style: TextStyle(fontSize: 12)),
          ),
        ),
    ]);
  }
}

class _Option extends StatelessWidget {
  final Item item;
  final String id;
  final bool viewer;
  const _Option(this.item, this.id, {required this.viewer});
  @override
  Widget build(BuildContext context) => _PlaceLoader(id, builder: (p, loading) {
        return Container(
          width: 156,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.line)),
          child: p == null
              ? Center(child: loading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Tidak tersedia'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(onTap: () => openUrl(p.mapsUri), child: PlacePhoto(p, width: 144, height: 70)),
                  const SizedBox(height: 4),
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  RatingRow(p),
                  const Spacer(),
                  if (!viewer)
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: FilledButton(
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        onPressed: () async {
                          await PlaceResolver.I.choose(item, p);
                          if (context.mounted) toast(context, 'Dipilih: ${p.name}');
                        },
                        child: const Text('Pilih'),
                      ),
                    ),
                ]),
        );
      });
}
