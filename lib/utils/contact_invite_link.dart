import 'package:shared_preferences/shared_preferences.dart';

class ContactInviteLink {
  static const String _pendingTokenKey = 'pending_contact_invite_token';

  static String routeForToken(String token) =>
      '/invite/${Uri.encodeComponent(token)}';

  static String? extractTokenFromUrlString(String? url) {
    final raw = url?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return null;
    }
    return extractTokenFromUri(uri);
  }

  static String? extractTokenFromUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length >= 2 && segments.first == 'invite') {
      return Uri.decodeComponent(segments[1]);
    }
    if (uri.host == 'invite' && segments.isNotEmpty) {
      return Uri.decodeComponent(segments.first);
    }
    return null;
  }

  static Future<void> rememberPendingToken(String token) async {
    if (token.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingTokenKey, token);
  }

  static Future<String?> takePendingToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_pendingTokenKey);
    if (token != null && token.isNotEmpty) {
      await prefs.remove(_pendingTokenKey);
      return token;
    }
    return null;
  }
}
