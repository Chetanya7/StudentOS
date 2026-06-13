import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/calendar'],
  );

  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } on PlatformException catch (e) {
      throw GoogleAuthException(_messageForPlatformException(e));
    } catch (e) {
      throw GoogleAuthException('Google sign-in failed. Please try again.');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  String _messageForPlatformException(PlatformException e) {
    final details = e.details?.toString() ?? '';
    final message = e.message ?? '';

    if (details.contains('ApiException: 10') ||
        message.contains('ApiException: 10')) {
      return 'Google sign-in is not configured correctly yet. Add this app\'s SHA-1 fingerprint in Google Cloud/Firebase, then rebuild the app.';
    }

    if (e.code == GoogleSignIn.kSignInCanceledError) {
      return 'Google sign-in was cancelled.';
    }

    if (e.code == GoogleSignIn.kNetworkError) {
      return 'Google sign-in failed because the network is unavailable.';
    }

    return 'Google sign-in failed: ${e.message ?? e.code}';
  }
}
