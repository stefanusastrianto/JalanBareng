import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models.dart';
import '../services/media.dart';
import '../services/recap.dart';
import '../store.dart';
import 'common.dart';

String _mb(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).round()} KB' : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

// ======================================================================
// Strip foto kecil untuk kartu hari di tab Jadwal
// ======================================================================
class MediaStrip extends StatelessWidget {
  final String day;
  const MediaStrip(this.day, {super.key});
  @override
  Widget build(BuildContext context) {
    final list = AppState.I.mediaOn(day);
    if (list.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: list.length > 12 ? 13 : list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (c, k) {
          if (k == 12) {
            return InkWell(
              onTap: () => openGallery(context, day: day),
              child: Container(
                width: 64,
                decoration: BoxDecoration(color: C.sunk, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text('+${list.length - 12}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            );
          }
          return _Thumb(list[k], size: 64, onTap: () => openViewer(context, list, k));
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Media m;
  final double size;
  final VoidCallback onTap;
  const _Thumb(this.m, {required this.size, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.passthrough, children: [
            Image.network(m.thumbUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: 240,
                errorBuilder: (_, __, ___) => Container(width: size, height: size, color: C.sunk, child: const Icon(Icons.image_not_supported_outlined))),
            if (m.isVideo)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
                    Text('${(m.durationMs / 1000).round()}d', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        ),
      );
}

// ======================================================================
// Banner "ada foto baru" di tab Jadwal
// ======================================================================
class NewMediaBanner extends StatelessWidget {
  const NewMediaBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MediaService.I,
      builder: (c, _) {
        final ms = MediaService.I;
        if (ms.uploading || ms.failed > 0) return _UploadStatus(ms);
        final n = ms.newCount;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: cardBox(color: C.skySoft, border: C.skySoft, radius: 16),
          child: Row(children: [
            const Icon(Icons.photo_library_outlined, color: C.sky),
            const SizedBox(width: 10),
            Expanded(child: Text('$n foto/video baru dari trip di HP ini', style: const TextStyle(fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())), child: const Text('Tinjau')),
            FilledButton(onPressed: () => ms.enqueue(ms.newAssets), child: const Text('Unggah')),
          ]),
        );
      },
    );
  }
}

class _UploadStatus extends StatelessWidget {
  final MediaService ms;
  const _UploadStatus(this.ms);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: cardBox(color: C.toscaSoft, border: C.toscaSoft, radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                ms.uploading
                    ? 'Mengunggah ${ms.done + ms.failed + 1} dari ${ms.total} · ${ms.current}'
                    : 'Unggah selesai: ${ms.done} berhasil, ${ms.failed} gagal',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (!ms.uploading) IconButton(onPressed: ms.resetCounters, icon: const Icon(Icons.close, size: 18)),
          ]),
          if (ms.uploading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: ms.total == 0 ? null : (ms.done + ms.failed) / ms.total, color: C.tosca, backgroundColor: Colors.white),
          ],
          if (!ms.uploading && ms.lastError != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(ms.lastError!, style: const TextStyle(color: C.bad, fontSize: 12))),
        ]),
      );
}

// ======================================================================
// Galeri lengkap: per hari, dikelompokkan per agenda
// ======================================================================
Future<void> openGallery(BuildContext context, {String? day}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => GalleryScreen(day: day)));

class GalleryScreen extends StatelessWidget {
  final String? day;
  const GalleryScreen({super.key, this.day});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, MediaService.I]),
      builder: (c, _) {
        final s = AppState.I;
        final days = day == null ? s.tripDays().where((d) => s.mediaOn(d).isNotEmpty).toList() : [day!];
        final recaps = s.recaps.where((r) => day == null || r.date == day || r.scope == 'trip').toList();
        return Scaffold(
          appBar: AppBar(title: Text(day == null ? 'Foto & video trip' : 'Foto & video · ${dayLabel(day!)}')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            const NewMediaBanner(),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Ambil dari galeri HP'),
              ),
              OutlinedButton.icon(
                onPressed: () => openRecap(context, day),
                icon: const Icon(Icons.movie_creation_outlined),
                label: Text(day == null ? 'Recap seluruh trip' : 'Recap hari ini'),
              ),
            ]),
            if (recaps.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Video recap', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              for (final r in recaps) _RecapTile(r),
            ],
            const SizedBox(height: 16),
            if (days.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: cardBox(),
                child: const Text(
                    'Belum ada foto atau video. Ketuk "Ambil dari galeri HP": aplikasi mencari foto yang Anda ambil selama tanggal trip dan menaruhnya otomatis di hari dan agenda yang sesuai.',
                    style: TextStyle(color: C.muted)),
              ),
            for (final d in days) _DaySection(d),
          ]),
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  final String d;
  const _DaySection(this.d);
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final list = s.mediaOn(d);
    final groups = <String, List<Media>>{};
    for (final m in list) {
      groups.putIfAbsent(m.itemId, () => []).add(m);
    }
    final order = s.itemsOn(d).map((i) => i.id).where(groups.containsKey).toList();
    if (groups.containsKey('')) order.insert(0, '');
    for (final k in groups.keys) {
      if (!order.contains(k)) order.add(k);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${dayLabel(d)} · ${s.realCityLabel(d)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          Text('${list.length}', style: const TextStyle(color: C.muted)),
          TextButton(onPressed: () => openRecap(context, d), child: const Text('Recap')),
        ]),
        for (final key in order) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              key.isEmpty ? 'Di luar agenda' : (s.items.where((i) => i.id == key).firstOrNull?.title ?? 'Agenda dihapus'),
              style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final m in groups[key]!)
                LayoutBuilder(builder: (c, bc) => _Thumb(m, size: bc.maxWidth, onTap: () => openViewer(context, list, list.indexOf(m)))),
            ],
          ),
        ],
      ]),
    );
  }
}

class _RecapTile extends StatelessWidget {
  final Recap r;
  const _RecapTile(this.r);
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: C.coralSoft,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.movie_outlined, color: C.coral),
          title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${r.scope == 'trip' ? 'Seluruh trip' : dayLabel(r.date)} · ${(r.durationMs / 1000).round()} dtk · oleh ${r.byName}'),
          trailing: IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => shareRecap(context, r)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPage(url: r.url, title: r.title))),
        ),
      );
}

Future<void> shareRecap(BuildContext context, Recap r) async {
  toast(context, 'Menyiapkan video…');
  try {
    final f = await MediaService.I.download(r.path, 'share_${r.id}.mp4');
    await Share.shareXFiles([XFile(f.path, mimeType: 'video/mp4')], text: r.title);
  } catch (e) {
    if (context.mounted) toast(context, 'Gagal membagikan: $e');
  }
}

// ======================================================================
// Pindai galeri HP dan pilih yang mau diunggah
// ======================================================================
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final Set<String> selected = {};
  bool showSkipped = false;
  bool _init = false;

  @override
  void initState() {
    super.initState();
    MediaService.I.scan().then((_) {
      if (!mounted) return;
      setState(() {
        selected.addAll(MediaService.I.newAssets.map((a) => a.id));
        _init = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, MediaService.I]),
      builder: (c, _) {
        final ms = MediaService.I;
        final s = AppState.I;
        final up = s.myUploadedAssets;
        final skipped = s.skippedAssets.toSet();
        final list = ms.found.where((a) => !up.contains(a.id) && (showSkipped || !skipped.contains(a.id))).toList();
        final byDay = <String, List<DeviceAsset>>{};
        for (final a in list) {
          byDay.putIfAbsent(a.day, () => []).add(a);
        }
        final nSel = list.where((a) => selected.contains(a.id)).length;
        final nVid = list.where((a) => selected.contains(a.id) && a.isVideo).length;
        final est = (nSel - nVid) * 600 * 1024 + list.where((a) => selected.contains(a.id) && a.isVideo).fold<int>(0, (t, a) => t + a.a.duration * 330 * 1024);
        return Scaffold(
          appBar: AppBar(title: const Text('Foto & video di HP ini'), actions: [
            if (skipped.isNotEmpty)
              TextButton(onPressed: () => setState(() => showSkipped = !showSkipped), child: Text(showSkipped ? 'Sembunyikan dilewati' : 'Lihat dilewati')),
          ]),
          body: ms.permitted == false
              ? _NoPermission(onRetry: () => ms.scan())
              : ms.scanning || !_init
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(
                          child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            ms.found.isEmpty
                                ? 'Tidak ada foto/video di HP ini yang diambil antara ${shortDay(s.start)} dan ${shortDay(s.end)}.'
                                : 'Semua foto/video trip di HP ini sudah diunggah.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: C.muted),
                          ),
                        ))
                      : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 110), children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                            child: Text('Semua sudah dipilih. Ketuk untuk membatalkan yang tidak ingin dibagikan, misalnya screenshot.',
                                style: TextStyle(color: C.muted)),
                          ),
                          for (final d in (byDay.keys.toList()..sort())) ...[
                            Row(children: [
                              Expanded(child: Text(dayLabel(d), style: const TextStyle(fontWeight: FontWeight.w800))),
                              TextButton(
                                onPressed: () => setState(() {
                                  final ids = byDay[d]!.map((a) => a.id);
                                  if (ids.every(selected.contains)) {
                                    selected.removeAll(ids);
                                  } else {
                                    selected.addAll(ids);
                                  }
                                }),
                                child: const Text('Pilih/lepas semua'),
                              ),
                            ]),
                            GridView.count(
                              crossAxisCount: 4,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                for (final a in byDay[d]!)
                                  _AssetTile(a, selected.contains(a.id), () => setState(() => selected.contains(a.id) ? selected.remove(a.id) : selected.add(a.id))),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ]),
          bottomSheet: list.isEmpty
              ? null
              : SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    color: C.surface,
                    child: Row(children: [
                      Expanded(
                        child: Text('$nSel dipilih${nVid > 0 ? ' ($nVid video)' : ''}\nperkiraan ${_mb(est)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final skip = list.where((a) => !selected.contains(a.id)).map((a) => a.id).toList();
                          await s.skipAssets(skip);
                          if (context.mounted) toast(context, '${skip.length} dilewati dan tidak akan ditawarkan lagi');
                        },
                        child: const Text('Lewati sisanya'),
                      ),
                      FilledButton(
                        onPressed: nSel == 0
                            ? null
                            : () async {
                                final pick = list.where((a) => selected.contains(a.id)).toList();
                                final skip = list.where((a) => !selected.contains(a.id)).map((a) => a.id).toList();
                                ms.enqueue(pick);
                                if (skip.isNotEmpty) await s.skipAssets(skip);
                                if (context.mounted) {
                                  toast(context, 'Mengunggah $nSel. Boleh pindah layar, unggahan tetap berjalan.');
                                  Navigator.pop(context);
                                }
                              },
                        child: const Text('Unggah'),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

class _NoPermission extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoPermission({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 44, color: C.coral),
            const SizedBox(height: 10),
            const Text('Aplikasi perlu izin membaca foto & video untuk mencari foto trip Anda.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Beri izin')),
            TextButton(onPressed: () => PhotoManager.openSetting(), child: const Text('Buka pengaturan HP')),
          ]),
        ),
      );
}

class _AssetTile extends StatelessWidget {
  final DeviceAsset a;
  final bool on;
  final VoidCallback onTap;
  const _AssetTile(this.a, this.on, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          FutureBuilder<Uint8List?>(
            future: a.a.thumbnailDataWithSize(const ThumbnailSize(240, 240), quality: 70),
            builder: (c, snap) => snap.data == null ? Container(color: C.sunk) : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (!on) Container(color: Colors.white.withValues(alpha: 0.6)),
          Positioned(
            top: 4,
            right: 4,
            child: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? C.tosca : Colors.white, size: 22),
          ),
          if (a.isVideo)
            const Positioned(left: 4, bottom: 4, child: Icon(Icons.videocam_rounded, color: Colors.white, size: 18)),
          Positioned(
            right: 4,
            bottom: 2,
            child: Text('${two(a.taken.hour)}:${two(a.taken.minute)}',
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 3)])),
          ),
        ]),
      );
}

// ======================================================================
// Penampil foto/video
// ======================================================================
Future<void> openViewer(BuildContext context, List<Media> list, int index) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => _Viewer(list: list, index: index)));

class _Viewer extends StatefulWidget {
  final List<Media> list;
  final int index;
  const _Viewer({required this.list, required this.index});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final PageController pc = PageController(initialPage: widget.index);
  late int k = widget.index;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final m = widget.list[k];
    final item = s.items.where((i) => i.id == m.itemId).firstOrNull;
    final mine = m.by == s.email || s.isAdmin;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${dayLabel(m.date)} · ${m.time}', style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(icon: const Icon(Icons.drive_file_move_outlined), tooltip: 'Pindah agenda', onPressed: () => _move(m)),
          if (mine)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Hapus',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Hapus dari trip?'),
                    content: const Text('File di galeri HP tidak ikut terhapus.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus')),
                    ],
                  ),
                );
                if (ok == true) {
                  await MediaService.I.delete(m);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: pc,
            itemCount: widget.list.length,
            onPageChanged: (i) => setState(() => k = i),
            itemBuilder: (c, i) {
              final x = widget.list[i];
              if (x.isVideo) return _VideoBox(url: x.url, key: ValueKey(x.id));
              return InteractiveViewer(
                child: Center(
                  child: Image.network(x.url,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, p) => p == null ? child : Image.network(x.thumbUrl, fit: BoxFit.contain)),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Text('${item?.title ?? 'Di luar agenda'} · oleh ${m.byName}', style: const TextStyle(color: Colors.white70)),
        ),
      ]),
    );
  }

  Future<void> _move(Media m) async {
    final its = AppState.I.itemsOn(m.date);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Pindahkan ke agenda', style: TextStyle(fontWeight: FontWeight.w800))),
        ListTile(title: const Text('Di luar agenda'), onTap: () => Navigator.pop(c, '')),
        for (final i in its)
          ListTile(leading: TypeIcon(i.type, size: 30), title: Text(i.title), subtitle: Text(i.time), onTap: () => Navigator.pop(c, i.id)),
      ]),
    );
    if (pick != null) await MediaService.I.moveToItem(m, pick);
    if (mounted) setState(() {});
  }
}

class _VideoBox extends StatefulWidget {
  final String url;
  const _VideoBox({required this.url, super.key});
  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  late final VideoPlayerController vc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool ready = false;
  String? err;

  @override
  void initState() {
    super.initState();
    vc.initialize().then((_) {
      if (!mounted) return;
      setState(() => ready = true);
      vc.play();
    }).catchError((Object e) {
      if (mounted) setState(() => err = e.toString());
    });
    vc.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (err != null) return Center(child: Text('Video tidak bisa diputar.\n$err', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center));
    if (!ready) return const Center(child: CircularProgressIndicator(color: Colors.white));
    return GestureDetector(
      onTap: () => vc.value.isPlaying ? vc.pause() : vc.play(),
      child: Stack(alignment: Alignment.center, children: [
        Center(child: AspectRatio(aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc))),
        if (!vc.value.isPlaying) const Icon(Icons.play_circle_fill, color: Colors.white70, size: 72),
        Positioned(left: 0, right: 0, bottom: 0, child: VideoProgressIndicator(vc, allowScrubbing: true)),
      ]),
    );
  }
}

class VideoPage extends StatelessWidget {
  final String url;
  final String title;
  const VideoPage({super.key, required this.url, required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
        body: _VideoBox(url: url, key: ValueKey(url)),
      );
}

// ======================================================================
// Membuat recap
// ======================================================================
Future<void> openRecap(BuildContext context, String? day) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: C.surface,
    builder: (c) => _RecapSheet(day: day),
  );
}

class _RecapSheet extends StatefulWidget {
  final String? day;
  const _RecapSheet({this.day});
  @override
  State<_RecapSheet> createState() => _RecapSheetState();
}

class _RecapSheetState extends State<_RecapSheet> {
  String? music;
  String? musicName;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final day = widget.day;
    final count = day == null ? s.media.length : s.mediaOn(day).length;
    return ListenableBuilder(
      listenable: RecapService.I,
      builder: (c, _) {
        final r = RecapService.I;
        final done = !r.running && r.lastPath != null && r.error == null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(day == null ? 'Recap seluruh trip' : 'Recap ${dayLabel(day)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '$count foto/video tersedia. Gemini memilih momen terbaik (maks ${day == null ? 40 : 18}), lalu video dirakit langsung di HP. '
              'Video ${day == null ? '±2 menit' : '±45 detik'}, dengan judul dan keterangan tempat. Sebaiknya pakai Wi-Fi.',
              style: const TextStyle(color: C.muted),
            ),
            const SizedBox(height: 12),
            if (!r.running && !done) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await openFile(acceptedTypeGroups: [
                    const XTypeGroup(label: 'Audio', extensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg'], mimeTypes: ['audio/*']),
                  ]);
                  if (f != null) setState(() {
                    music = f.path;
                    musicName = f.name;
                  });
                },
                icon: const Icon(Icons.music_note_outlined),
                label: Text(musicName == null ? 'Tambah musik dari HP (opsional)' : 'Musik: $musicName'),
              ),
              const SizedBox(height: 4),
              const Text('Tanpa musik, suara asli dari klip video dipakai.', style: TextStyle(color: C.muted, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: count == 0 ? null : () => r.make(day: day, musicPath: music),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Buat video recap'),
                ),
              ),
            ],
            if (r.running) ...[
              Text(r.status, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: r.progress, color: C.coral, backgroundColor: C.coralSoft),
              const SizedBox(height: 8),
              const Text('Biarkan aplikasi tetap terbuka sampai selesai.', style: TextStyle(color: C.muted, fontSize: 12)),
            ],
            if (!r.running && r.error != null) ...[
              const SizedBox(height: 8),
              Text(r.error!, style: const TextStyle(color: C.bad)),
            ],
            if (done) ...[
              Text('Selesai: ${r.lastTitle ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Sudah tersimpan di aplikasi, jadi anggota lain juga bisa menontonnya.', style: TextStyle(color: C.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _LocalVideoPage(path: r.lastPath!, title: r.lastTitle ?? 'Recap'))),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Putar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25A35A)),
                  onPressed: () => Share.shareXFiles([XFile(r.lastPath!, mimeType: 'video/mp4')], text: r.lastTitle),
                  icon: const Icon(Icons.share),
                  label: const Text('Bagikan (WhatsApp)'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await PhotoManager.editor.saveVideo(File(r.lastPath!), title: 'Recap ${r.lastTitle ?? ''}.mp4');
                      if (context.mounted) toast(context, 'Tersimpan di galeri HP');
                    } catch (e) {
                      if (context.mounted) toast(context, 'Gagal menyimpan: $e');
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Simpan ke galeri'),
                ),
              ]),
            ],
          ]),
        );
      },
    );
  }
}

class _LocalVideoPage extends StatefulWidget {
  final String path;
  final String title;
  const _LocalVideoPage({required this.path, required this.title});
  @override
  State<_LocalVideoPage> createState() => _LocalVideoPageState();
}

class _LocalVideoPageState extends State<_LocalVideoPage> {
  late final VideoPlayerController vc = VideoPlayerController.file(File(widget.path));
  @override
  void initState() {
    super.initState();
    vc.initialize().then((_) {
      if (mounted) setState(() {});
      vc.play();
    });
    vc.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    vc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.title)),
        body: !vc.value.isInitialized
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : GestureDetector(
                onTap: () => vc.value.isPlaying ? vc.pause() : vc.play(),
                child: Center(child: AspectRatio(aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc))),
              ),
      );
}
