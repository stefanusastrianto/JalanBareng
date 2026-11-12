import 'package:flutter/material.dart';

import '../models.dart';
import '../services/gemini.dart';
import '../services/recorder.dart';
import '../store.dart';
import 'common.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ctl = TextEditingController();
  final files = <AiFile>[];

  Future<void> _send() async {
    final s = AppState.I;
    final text = ctl.text.trim();
    if (text.isEmpty && files.isEmpty) return;
    if (s.busy) {
      toast(context, 'Tunggu pesan sebelumnya selesai dicatat');
      return;
    }
    final f = List<AiFile>.from(files);
    ctl.clear();
    setState(() => files.clear());
    final err = await Recorder.send(text, f);
    if (err != null && mounted) toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final msgs = s.messages.reversed.toList();
    final pending = s.pending;
    return Column(children: [
      if (pending.isNotEmpty && !s.busy && !s.isViewer)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: C.skySoft, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: Text('${pending.length} pesan belum dicatat (kuota AI habis atau tidak ada sinyal).')),
            FilledButton(
                onPressed: () async {
                  final err = await Recorder.processPending();
                  if (err != null && context.mounted) toast(context, err);
                },
                child: const Text('Catat sekarang')),
          ]),
        ),
      Expanded(
        child: msgs.isEmpty
            ? ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: cardBox(),
                  child: const Text(
                      'Tulis kabar booking dengan bahasa biasa, lampirkan e-tiket, screenshot email, atau foto struk, atau tanya soal jadwal. Asisten mencocokkannya dengan jadwal, mencentang Checklist, dan mencatat biaya.'),
                ),
              ])
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: msgs.length + (s.typing.isNotEmpty ? 1 : 0),
                itemBuilder: (c, k) {
                  if (s.typing.isNotEmpty) {
                    if (k == 0) return Padding(padding: const EdgeInsets.all(8), child: Text(s.typing, style: const TextStyle(color: C.muted)));
                    k -= 1;
                  }
                  return _bubble(context, s, msgs[k]);
                },
              ),
      ),
      if (!s.isViewer) _composer(context, s),
    ]);
  }

  Widget _bubble(BuildContext context, AppState s, Msg m) {
    final ai = m.role == 'assistant';
    final mine = !ai && m.author == s.email;
    final who = ai ? 'Asisten · untuk ${s.nameOfEmail(m.author)}' : (mine ? 'Anda' : (m.authorName.isEmpty ? s.nameOfEmail(m.author) : m.authorName));
    final bg = ai ? const Color(0xFFF1FBF8) : (mine ? C.tosca : C.surface);
    final fg = mine ? Colors.white : C.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Text(who, style: const TextStyle(fontSize: 11, color: C.muted, fontWeight: FontWeight.w700)),
            if (m.contextLabel.isNotEmpty) Text('tentang ${m.contextLabel}', style: const TextStyle(fontSize: 11, color: C.muted)),
            if (m.text.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: ai ? const Color(0xFFBFE8DE) : (mine ? C.tosca : C.line))),
                child: SelectableText(m.text, style: TextStyle(color: fg)),
              ),
            for (final a in m.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: str(a['fileId']).isNotEmpty
                    ? SizedBox(width: 180, child: StoredImage(str(a['fileId'])))
                    : Chip(label: Text('📎 ${str(a['name'])}'), visualDensity: VisualDensity.compact),
              ),
            if (m.role == 'user' && !m.processed)
              const Padding(padding: EdgeInsets.only(top: 2), child: Text('Menunggu dicatat', style: TextStyle(fontSize: 11, color: Color(0xFFB77A00), fontWeight: FontWeight.w700))),
            for (final a in m.actions)
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: cardBox(radius: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      {'add': '+', 'unbook': '↺', 'expense': 'Rp', 'delete': '✕'}[str(a['op'])] ?? '✓',
                      style: const TextStyle(color: C.good, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(str(a['label']),
                          style: TextStyle(fontSize: 12.5, decoration: m.undone ? TextDecoration.lineThrough : null, color: m.undone ? C.muted : C.ink))),
                ]),
              ),
            if (ai && m.actions.isNotEmpty && !m.undone && !s.isViewer)
              TextButton(
                  onPressed: () async {
                    await Recorder.undo(m);
                    if (context.mounted) toast(context, 'Perubahan dibatalkan');
                  },
                  child: const Text('Batalkan perubahan ini')),
          ]),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, AppState s) {
    return SafeArea(
      top: false,
      child: Container(
        color: C.bg,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (s.messages.isEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in ['Apa saja yang belum dibooking?', 'Makan siang di Empal Gentong 285 ribu, saya yang bayar'])
                ActionChip(label: Text(t, style: const TextStyle(fontSize: 12)), onPressed: () => setState(() => ctl.text = t)),
            ]),
          if (files.isNotEmpty)
            Wrap(spacing: 6, children: [
              for (var k = 0; k < files.length; k++)
                InputChip(label: Text(files[k].name), onDeleted: () => setState(() => files.removeAt(k))),
            ]),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: C.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: C.tosca, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x220E9C8A), blurRadius: 14, offset: Offset(0, 4))],
            ),
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
                  maxLines: 6,
                  decoration: const InputDecoration(hintText: 'Kabar booking, foto struk, email, atau pertanyaan…', border: InputBorder.none, isDense: true),
                ),
              ),
              IconButton.filled(onPressed: s.busy ? null : _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ]),
      ),
    );
  }
}
