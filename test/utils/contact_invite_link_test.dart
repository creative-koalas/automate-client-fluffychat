import 'package:flutter_test/flutter_test.dart';
import 'package:psygo/utils/contact_invite_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContactInviteLink', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('builds encoded route for token', () {
      expect(
        ContactInviteLink.routeForToken('token/with space'),
        '/invite/token%2Fwith%20space',
      );
    });

    test('builds canonical https invite url for token', () {
      expect(
        ContactInviteLink.httpsUrlForToken('token/with space'),
        'https://psygoai.com/invite/token%2Fwith%20space',
      );
    });

    test('builds custom scheme invite url for token', () {
      expect(
        ContactInviteLink.customSchemeUrlForToken('token/with space'),
        'psygo://invite/token%2Fwith%20space',
      );
    });

    test('extracts token from invite page url', () {
      expect(
        ContactInviteLink.extractTokenFromUrlString(
          'https://user.psygoai.com/invite/token%2Fwith%20space',
        ),
        'token/with space',
      );
    });

    test('extracts token from custom invite host uri', () {
      final uri = Uri.parse('psygo://invite/token-123');
      expect(ContactInviteLink.extractTokenFromUri(uri), 'token-123');
    });

    test('returns null for unrelated url', () {
      expect(
        ContactInviteLink.extractTokenFromUrlString(
          'https://user.psygoai.com/rooms',
        ),
        isNull,
      );
    });

    test('remembers and consumes pending token once', () async {
      await ContactInviteLink.rememberPendingToken('invite-token');

      final first = await ContactInviteLink.takePendingToken();
      final second = await ContactInviteLink.takePendingToken();

      expect(first, 'invite-token');
      expect(second, isNull);
    });
  });
}
