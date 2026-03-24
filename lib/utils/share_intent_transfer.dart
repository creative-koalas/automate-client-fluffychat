import 'package:psygo/widgets/share_scaffold_dialog.dart';

class ShareIntentTransfer {
  ShareIntentTransfer._();

  static String? _pendingRoomId;
  static List<ShareItem>? _pendingItems;

  static void setPending({
    required String roomId,
    required List<ShareItem> items,
  }) {
    _pendingRoomId = roomId;
    _pendingItems = List<ShareItem>.from(items);
  }

  static List<ShareItem>? takeForRoom(String roomId) {
    if (_pendingRoomId != roomId || _pendingItems == null) return null;
    final items = _pendingItems;
    _pendingRoomId = null;
    _pendingItems = null;
    return items;
  }
}
