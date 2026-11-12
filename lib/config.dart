// Nilai-nilai ini diisi saat build lewat --dart-define (lihat .github/workflows/build.yml).
class Config {
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _bucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// Bucket Firebase Storage. Proyek baru memakai nama "<project-id>.firebasestorage.app".
  static String get storageBucket => _bucket.isNotEmpty ? _bucket : '$firebaseProjectId.firebasestorage.app';

  /// OAuth client ID bertipe "Web application" dari Google Cloud (dipakai Google Sign-In untuk Firebase).
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  static const geminiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const geminiModelDefault = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-flash-latest');
  static const placesKey = String.fromEnvironment('PLACES_API_KEY');

  /// Untuk pembatasan API key berdasarkan aplikasi Android.
  static const androidPackage = 'id.jalanbareng.jalan_bareng';
  static const androidCertSha1 = String.fromEnvironment('ANDROID_CERT_SHA1');

  static const tripId = 'main';
  static const timezone = 'Asia/Jakarta';
}
