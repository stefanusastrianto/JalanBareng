import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

const gmailScope = 'https://www.googleapis.com/auth/gmail.readonly';

class AuthService {
  AuthService._();
  static final AuthService I = AuthService._();

  final GoogleSignIn google = GoogleSignIn(
    scopes: const ['email'],
    serverClientId: Config.webClientId.isEmpty ? null : Config.webClientId,
  );

  Future<User?> signIn() async {
    final acc = await google.signIn();
    if (acc == null) return null;
    final auth = await acc.authentication;
    final cred = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
    final res = await FirebaseAuth.instance.signInWithCredential(cred);
    return res.user;
  }

  Future<void> signOut() async {
    await google.signOut();
    await FirebaseAuth.instance.signOut();
  }

  /// Minta izin baca Gmail (hanya sekali) lalu kembalikan header Authorization.
  Future<Map<String, String>?> gmailHeaders() async {
    var acc = google.currentUser ?? await google.signInSilently();
    acc ??= await google.signIn();
    if (acc == null) return null;
    final granted = await google.requestScopes(const [gmailScope]);
    if (!granted) return null;
    return (google.currentUser ?? acc).authHeaders;
  }
}
