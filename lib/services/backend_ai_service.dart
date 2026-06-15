import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class BackendAiException implements Exception {
  const BackendAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackendAiService {
  const BackendAiService();

  Uri? get _baseUri {
    final value = dotenv.env['BACKEND_API_URL']?.trim() ?? '';
    if (value.isEmpty) return null;
    return Uri.tryParse(value);
  }

  bool get isConfigured => _baseUri != null;

  Future<String?> postText(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final raw = await postJson(path, body, timeout: timeout);
    final text = raw['text']?.toString();
    return text == null || text.trim().isEmpty ? null : text;
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final baseUri = _baseUri;
    if (baseUri == null) {
      throw const BackendAiException('BACKEND_API_URL is not configured.');
    }

    final idToken = await _googleIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const BackendAiException('Google ID token is unavailable.');
    }

    final uri = baseUri.resolve(path);
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'Backend AI request failed: ${response.statusCode} ${response.body}',
      );
      throw BackendAiException(
        'Backend request failed with status ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw const BackendAiException('Backend returned non-object JSON.');
  }

  Future<String?> _googleIdToken() async {
    final account = GoogleSignIn().currentUser;
    final auth = await account?.authentication;
    return auth?.idToken;
  }
}
