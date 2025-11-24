import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AutomateAuthState extends ChangeNotifier {
  AutomateAuthState({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _chatbotKey = 'automate_chatbot_token';
  static const _primaryKey = 'automate_primary_token';
  static const _userIdKey = 'automate_user_id';

  bool _loggedIn = false;
  String? _chatbotToken;
  String? _primaryToken;
  String? _userId;

  bool get isLoggedIn => _loggedIn;
  String? get chatbotToken => _chatbotToken;
  String? get primaryToken => _primaryToken;
  String? get userId => _userId;

  Future<void> load() async {
    _primaryToken = await _storage.read(key: _primaryKey);
    _chatbotToken = await _storage.read(key: _chatbotKey);
    _userId = await _storage.read(key: _userIdKey);
    _loggedIn = _primaryToken != null && _chatbotToken != null;
    notifyListeners();
  }

  Future<void> save({
    required String primaryToken,
    required String chatbotToken,
    required String userId,
  }) async {
    _primaryToken = primaryToken;
    _chatbotToken = chatbotToken;
    _userId = userId;
    _loggedIn = true;
    await _storage.write(key: _primaryKey, value: primaryToken);
    await _storage.write(key: _chatbotKey, value: chatbotToken);
    await _storage.write(key: _userIdKey, value: userId);
    notifyListeners();
  }

  Future<void> markLoggedOut() async {
    _primaryToken = null;
    _chatbotToken = null;
    _userId = null;
    _loggedIn = false;
    await _storage.delete(key: _primaryKey);
    await _storage.delete(key: _chatbotKey);
    await _storage.delete(key: _userIdKey);
    notifyListeners();
  }
}
