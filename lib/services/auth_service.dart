import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_chat_app/models/user.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<AppUser?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _analytics.logLogin(loginMethod: 'email');
      final doc = await _firestore.collection('users').doc(result.user!.uid).get();
      if (!doc.exists) throw Exception('User document not found');
      return AppUser.fromMap(doc.data()!);
    } catch (e) {
      print('Sign-in error: $e');
      rethrow;
    }
  }

  Future<AppUser?> register(String email, String password, String displayName) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      AppUser user = AppUser(
        id: result.user!.uid,
        email: email,
        displayName: displayName,
      );
      await _firestore.collection('users').doc(user.id).set(user.toMap());
      await _analytics.logSignUp(signUpMethod: 'email');
      return user;
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _analytics.logEvent(name: 'sign_out');
  }

  AppUser? get currentUser {
    final user = _auth.currentUser;
    if (user != null) {
      return AppUser(
        id: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? 'User',
      );
    }
    return null;
  }
}