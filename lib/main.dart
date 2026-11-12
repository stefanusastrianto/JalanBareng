import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config.dart';
import 'services/auth.dart';
import 'services/notifications.dart';
import 'store.dart';
import 'screens/admin_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/checklist_screen.dart';
import 'screens/common.dart';
import 'screens/cost_screen.dart';
import 'screens/gallery_screen.dart';
import 'screens/plan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: Config.firebaseApiKey,
      appId: Config.firebaseAppId,
      messagingSenderId: Config.firebaseSenderId,
      projectId: Config.firebaseProjectId,
      storageBucket: Config.storageBucket,
    ),
  );
  // Simpan salinan data di HP supaya bisa dibuka tanpa sinyal.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  await NotificationService.I.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jalan Bareng',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: C.tosca, primary: C.tosca, surface: C.surface),
        scaffoldBackgroundColor: C.bg,
        appBarTheme: const AppBarTheme(backgroundColor: C.surface, surfaceTintColor: C.surface, foregroundColor: C.ink, elevation: 0),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (c, snap) {
        final u = snap.data;
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (u == null) return const SignInScreen();
        if (AppState.I.user?.uid != u.uid) AppState.I.begin(u);
        return ListenableBuilder(listenable: AppState.I, builder: (c, _) => TripGate());
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: Image.asset('assets/logo.png', width: 200, height: 200, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Jalan Bareng', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Jadwal, booking, dan biaya liburan keluarga. Bisa dibuka tanpa sinyal.',
                textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await AuthService.I.signIn();
                      } catch (e) {
                        if (context.mounted) toast(context, 'Gagal masuk: $e');
                      }
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.login),
              label: Text(busy ? 'Masuk…' : 'Masuk dengan Google'),
            ),
          ]),
        ),
      ),
    );
  }
}

class TripGate extends StatelessWidget {
  const TripGate({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    if (!s.tripLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.accessError != null) return _NoAccess(email: s.email);
    if (s.tripMissing) return const SetupScreen();
    if (s.trip == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return HomeShell(); // tidak const: agar ikut dibangun ulang saat data berubah
  }
}

class _NoAccess extends StatelessWidget {
  final String email;
  const _NoAccess({required this.email});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.lock_outline, size: 48, color: C.coral),
              const SizedBox(height: 12),
              Text('Email $email belum terdaftar di trip ini.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Minta admin menambahkan email Anda di tab Admin, lalu buka aplikasi lagi.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(
                  onPressed: () async {
                    AppState.I.stop();
                    await AuthService.I.signOut();
                  },
                  child: const Text('Masuk dengan akun lain')),
            ]),
          ),
        ),
      );
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool busy = false;
  String? lastError;
  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e');
      lastError = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Selamat datang', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Belum ada trip. Impor data liburan keluarga dari versi web (jadwal, booking, dan biaya yang sudah tercatat), atau mulai trip kosong. Anda akan menjadi admin.',
                  textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
              const SizedBox(height: 24),
              FilledButton(onPressed: busy ? null : () => _run(() async => AppState.I.importSeed()), child: const Text('Impor data dari versi web')),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _run(() => AppState.I.createEmptyTrip('Trip baru', isoNow(), isoNow())),
                  child: const Text('Mulai trip kosong')),
              if (busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
            ]),
          ),
        ),
      );
}

String isoNow() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0; // 0 Jadwal, 1 Checklist, 2 Chat, 3 Biaya, 4 Admin

  @override
  void initState() {
    super.initState();
    NotificationService.I.requestPermission();
    NotificationService.I.launchPayload().then(AppState.I.openRoute);
  }

  /// Buka layar yang diminta dari notifikasi (mis. "recap:2026-12-18").
  void _handleRoute(AppState s) {
    final r = s.pendingRoute;
    if (r == null) return;
    s.pendingRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (r.startsWith('recap:')) {
        final d = r.substring(6);
        setState(() => tab = 0);
        openGallery(context, day: d == 'trip' ? null : d);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    _handleRoute(s);
    // Dibuat baru setiap build (bukan const) supaya setiap tab ikut menampilkan data terbaru.
    final pages = <Widget>[PlanScreen(), ChecklistScreen(), ChatScreen(), CostScreen(), AdminScreen()];
    final titles = ['Jadwal', 'Checklist booking', 'Chat', 'Biaya', 'Admin'];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tab == 0 ? s.tripName : titles[tab], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(
            s.start.length < 10 || s.end.length < 10 ? '' : '${s.start.substring(8)}/${s.start.substring(5, 7)} – ${s.end.substring(8)}/${s.end.substring(5, 7)}/${s.end.substring(0, 4)} · ${s.members.length} anggota',
            style: const TextStyle(fontSize: 12, color: C.muted),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Foto & video',
            onPressed: () => openGallery(context),
            icon: Badge(isLabelVisible: s.media.isNotEmpty, label: Text('${s.media.length}'), child: const Icon(Icons.photo_library_outlined)),
          ),
          if (s.fromCache)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(avatar: Icon(Icons.cloud_off, size: 16), label: Text('Offline'), visualDensity: VisualDensity.compact),
            ),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      // Saat tab Chat aktif, tombol bulat disembunyikan supaya tidak menutupi kotak ketik.
      floatingActionButton: tab == 2 ? null : SizedBox(
        width: 64,
        height: 64,
        child: FloatingActionButton(
          onPressed: () => setState(() => tab = 2),
          backgroundColor: tab == 2 ? C.coral : C.tosca,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: Badge(
            isLabelVisible: s.pending.isNotEmpty,
            label: Text('${s.pending.length}'),
            child: const Icon(Icons.chat_bubble_outline, size: 28),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        height: 68,
        padding: EdgeInsets.zero,
        color: C.surface,
        child: Row(children: [
          _tabBtn(0, Icons.calendar_month_outlined, 'Jadwal'),
          _tabBtn(1, Icons.checklist_rounded, 'Checklist', badge: s.todoBookings),
          tab == 2
              ? _tabBtn(2, Icons.chat_bubble, 'Chat')
              : const Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.muted))))),
          _tabBtn(3, Icons.receipt_long_outlined, 'Biaya'),
          _tabBtn(4, Icons.admin_panel_settings_outlined, 'Admin'),
        ]),
      ),
    );
  }

  Widget _tabBtn(int k, IconData icon, String label, {int badge = 0}) {
    final on = tab == k;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => tab = k),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, color: on ? C.tosca : C.muted)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? C.tosca : C.muted)),
        ]),
      ),
    );
  }
}
