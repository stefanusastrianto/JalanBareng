# Jalan Bareng — aplikasi Android

Aplikasi itinerary liburan keluarga untuk 2–4 orang: jadwal per hari, checklist booking, chat pencatat (struk, e-tiket, email), rencana vs realisasi biaya, foto dan rating Google Maps, pengingat, dan sync Gmail. Data tersimpan di HP sehingga tetap bisa dibuka tanpa sinyal, lalu sinkron saat online.

Semua layanan yang dipakai punya kuota gratis yang cukup untuk pemakaian keluarga:

| Layanan | Untuk apa | Biaya untuk 2–4 orang |
| --- | --- | --- |
| Firebase (paket Spark) | Login Google, database, offline | Gratis |
| Gemini API (tier gratis) | Membaca chat, struk, e-tiket, email | Gratis dalam batas harian. Di tier gratis, Google dapat memakai data yang dikirim untuk meningkatkan layanannya. |
| Google Places API (New) | Foto, rating, dan saran tempat | Kuota gratis per bulan. Wajib ada akun billing (kartu kredit). |
| Gmail API | Sync email booking | Gratis |
| GitHub Actions | Membangun file APK | Gratis untuk repo private dalam batas menit bulanan |

Total waktu setup: sekitar 1–2 jam, sekali saja. Semua langkah bisa dilakukan dari browser di laptop.

---

## Langkah 1 — Upload kode ke GitHub

1. Buat akun di github.com jika belum punya.
2. Buat repository baru: **New repository** → nama `jalan-bareng` → pilih **Private** → **Create repository**.
3. Ekstrak file zip ini di laptop.
4. Di halaman repo, klik **uploading an existing file**, lalu seret **semua isi** folder `jalan-bareng` (bukan foldernya) ke halaman itu → **Commit changes**.
   - Pastikan folder `.github` ikut terupload. Di Mac, folder yang diawali titik tersembunyi: tekan `Cmd + Shift + .` di Finder untuk menampilkannya.

## Langkah 2 — Buat kunci tanda tangan aplikasi (sekali saja)

1. Di repo, buka tab **Actions** → pilih **Buat kunci tanda tangan (sekali saja)** → **Run workflow**.
2. Setelah selesai (±1 menit), buka hasil run-nya:
   - Catat **SHA-1** yang tampil di ringkasan. Bentuknya seperti `AB:CD:12:...`.
   - Unduh artifact **kunci-tanda-tangan** dan ekstrak.
3. Buka **Settings** → **Secrets and variables** → **Actions** → **New repository secret**, lalu buat:
   - `DEBUG_KEYSTORE_B64` = isi file `DEBUG_KEYSTORE_B64.txt`
   - `ANDROID_CERT_SHA1` = isi file `ANDROID_CERT_SHA1.txt`

> Simpan file kunci ini. Kalau hilang, Anda perlu membuat kunci baru dan mendaftarkan ulang SHA-1 di langkah 3.

## Langkah 3 — Firebase (login dan database)

1. Buka console.firebase.google.com → **Create a project** → nama `jalan-bareng`. Google Analytics boleh dimatikan.
2. **Build → Authentication → Get started → Sign-in method → Google → Enable** → isi email dukungan → **Save**.
   - Buka lagi provider Google, bagian **Web SDK configuration**. Salin **Web client ID** → simpan sebagai secret `GOOGLE_WEB_CLIENT_ID`.
3. **Build → Firestore Database → Create database** → lokasi `asia-southeast2 (Jakarta)` → **Start in production mode**.
   - Buka tab **Rules**, ganti isinya dengan isi file `firestore.rules` dari zip ini → **Publish**.
4. **Project settings** (ikon roda gigi) → **Your apps** → ikon Android:
   - Package name: `id.jalanbareng.jalan_bareng`
   - SHA-1: tempel SHA-1 dari langkah 2
   - **Register app** → unduh `google-services.json` (file ini tidak perlu diupload ke repo).
5. Dari `google-services.json`, buat secret berikut:
   - `FIREBASE_API_KEY` = nilai `current_key` (di dalam `api_key`)
   - `FIREBASE_APP_ID` = nilai `mobilesdk_app_id`
   - `FIREBASE_SENDER_ID` = nilai `project_number`
   - `FIREBASE_PROJECT_ID` = nilai `project_id`

## Langkah 4 — Izin Gmail (untuk Sync email)

Proyek Firebase otomatis punya proyek Google Cloud dengan nama yang sama.

1. Buka console.cloud.google.com → pilih **Create API key in new project** (project tanpa billing, supaya tetap gratis).
2. **APIs & Services → Library** → cari **Gmail API** → **Enable**.
3. **APIs & Services → OAuth consent screen**:
   - User type: **External**. Status biarkan **Testing**.
   - **Test users** → tambahkan email Google Anda dan istri Anda.
   - **Data access / Scopes** → tambahkan `.../auth/gmail.readonly`.

> Di mode Testing, izin Gmail berlaku 7 hari. Setelah itu aplikasi akan meminta izin lagi saat menekan Sync. Ini normal untuk aplikasi pribadi yang tidak dipublikasikan.

## Langkah 5 — Gemini API (otak AI)

1. Buka aistudio.google.com → **Get API key** → **Create API key** → pilih **Create API key in new project** (project tanpa billing, supaya tetap gratis).
2. Simpan sebagai secret `GEMINI_API_KEY`.

Model default `gemini-flash-latest` (selalu versi Flash terbaru). Kalau Google mengganti atau menghentikan model ini, ubah nama model di aplikasi: **Admin → Ubah trip → Model Gemini**. Tidak perlu build ulang.

## Langkah 6 — Google Places (foto dan rating tempat)

1. Di console.cloud.google.com → **Billing** → hubungkan akun billing (kartu kredit). Pemakaian di bawah kuota gratis bulanan tetap Rp0.
2. **APIs & Services → Library** → cari **Places API (New)** → **Enable**.
3. **APIs & Services → Credentials → Create credentials → API key**. Lalu **Edit** key tersebut:
   - **Application restrictions**: Android apps → tambah package `id.jalanbareng.jalan_bareng` + SHA-1 dari langkah 2.
   - **API restrictions**: Restrict key → centang **Places API (New)**.
4. Simpan key sebagai secret `PLACES_API_KEY`.
5. Supaya aman dari tagihan tak terduga:
   - **Billing → Budgets & alerts** → buat anggaran kecil, misalnya US$1, dengan notifikasi email.
   - **APIs & Services → Places API (New) → Quotas** → batasi permintaan per hari, misalnya 100.

## Langkah 7 — Build APK

1. Tab **Actions** → **Build APK** → **Run workflow** (±10–15 menit).
2. Buka hasil run → unduh artifact **jalan-bareng-apk** → ekstrak → dapat `app-release.apk`.
3. Kirim file APK ke HP (misalnya lewat WhatsApp ke diri sendiri atau Google Drive) → buka → izinkan **Instal dari sumber tidak dikenal**.

Setiap kali kode diubah dan di-upload ulang ke GitHub, APK baru otomatis dibangun.

## Langkah 8 — Pemakaian pertama

1. **Anda (admin)**: buka aplikasi → **Masuk dengan Google** → **Impor data dari versi web**. Semua jadwal, booking, dan biaya dari versi claude.ai masuk, dan Anda menjadi admin.
2. Buka tab **Admin** → ketuk anggota **Anastasia** → isi email akun Google-nya → **Simpan**.
3. Kirim APK ke istri Anda → ia memasang dan masuk dengan akun Google tersebut.
4. Tab Admin → **Aktifkan / jadwalkan ulang** pengingat, lalu **Tes notifikasi**.

## Langkah 9 — Foto, video, dan video recap (versi 1.1)

1. Firebase console → kiri bawah **Spark · Upgrade** → pilih paket **Blaze** → pilih akun billing yang sudah ada. Pemakaian di bawah kuota gratis tetap Rp0.
2. **Databases and storage → Storage → Get started** → lokasi `asia-southeast2` (atau yang ditawarkan) → **Production mode** → **Done**.
3. Tab **Rules** → ganti isinya dengan isi file `storage.rules` → **Publish**. Kalau diminta memberi izin Storage membaca Firestore, klik **Grant**.
4. Google Cloud → **Budgets and caps** → buat budget kecil untuk layanan **Cloud Storage**.

Cara pakai:
- Selama trip, tab Jadwal menampilkan banner "N foto/video baru" → **Unggah**. Foto dikompres (±0,5 MB), video dikompres ke 720p. Masing-masing otomatis ditaruh di hari dan agenda sesuai jam pengambilan; bisa dipindah manual.
- Setiap jam 21.00 muncul notifikasi **Recap hari ini**. Ketuk → **Buat video recap**: Gemini memilih momen terbaik, video dirakit di HP, lalu bisa dibagikan ke WhatsApp. Malam terakhir: **recap seluruh trip**.

---

## Kalau ada masalah

| Gejala | Penyebab paling umum |
| --- | --- |
| Build gagal di langkah "Cek secrets" | Secret belum diisi atau namanya salah ketik |
| Build gagal di langkah lain | Kirim isi log error ke Claude untuk diperbaiki |
| "Gagal masuk" / error 10 saat login | SHA-1 di Firebase tidak sama dengan SHA-1 kunci (langkah 2 dan 3.4), atau `GOOGLE_WEB_CLIENT_ID` salah |
| "Email belum terdaftar di trip ini" | Admin belum mengisi email anggota di tab Admin |
| Chat: "Kuota harian Gemini sedang habis" | Batas harian tier gratis tercapai. Pesan tersimpan; tekan **Catat sekarang** besok |
| Chat: model tidak ditemukan | Ganti nama model di Admin → Ubah trip |
| Foto/rating tempat tidak muncul | `PLACES_API_KEY` kosong, billing belum aktif, atau pembatasan key belum memuat SHA-1 |
| Sync Gmail: izin ditolak | Email belum ditambahkan sebagai Test user di OAuth consent screen |
| Unggah foto gagal "permission denied" / "unauthorized" | Storage belum dibuat, `storage.rules` belum dipasang, atau project belum Blaze |
| Unggah foto gagal "bucket not found" | Nama bucket berbeda: salin nama bucket dari halaman Storage (tanpa `gs://`) ke secret `FIREBASE_STORAGE_BUCKET`, lalu build ulang |
| Recap gagal dirakit | Coba tanpa musik; HP lama kadang menolak campuran foto + video bersuara (aplikasi otomatis mencoba ulang tanpa suara) |
| Notifikasi tidak muncul | Izinkan notifikasi untuk Jalan Bareng di pengaturan HP; matikan penghemat baterai untuk aplikasi ini |

## Struktur kode

```
lib/
  main.dart              login, pembuka, navigasi 5 tab (Chat di tengah)
  config.dart            kunci-kunci dari build (--dart-define)
  models.dart            tipe data, tanggal, format rupiah
  store.dart             data Firestore (offline + sinkron)
  services/
    auth.dart            login Google + izin Gmail
    gemini.dart          panggilan Gemini API
    recorder.dart        pencatat: chat/struk/email → perubahan jadwal & biaya
    places.dart          Google Places (foto, rating, saran)
    gmail.dart           membaca email booking
    notifications.dart   pengingat lokal
  screens/               Jadwal, Checklist, Chat, Biaya, Admin, lembar detail
assets/seed.json         data trip dari versi web
firestore.rules          aturan akses database (hanya email anggota)
tool/patch_android.py    penyesuaian Android saat build
.github/workflows/       build APK dan pembuatan kunci
```
