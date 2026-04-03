import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

import 'package:psygo/config/setting_keys.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/chat_upload_limits.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/utils/macos_enter_ime_guard.dart';
import 'package:psygo/utils/matrix_input_mention.dart';
import 'package:psygo/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:psygo/utils/markdown_context_builder.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/room_display_name.dart';
import 'package:psygo/widgets/mxc_image.dart';
import '../../widgets/avatar.dart';
import '../../widgets/matrix.dart';
import 'command_hints.dart';

class InputBar extends StatefulWidget {
  final Room room;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<Uint8List?>? onSubmitImage;
  final ValueChanged<KeyboardInsertedContent>? onContentInserted;
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final MacOsEnterImeGuard? macOsEnterImeGuard;
  final bool? autofocus;
  final bool readOnly;
  final List<Emoji> suggestionEmojis;

  const InputBar({
    required this.room,
    this.minLines,
    this.maxLines,
    this.keyboardType,
    this.onSubmitted,
    this.onSubmitImage,
    this.onContentInserted,
    this.focusNode,
    this.controller,
    required this.decoration,
    this.onChanged,
    this.macOsEnterImeGuard,
    this.autofocus,
    this.textInputAction,
    this.readOnly = false,
    required this.suggestionEmojis,
    super.key,
  });

  @override
  State<InputBar> createState() => _InputBarState();

  int get _effectiveTextLengthLimit {
    final configuredLimit = AppSettings.textMessageMaxLength.value;
    final pduLimit = (maxPDUSize / 3).floor();
    return configuredLimit < pduLimit ? configuredLimit : pduLimit;
  }
}

class _InputBarState extends State<InputBar> {
  int _mentionPresentationVersion = 0;
  final OverlayPortalController _desktopSuggestionsOverlayController =
      OverlayPortalController();
  final LayerLink _desktopSuggestionsFieldLink = LayerLink();
  List<Map<String, String?>> _desktopSuggestions =
      const <Map<String, String?>>[];
  int? _desktopHighlightedSuggestionIndex;
  int _desktopSuggestionsRequestId = 0;

  Room get room => widget.room;
  int? get minLines => widget.minLines;
  int? get maxLines => widget.maxLines;
  TextInputType? get keyboardType => widget.keyboardType;
  TextInputAction? get textInputAction => widget.textInputAction;
  ValueChanged<String>? get onSubmitted => widget.onSubmitted;
  ValueChanged<Uint8List?>? get onSubmitImage => widget.onSubmitImage;
  ValueChanged<KeyboardInsertedContent>? get onContentInserted =>
      widget.onContentInserted;
  FocusNode? get focusNode => widget.focusNode;
  TextEditingController? get controller => widget.controller;
  InputDecoration get decoration => widget.decoration;
  ValueChanged<String>? get onChanged => widget.onChanged;
  MacOsEnterImeGuard? get macOsEnterImeGuard => widget.macOsEnterImeGuard;
  bool? get autofocus => widget.autofocus;
  bool get readOnly => widget.readOnly;
  List<Emoji> get suggestionEmojis => widget.suggestionEmojis;
  int get _effectiveTextLengthLimit => widget._effectiveTextLengthLimit;
  bool get _usesCustomDesktopSuggestions => PlatformInfos.isWindows;

  @override
  void initState() {
    super.initState();
    _attachDesktopInputListeners();
    AgentService.instance.profileNotifier.addListener(_handleProfileUpdated);
  }

  @override
  void didUpdateWidget(covariant InputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode) {
      _detachDesktopInputListeners(oldWidget);
      _attachDesktopInputListeners();
      if (_usesCustomDesktopSuggestions) {
        unawaited(_refreshDesktopSuggestions());
      }
    }
  }

  @override
  void dispose() {
    _detachDesktopInputListeners(widget);
    AgentService.instance.profileNotifier.removeListener(_handleProfileUpdated);
    super.dispose();
  }

  void _handleProfileUpdated() {
    if (!mounted) {
      return;
    }

    if (_usesCustomDesktopSuggestions) {
      unawaited(_refreshDesktopSuggestions());
      return;
    }

    setState(() {
      _mentionPresentationVersion++;
    });
  }

  void _attachDesktopInputListeners() {
    if (!_usesCustomDesktopSuggestions) {
      return;
    }
    widget.controller?.addListener(_handleDesktopTextChanged);
    widget.focusNode?.addListener(_handleDesktopFocusChanged);
  }

  void _detachDesktopInputListeners(InputBar targetWidget) {
    if (!_usesCustomDesktopSuggestions) {
      return;
    }
    targetWidget.controller?.removeListener(_handleDesktopTextChanged);
    targetWidget.focusNode?.removeListener(_handleDesktopFocusChanged);
  }

  void _handleDesktopTextChanged() {
    if (!_usesCustomDesktopSuggestions) {
      return;
    }
    unawaited(_refreshDesktopSuggestions());
  }

  void _handleDesktopFocusChanged() {
    if (!_usesCustomDesktopSuggestions) {
      return;
    }
    if (focusNode?.hasFocus ?? false) {
      unawaited(_refreshDesktopSuggestions());
      return;
    }
    _applyDesktopSuggestions(const <Map<String, String?>>[]);
  }

  int _resolvedHighlightedSuggestionIndex({
    required int? highlightedIndex,
    required int suggestionsLength,
  }) {
    if (suggestionsLength <= 0) {
      return -1;
    }
    if (highlightedIndex != null &&
        highlightedIndex >= 0 &&
        highlightedIndex < suggestionsLength) {
      return highlightedIndex;
    }
    return 0;
  }

  int? _resolvedAutocompleteTextOffset(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid) {
      return null;
    }

    final selectionEnd = selection.end;
    if (selectionEnd < 0) {
      return null;
    }

    if (!selection.isCollapsed) {
      final composing = value.composing;
      final selectionWithinComposing =
          composing.isValid &&
              selection.start >= composing.start &&
              selection.end <= composing.end;
      if (!selectionWithinComposing) {
        return null;
      }
    }

    return selectionEnd.clamp(0, value.text.length);
  }

  TextEditingValue _suggestionTextEditingValue(
    TextEditingValue value,
    Map<String, String?> suggestion,
  ) {
    final fullText = value.text;
    final rawOffset = _resolvedAutocompleteTextOffset(value) ??
        value.selection.end;
    final safeOffset = (rawOffset < 0 || rawOffset > fullText.length)
        ? fullText.length
        : rawOffset;
    final replaceText = fullText.substring(0, safeOffset);
    var startText = '';
    final afterText =
        safeOffset >= fullText.length ? '' : fullText.substring(safeOffset);
    var insertText = '';
    if (suggestion['type'] == 'command') {
      insertText = '${suggestion['name']!} ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'^(/\w*)$'),
        (Match m) => '/$insertText',
      );
    }
    if (suggestion['type'] == 'emoji') {
      insertText = '${suggestion['emoji']!} ';
      startText = replaceText.replaceAllMapped(
        suggestion['current_word']!,
        (Match m) => insertText,
      );
    }
    if (suggestion['type'] == 'emote') {
      var isUnique = true;
      final insertEmote = suggestion['name'];
      final insertPack = suggestion['pack'];
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      for (final pack in emotePacks.entries) {
        if (pack.key == insertPack) {
          continue;
        }
        for (final emote in pack.value.images.entries) {
          if (emote.key == insertEmote) {
            isUnique = false;
            break;
          }
        }
        if (!isUnique) {
          break;
        }
      }
      insertText = ':${isUnique ? '' : '${insertPack!}~'}$insertEmote: ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(:(?:[-\w]+~)?[-\w]+)$'),
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'user') {
      insertText = '${suggestion['mention']!} ';
      final replaced = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(@\S*)$'),
        (Match m) => '${m[1]}$insertText',
      );
      startText =
          replaced == replaceText ? '$replaceText$insertText' : replaced;
    }
    if (suggestion['type'] == 'room') {
      insertText = '${suggestion['mxid']!} ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(#[-\w]+)$'),
        (Match m) => '${m[1]}$insertText',
      );
    }

    return value.copyWith(
      text: startText + afterText,
      selection: TextSelection.collapsed(offset: startText.length),
      composing: TextRange.empty,
    );
  }

  bool _commitHighlightedSuggestion({
    required BuildContext context,
    required TextEditingController textController,
    required ValueNotifier<int?> highlightedSuggestionIndex,
  }) {
    final suggestions = _buildSuggestions(textController.value, context);
    if (suggestions.isEmpty) {
      highlightedSuggestionIndex.value = null;
      return false;
    }

    final resolvedIndex = _resolvedHighlightedSuggestionIndex(
      highlightedIndex: highlightedSuggestionIndex.value,
      suggestionsLength: suggestions.length,
    );
    if (resolvedIndex < 0) {
      highlightedSuggestionIndex.value = null;
      return false;
    }

    final nextValue = _suggestionTextEditingValue(
      textController.value,
      suggestions[resolvedIndex],
    );
    if (nextValue.text == textController.text &&
        nextValue.selection == textController.selection) {
      highlightedSuggestionIndex.value = null;
      return false;
    }

    textController.value = nextValue;
    highlightedSuggestionIndex.value = null;
    onChanged?.call(nextValue.text);
    return true;
  }

  Future<Iterable<Map<String, String?>>> getSuggestions(
    TextEditingValue text,
    BuildContext context,
  ) async {
    await _warmMentionPresentation(text);
    return _buildSuggestions(text, context);
  }

  void _applyDesktopSuggestions(List<Map<String, String?>> suggestions) {
    final shouldShowSuggestions =
        _usesCustomDesktopSuggestions &&
        (focusNode?.hasFocus ?? false) &&
        !readOnly &&
        suggestions.isNotEmpty;

    final nextHighlightedIndex = suggestions.isEmpty
        ? null
        : _resolvedHighlightedSuggestionIndex(
            highlightedIndex: _desktopHighlightedSuggestionIndex,
            suggestionsLength: suggestions.length,
          );

    if (mounted) {
      setState(() {
        _desktopSuggestions = List.unmodifiable(suggestions);
        _desktopHighlightedSuggestionIndex = nextHighlightedIndex;
      });
    }

    if (shouldShowSuggestions) {
      _desktopSuggestionsOverlayController.show();
    } else {
      _desktopSuggestionsOverlayController.hide();
    }
  }

  Future<void> _refreshDesktopSuggestions() async {
    if (!_usesCustomDesktopSuggestions) {
      return;
    }

    final textController = controller;
    final effectiveFocusNode = focusNode;
    if (!mounted ||
        textController == null ||
        effectiveFocusNode == null ||
        !effectiveFocusNode.hasFocus ||
        readOnly) {
      _applyDesktopSuggestions(const <Map<String, String?>>[]);
      return;
    }

    final requestId = ++_desktopSuggestionsRequestId;
    final suggestions = (await getSuggestions(textController.value, context))
        .toList(growable: false);
    if (!mounted ||
        requestId != _desktopSuggestionsRequestId ||
        controller != textController ||
        focusNode != effectiveFocusNode) {
      return;
    }

    _applyDesktopSuggestions(suggestions);
  }

  bool _commitDesktopHighlightedSuggestion() {
    final textController = controller;
    if (textController == null || _desktopSuggestions.isEmpty) {
      _desktopHighlightedSuggestionIndex = null;
      return false;
    }

    final resolvedIndex = _resolvedHighlightedSuggestionIndex(
      highlightedIndex: _desktopHighlightedSuggestionIndex,
      suggestionsLength: _desktopSuggestions.length,
    );
    if (resolvedIndex < 0) {
      _desktopHighlightedSuggestionIndex = null;
      return false;
    }

    final nextValue = _suggestionTextEditingValue(
      textController.value,
      _desktopSuggestions[resolvedIndex],
    );
    if (nextValue.text == textController.text &&
        nextValue.selection == textController.selection) {
      _desktopHighlightedSuggestionIndex = null;
      return false;
    }

    textController.value = nextValue;
    _desktopHighlightedSuggestionIndex = null;
    _desktopSuggestionsOverlayController.hide();
    onChanged?.call(nextValue.text);
    return true;
  }

  void _moveDesktopHighlightedSuggestion(int delta) {
    if (_desktopSuggestions.isEmpty) {
      return;
    }
    final currentIndex = _resolvedHighlightedSuggestionIndex(
      highlightedIndex: _desktopHighlightedSuggestionIndex,
      suggestionsLength: _desktopSuggestions.length,
    );
    final nextIndex = (currentIndex + delta).clamp(
          0,
          _desktopSuggestions.length - 1,
        );
    if (nextIndex == _desktopHighlightedSuggestionIndex) {
      return;
    }
    setState(() {
      _desktopHighlightedSuggestionIndex = nextIndex;
    });
  }

  void _setDesktopHighlightedSuggestion(int? index) {
    if (index == _desktopHighlightedSuggestionIndex) {
      return;
    }
    setState(() {
      _desktopHighlightedSuggestionIndex = index;
    });
  }

  void _selectDesktopSuggestion(Map<String, String?> suggestion) {
    final textController = controller;
    if (textController == null) {
      return;
    }
    final nextValue = _suggestionTextEditingValue(
      textController.value,
      suggestion,
    );
    if (nextValue.text == textController.text &&
        nextValue.selection == textController.selection) {
      return;
    }
    textController.value = nextValue;
    _desktopSuggestionsOverlayController.hide();
    onChanged?.call(nextValue.text);
  }

  Future<void> _warmMentionPresentation(TextEditingValue text) async {
    final textOffset = _resolvedAutocompleteTextOffset(text);
    if (textOffset == null) {
      return;
    }

    final searchText = text.text.substring(0, textOffset);
    final userMatch = RegExp(r'(?:\s|^)@([-\w]*)$').firstMatch(searchText);
    final cjkMentionMatch = RegExp(r'(?:\s|^)@(\S*)$').firstMatch(searchText);
    if (userMatch == null && cjkMentionMatch == null) {
      return;
    }

    if (room.directChatMatrixID != null) {
      return;
    }

    await AgentService.instance.ensureGroupDisplayNamesByMatrixUserIds(
      room.getParticipants().map((user) => user.id),
    );
  }

  List<Map<String, String?>> _buildSuggestions(
    TextEditingValue text,
    BuildContext context,
  ) {
    final textOffset = _resolvedAutocompleteTextOffset(text);
    if (textOffset == null) {
      return [];
    }
    final l10n = L10n.of(context);
    final matrixLocals = MatrixLocals(l10n);
    final mentionEveryone = _normalizedEveryoneMentionLabel(
      l10n.mentionEveryone,
    );
    final searchText = text.text.substring(0, textOffset);
    final ret = <Map<String, String?>>[];
    const maxResults = 30;

    final emojiMatch = RegExp(
      r'(?:\s|^):(?:([\p{L}\p{N}_-]+)~)?([\p{L}\p{N}_-]+)$',
      unicode: true,
    ).firstMatch(searchText);
    if (emojiMatch != null) {
      final packSearch = emojiMatch[1];
      final emoteSearch = emojiMatch[2]!.toLowerCase();
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      if (packSearch == null || packSearch.isEmpty) {
        for (final pack in emotePacks.entries) {
          for (final emote in pack.value.images.entries) {
            if (emote.key.toLowerCase().contains(emoteSearch)) {
              ret.add({
                'type': 'emote',
                'name': emote.key,
                'pack': pack.key,
                'pack_avatar_url': pack.value.pack.avatarUrl?.toString(),
                'pack_display_name': pack.value.pack.displayName ?? pack.key,
                'mxc': emote.value.url.toString(),
              });
            }
            if (ret.length > maxResults) {
              break;
            }
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      } else if (emotePacks[packSearch] != null) {
        for (final emote in emotePacks[packSearch]!.images.entries) {
          if (emote.key.toLowerCase().contains(emoteSearch)) {
            ret.add({
              'type': 'emote',
              'name': emote.key,
              'pack': packSearch,
              'pack_avatar_url':
                  emotePacks[packSearch]!.pack.avatarUrl?.toString(),
              'pack_display_name':
                  emotePacks[packSearch]!.pack.displayName ?? packSearch,
              'mxc': emote.value.url.toString(),
            });
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      }

      // aside of emote packs, also propose normal (tm) unicode emojis
      final matchingUnicodeEmojis = suggestionEmojis
          .where((emoji) => emoji.name.toLowerCase().contains(emoteSearch))
          .toList();

      // sort by the index of the search term in the name in order to have
      // best matches first
      // (thanks for the hint by github.com/nextcloud/circles devs)
      matchingUnicodeEmojis.sort((a, b) {
        final indexA = a.name.indexOf(emoteSearch);
        final indexB = b.name.indexOf(emoteSearch);
        if (indexA == -1 || indexB == -1) {
          if (indexA == indexB) return 0;
          if (indexA == -1) {
            return 1;
          } else {
            return 0;
          }
        }
        return indexA.compareTo(indexB);
      });
      for (final emoji in matchingUnicodeEmojis) {
        ret.add({
          'type': 'emoji',
          'emoji': emoji.emoji,
          'label': emoji.name,
          'current_word': ':$emoteSearch',
        });
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    // Trigger mention suggestions immediately after typing '@'.
    final userMatch = RegExp(r'(?:\s|^)@([-\w]*)$').firstMatch(searchText);
    // Also match CJK/localized input like @所有人 and plain '@'.
    final cjkMentionMatch = RegExp(r'(?:\s|^)@(\S*)$').firstMatch(searchText);
    final effectiveMatch = userMatch ?? cjkMentionMatch;
    if (effectiveMatch != null) {
      final userSearch = effectiveMatch[1]!.toLowerCase();

      // Add localized "@everyone" option in group chats
      final isGroupChat = room.directChatMatrixID == null;
      if (isGroupChat) {
        final everyoneAliases = <String>{
          'all',
          'everyone',
          'room',
          '所有人',
          '所有',
          '所',
        };
        final localizedAlias = mentionEveryone.startsWith('@')
            ? mentionEveryone.substring(1)
            : mentionEveryone;
        if (localizedAlias.isNotEmpty) {
          everyoneAliases.add(localizedAlias.toLowerCase());
        }
        if (everyoneAliases.any((alias) => alias.startsWith(userSearch))) {
          ret.add({
            'type': 'user',
            'mxid': '@room',
            'mention': mentionEveryone,
            'displayname': mentionEveryone,
            'avatar_url': null,
          });
        }
      }

      final participants = room.getParticipants().toList()
        ..sort((a, b) {
          final selfId = room.client.userID;
          if (a.id == selfId && b.id != selfId) return 1;
          if (b.id == selfId && a.id != selfId) return -1;

          final powerLevelCompare = b.powerLevel.compareTo(a.powerLevel);
          if (powerLevelCompare != 0) {
            return powerLevelCompare;
          }

          final displayNameA = resolveDisplayNameForMatrixUserId(
            room: room,
            matrixUserId: a.id,
            matrixLocals: matrixLocals,
          );
          final displayNameB = resolveDisplayNameForMatrixUserId(
            room: room,
            matrixUserId: b.id,
            matrixLocals: matrixLocals,
          );
          final displayNameCompare = displayNameA.toLowerCase().compareTo(
                displayNameB.toLowerCase(),
              );
          if (displayNameCompare != 0) {
            return displayNameCompare;
          }

          return a.id.toLowerCase().compareTo(b.id.toLowerCase());
        });

      for (final user in participants) {
        final roomDisplayName = user.calcDisplayname(i18n: matrixLocals);
        final fallbackDisplayName =
            user.displayName ?? roomDisplayName;
        final resolvedDisplayName = resolveDisplayNameForMatrixUserId(
          room: room,
          matrixUserId: user.id,
          matrixLocals: matrixLocals,
        );
        final resolvedAvatar = AgentService.instance.resolveAvatarUriByMatrixUserId(
          user.id,
          fallbackAvatarUri: user.avatarUrl,
        );
        final mentionText = buildInputMentionByUser(room: room, user: user);
        final searchCandidates = <String>{
          resolvedDisplayName,
          fallbackDisplayName,
          roomDisplayName,
          user.displayName ?? '',
          user.id.split(':').first,
        };
        final matchesSearch = searchCandidates.any((candidate) {
          final normalizedCandidate = candidate.trim().toLowerCase();
          if (normalizedCandidate.isEmpty) {
            return false;
          }
          return normalizedCandidate.contains(userSearch) ||
              slugify(normalizedCandidate).contains(userSearch);
        });
        if (matchesSearch) {
          ret.add({
            'type': 'user',
            'mxid': user.id,
            'mention': mentionText,
            'displayname': resolvedDisplayName,
            'avatar_url': resolvedAvatar?.toString(),
          });
        }
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    final roomMatch = RegExp(r'(?:\s|^)#([-\w]+)$').firstMatch(searchText);
    if (roomMatch != null) {
      final roomSearch = roomMatch[1]!.toLowerCase();
      for (final r in room.client.rooms) {
        if (r.getState(EventTypes.RoomTombstone) != null) {
          continue; // we don't care about tombstoned rooms
        }
        final state = r.getState(EventTypes.RoomCanonicalAlias);
        if ((state != null &&
                ((state.content['alias'] is String &&
                        state.content
                            .tryGet<String>('alias')!
                            .split(':')[0]
                            .toLowerCase()
                            .contains(roomSearch)) ||
                    (state.content['alt_aliases'] is List &&
                        (state.content['alt_aliases'] as List).any(
                          (l) =>
                              l is String &&
                              l
                                  .split(':')[0]
                                  .toLowerCase()
                                  .contains(roomSearch),
                        )))) ||
            (r.name.toLowerCase().contains(roomSearch))) {
          ret.add({
            'type': 'room',
            'mxid': (r.canonicalAlias.isNotEmpty) ? r.canonicalAlias : r.id,
            'displayname': r.getLocalizedDisplayname(),
            'avatar_url': r.avatar?.toString(),
          });
        }
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    return ret;
  }

  Widget buildSuggestion(
    BuildContext context,
    Map<String, String?> suggestion,
    void Function(Map<String, String?>) onSelected,
    Client? client,
    bool highlighted,
  ) {
    final theme = Theme.of(context);
    final layout = _mentionAutocompleteLayout(context);
    const size = 30.0;
    if (suggestion['type'] == 'command') {
      final command = suggestion['name']!;
      final hint = commandHint(L10n.of(context), command);
      return _buildSuggestionTile(
        context: context,
        highlighted: highlighted,
        compact: layout.isCompact,
        mobileSheetStyle: layout.mobileSheetStyle,
        onTap: () => onSelected(suggestion),
        title: Text(
          commandExample(command),
          style: const TextStyle(fontFamily: 'RobotoMono'),
        ),
        subtitle: Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    if (suggestion['type'] == 'emoji') {
      final label = suggestion['label']!;
      return _buildSuggestionTile(
        context: context,
        highlighted: highlighted,
        compact: layout.isCompact,
        mobileSheetStyle: layout.mobileSheetStyle,
        onTap: () => onSelected(suggestion),
        leading: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              suggestion['emoji']!,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    if (suggestion['type'] == 'emote') {
      return _buildSuggestionTile(
        context: context,
        highlighted: highlighted,
        compact: layout.isCompact,
        mobileSheetStyle: layout.mobileSheetStyle,
        onTap: () => onSelected(suggestion),
        leading: MxcImage(
          // ensure proper ordering ...
          key: ValueKey(suggestion['name']),
          uri: suggestion['mxc'] is String
              ? Uri.parse(suggestion['mxc'] ?? '')
              : null,
          width: size,
          height: size,
          isThumbnail: false,
        ),
        title: Text(
          suggestion['name']!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: layout.showSubtitle
            ? Text(
                suggestion['pack_display_name']!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              )
            : null,
        trailing: Opacity(
          opacity: suggestion['pack_avatar_url'] != null ? 0.8 : 0.5,
          child: suggestion['pack_avatar_url'] != null
              ? Avatar(
                  mxContent: Uri.tryParse(
                    suggestion.tryGet<String>('pack_avatar_url') ?? '',
                  ),
                  name: suggestion.tryGet<String>('pack_display_name'),
                  size: size * 0.9,
                  client: client,
                )
              : Text(
                  suggestion['pack_display_name']!,
                  style: theme.textTheme.bodySmall,
                ),
        ),
      );
    }
    if (suggestion['type'] == 'user' || suggestion['type'] == 'room') {
      final isRoomMention = suggestion['mxid'] == '@room';
      final url = Uri.tryParse(suggestion['avatar_url'] ?? '');
      return _buildSuggestionTile(
        context: context,
        highlighted: highlighted,
        compact: layout.isCompact,
        mobileSheetStyle: layout.mobileSheetStyle,
        onTap: () => onSelected(suggestion),
        leading: isRoomMention
            ? CircleAvatar(
                radius: size / 2,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.groups,
                  size: size * 0.6,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              )
            : Avatar(
                mxContent: url,
                name: suggestion.tryGet<String>('displayname') ??
                    suggestion.tryGet<String>('mxid'),
                size: size,
                client: client,
              ),
        title: Text(
          suggestion['displayname'] ?? suggestion['mxid']!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: isRoomMention || !layout.showSubtitle
            ? null
            : Text(
                suggestion['mxid']!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSuggestionTile({
    required BuildContext context,
    required bool highlighted,
    required bool compact,
    required bool mobileSheetStyle,
    required VoidCallback onTap,
    required Widget title,
    Widget? leading,
    Widget? subtitle,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final backgroundColor = highlighted
        ? theme.colorScheme.primaryContainer.withValues(
            alpha: mobileSheetStyle ? 0.78 : 0.55,
          )
        : Colors.transparent;

    return AnimatedContainer(
      duration: Duration(milliseconds: mobileSheetStyle ? 90 : 120),
      curve: Curves.easeOutCubic,
      color: backgroundColor,
      child: ListTile(
        onTap: onTap,
        dense: !compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: mobileSheetStyle ? 16 : 14,
          vertical: mobileSheetStyle ? 6 : 4,
        ),
        horizontalTitleGap: 12,
        minVerticalPadding: mobileSheetStyle
            ? 8
            : compact
                ? 6
                : 4,
        leading: leading,
        title: DefaultTextStyle.merge(
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
          ),
          child: title,
        ),
        subtitle: subtitle,
        trailing: trailing ??
            (highlighted && PlatformInfos.isDesktop
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.08,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Enter',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  )
                : null),
      ),
    );
  }

  Widget _buildSuggestionsPanel({
    required BuildContext context,
    required List<Map<String, String?>> suggestions,
    required ValueChanged<Map<String, String?>> onSelected,
    ValueChanged<int?>? onHighlightedIndexChanged,
    int? highlightedIndex,
  }) {
    final theme = Theme.of(context);
    final overlayLayout = _mentionAutocompleteLayout(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        overlayLayout.horizontalInset,
        0,
        overlayLayout.horizontalInset,
        overlayLayout.verticalGap,
      ),
      child: Align(
        alignment: overlayLayout.mobileSheetStyle
            ? Alignment.bottomCenter
            : Alignment.bottomLeft,
        child: SizedBox(
          width: overlayLayout.maxWidth,
          child: Material(
            elevation: theme.appBarTheme.scrolledUnderElevation ?? 8,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.2),
            color: theme.colorScheme.surface,
            borderRadius: overlayLayout.mobileSheetStyle
                ? BorderRadius.vertical(
                    top: Radius.circular(overlayLayout.borderRadius),
                  )
                : BorderRadius.circular(overlayLayout.borderRadius),
            clipBehavior: Clip.antiAlias,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: overlayLayout.mobileSheetStyle
                    ? BorderRadius.vertical(
                        top: Radius.circular(overlayLayout.borderRadius),
                      )
                    : BorderRadius.circular(overlayLayout.borderRadius),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: overlayLayout.maxWidth,
                  maxHeight: overlayLayout.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overlayLayout.mobileSheetStyle) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Flexible(
                      child: _AutocompleteOptionsList(
                        suggestions: suggestions,
                        onSelected: onSelected,
                        showSeparators: overlayLayout.mobileSheetStyle,
                        onHighlightedIndexChanged: onHighlightedIndexChanged,
                        highlightedIndex: highlightedIndex,
                        suggestionBuilder: (
                          context,
                          suggestion,
                          onSelected,
                          client,
                          highlighted,
                        ) =>
                            buildSuggestion(
                          context,
                          suggestion,
                          onSelected,
                          client,
                          highlighted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String insertSuggestion(Map<String, String?> suggestion) {
    return _suggestionTextEditingValue(controller!.value, suggestion).text;
  }

  String _normalizedEveryoneMentionLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '@room';
    return trimmed.startsWith('@') ? trimmed : '@$trimmed';
  }

  _MentionAutocompleteLayout _mentionAutocompleteLayout(
    BuildContext context,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final availableHeight = size.height -
        mediaQuery.padding.vertical -
        mediaQuery.viewInsets.bottom;
    final shortestSide = size.shortestSide;
    final isTablet = !PlatformInfos.isDesktop && shortestSide >= 600;
    final isCompact =
        PlatformInfos.isMobile || (!PlatformInfos.isDesktop && !isTablet);
    final isMobileSheet = PlatformInfos.isMobile && !isTablet;

    final desiredMaxHeight = isCompact
        ? availableHeight * (isMobileSheet ? 0.52 : 0.34)
        : isTablet
            ? availableHeight * 0.38
            : availableHeight * 0.42;

    final maxHeight = desiredMaxHeight
        .clamp(
          220.0,
          isMobileSheet
              ? 520.0
              : isCompact
                  ? 320.0
                  : isTablet
                      ? 380.0
                      : 420.0,
        )
        .toDouble();

    final maxWidth = isMobileSheet
        ? size.width
        : isCompact
            ? size.width - 12
            : isTablet
                ? math.min(size.width * 0.72, 520.0)
                : 460.0;

    return _MentionAutocompleteLayout(
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      horizontalInset: isMobileSheet
          ? 0
          : isCompact
              ? 6
              : isTablet
                  ? 8
                  : 0,
      verticalGap: isMobileSheet
          ? 0
          : isCompact
              ? 6
              : 8,
      borderRadius: isMobileSheet
          ? 24
          : isCompact
              ? 18
              : 16,
      isCompact: isCompact,
      showSubtitle: !(isCompact || isMobileSheet),
      mobileSheetStyle: isMobileSheet,
    );
  }

  KeyEventResult _handleDesktopInputKeyEvent(
    KeyEvent event,
    TextEditingController textController,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final hasSuggestions = _desktopSuggestions.isNotEmpty &&
        _desktopSuggestionsOverlayController.isShowing;
    if (hasSuggestions) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _moveDesktopHighlightedSuggestion(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _moveDesktopHighlightedSuggestion(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.pageDown) {
        _moveDesktopHighlightedSuggestion(5);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.pageUp) {
        _moveDesktopHighlightedSuggestion(-5);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _applyDesktopSuggestions(const <Map<String, String?>>[]);
        return KeyEventResult.handled;
      }
    }

    final isPlainEnter =
        (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
            !HardwareKeyboard.instance.isShiftPressed &&
            !HardwareKeyboard.instance.isControlPressed &&
            !HardwareKeyboard.instance.isAltPressed &&
            !HardwareKeyboard.instance.isMetaPressed;
    if (!isPlainEnter) {
      return KeyEventResult.ignored;
    }

    if (PlatformInfos.isMacOS &&
        (macOsEnterImeGuard?.markSubmitToSkipIfComposing(
              textController.value,
            ) ??
            false)) {
      return KeyEventResult.ignored;
    }

    if (hasSuggestions && _commitDesktopHighlightedSuggestion()) {
      return KeyEventResult.handled;
    }

    if (!AppSettings.sendOnEnter.value) {
      return KeyEventResult.ignored;
    }

    final text = textController.text.trim();
    if (text.isNotEmpty) {
      onSubmitted?.call(text);
    }
    return KeyEventResult.handled;
  }

  Widget _buildInputTextField(
    BuildContext context, {
    required TextEditingController textController,
    required FocusNode effectiveFocusNode,
    bool Function()? commitSuggestion,
    KeyEventResult Function(KeyEvent event)? onDesktopKeyEvent,
  }) {
    final effectiveTextLengthLimit = _effectiveTextLengthLimit;
    final textField = TextField(
      controller: textController,
      focusNode: effectiveFocusNode,
      readOnly: readOnly,
      contextMenuBuilder: (c, e) => markdownContextBuilder(c, e, textController),
      contentInsertionConfiguration: ContentInsertionConfiguration(
        onContentInserted: (KeyboardInsertedContent content) {
          if (onContentInserted != null) {
            onContentInserted!(content);
            return;
          }
          final data = content.data;
          if (data == null) return;
          if (data.length > kChatAttachmentMaxUploadBytes) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  FileTooBigMatrixException(
                    data.length,
                    kChatAttachmentMaxUploadBytes,
                  ).toLocalizedString(context),
                ),
              ),
            );
            return;
          }

          if (onSubmitImage != null) {
            onSubmitImage!(data);
            return;
          }

          final file = MatrixFile(
            mimeType: content.mimeType,
            bytes: data,
            name: content.uri.split('/').last,
          );
          room.sendFileEvent(file, shrinkImageMaxDimension: 1600);
        },
      ),
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: keyboardType!,
      textInputAction: textInputAction,
      autofocus: autofocus!,
      onSubmitted: (text) {
        if (PlatformInfos.isDesktop && !PlatformInfos.isMacOS) {
          return;
        }
        if (PlatformInfos.isMacOS &&
            (macOsEnterImeGuard?.consumeSkippedSubmit() ?? false)) {
          return;
        }
        if (PlatformInfos.isDesktop &&
            commitSuggestion != null &&
            commitSuggestion()) {
          return;
        }
        onSubmitted?.call(text);
      },
      maxLength: effectiveTextLengthLimit,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      decoration: decoration,
      onChanged: (text) => onChanged?.call(text),
      textCapitalization: TextCapitalization.sentences,
    );

    if (!PlatformInfos.isDesktop || onDesktopKeyEvent == null) {
      return textField;
    }

    return Focus(
      onKeyEvent: (node, event) => onDesktopKeyEvent(event),
      child: textField,
    );
  }

  Widget _buildDesktopInput(BuildContext context) {
    final textController = controller;
    final effectiveFocusNode = focusNode;
    if (textController == null || effectiveFocusNode == null) {
      return const SizedBox.shrink();
    }

    return OverlayPortal(
      controller: _desktopSuggestionsOverlayController,
      overlayChildBuilder: (context) {
        if (_desktopSuggestions.isEmpty) {
          return const SizedBox.shrink();
        }
        final overlayLayout = _mentionAutocompleteLayout(context);
        return CompositedTransformFollower(
          link: _desktopSuggestionsFieldLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: Offset(0, -overlayLayout.verticalGap),
          child: _buildSuggestionsPanel(
            context: context,
            suggestions: _desktopSuggestions,
            onSelected: _selectDesktopSuggestion,
            onHighlightedIndexChanged: _setDesktopHighlightedSuggestion,
            highlightedIndex: _desktopHighlightedSuggestionIndex,
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _desktopSuggestionsFieldLink,
        child: _buildInputTextField(
          context,
          textController: textController,
          effectiveFocusNode: effectiveFocusNode,
          commitSuggestion: _commitDesktopHighlightedSuggestion,
          onDesktopKeyEvent: (event) =>
              _handleDesktopInputKeyEvent(event, textController),
        ),
      ),
    );
  }

  Widget _buildRawAutocompleteInput(BuildContext context) {
    final textController = controller;
    final effectiveFocusNode = focusNode;
    if (textController == null || effectiveFocusNode == null) {
      return const SizedBox.shrink();
    }

    final highlightedSuggestionIndex = ValueNotifier<int?>(null);
    return Autocomplete<Map<String, String?>>(
      key: ValueKey<int>(_mentionPresentationVersion),
      focusNode: effectiveFocusNode,
      textEditingController: textController,
      optionsBuilder: (text) => getSuggestions(text, context),
      fieldViewBuilder: (
        context,
        textController,
        _,
        __,
      ) {
        return _buildInputTextField(
          context,
          textController: textController,
          effectiveFocusNode: effectiveFocusNode,
          commitSuggestion: () => _commitHighlightedSuggestion(
            context: context,
            textController: textController,
            highlightedSuggestionIndex: highlightedSuggestionIndex,
          ),
          onDesktopKeyEvent: (event) {
            if (event is! KeyDownEvent || !AppSettings.sendOnEnter.value) {
              return KeyEventResult.ignored;
            }
            final isPlainEnter =
                (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey ==
                            LogicalKeyboardKey.numpadEnter) &&
                    !HardwareKeyboard.instance.isShiftPressed &&
                    !HardwareKeyboard.instance.isControlPressed &&
                    !HardwareKeyboard.instance.isAltPressed &&
                    !HardwareKeyboard.instance.isMetaPressed;
            if (!isPlainEnter) {
              return KeyEventResult.ignored;
            }
            if (PlatformInfos.isMacOS &&
                (macOsEnterImeGuard?.markSubmitToSkipIfComposing(
                      textController.value,
                    ) ??
                    false)) {
              return KeyEventResult.ignored;
            }
            if (_commitHighlightedSuggestion(
              context: context,
              textController: textController,
              highlightedSuggestionIndex: highlightedSuggestionIndex,
            )) {
              return KeyEventResult.handled;
            }
            final text = textController.text.trim();
            if (text.isNotEmpty) {
              onSubmitted?.call(text);
            }
            return KeyEventResult.handled;
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return _buildSuggestionsPanel(
          context: context,
          suggestions: options.toList(),
          onSelected: onSelected,
          onHighlightedIndexChanged: (index) {
            highlightedSuggestionIndex.value = index;
          },
        );
      },
      displayStringForOption: insertSuggestion,
      optionsViewOpenDirection: OptionsViewOpenDirection.up,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_usesCustomDesktopSuggestions) {
      return _buildDesktopInput(context);
    }
    return _buildRawAutocompleteInput(context);
  }
}

class _AutocompleteOptionsList extends StatefulWidget {
  final List<Map<String, String?>> suggestions;
  final AutocompleteOnSelected<Map<String, String?>> onSelected;
  final bool showSeparators;
  final ValueChanged<int?>? onHighlightedIndexChanged;
  final int? highlightedIndex;
  final Widget Function(
    BuildContext context,
    Map<String, String?> suggestion,
    AutocompleteOnSelected<Map<String, String?>> onSelected,
    Client? client,
    bool highlighted,
  ) suggestionBuilder;

  const _AutocompleteOptionsList({
    required this.suggestions,
    required this.onSelected,
    required this.showSeparators,
    this.onHighlightedIndexChanged,
    this.highlightedIndex,
    required this.suggestionBuilder,
  });

  @override
  State<_AutocompleteOptionsList> createState() =>
      _AutocompleteOptionsListState();
}

class _AutocompleteOptionsListState extends State<_AutocompleteOptionsList> {
  final GlobalKey _scrollViewportKey = GlobalKey();
  late final ScrollController _scrollController = ScrollController();
  int? _lastAutoScrolledHighlightedIndex;

  String _suggestionsSignature(List<Map<String, String?>> suggestions) =>
      suggestions
          .map(
            (suggestion) =>
                '${suggestion['type']}:${suggestion['mxid'] ?? suggestion['mention'] ?? suggestion['name'] ?? suggestion['emoji'] ?? suggestion['label'] ?? ''}',
          )
          .join('|');

  @override
  void didUpdateWidget(covariant _AutocompleteOptionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_suggestionsSignature(oldWidget.suggestions) !=
        _suggestionsSignature(widget.suggestions)) {
      _lastAutoScrolledHighlightedIndex = null;
      widget.onHighlightedIndexChanged?.call(null);
    }
  }

  void _scrollHighlightedIntoView(BuildContext itemContext) {
    if (!_scrollController.hasClients) return;
    final itemRenderObject = itemContext.findRenderObject();
    final viewportRenderObject = _scrollViewportKey.currentContext
        ?.findRenderObject();
    if (itemRenderObject is! RenderBox ||
        viewportRenderObject is! RenderBox ||
        !itemRenderObject.attached ||
        !viewportRenderObject.attached) {
      return;
    }

    const edgePadding = 8.0;
    final position = _scrollController.position;
    final itemTop = itemRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
    final itemBottom = itemTop + itemRenderObject.size.height;
    final visibleTop = edgePadding;
    final visibleBottom = viewportRenderObject.size.height - edgePadding;

    double? targetOffset;
    if (itemTop < visibleTop) {
      targetOffset = position.pixels + (itemTop - visibleTop);
    } else if (itemBottom > visibleBottom) {
      targetOffset = position.pixels + (itemBottom - visibleBottom);
    }

    if (targetOffset == null) {
      return;
    }

    final clampedTarget = math.max(
      position.minScrollExtent,
      math.min(position.maxScrollExtent, targetOffset),
    );
    if ((clampedTarget - position.pixels).abs() < 1) {
      return;
    }

    _scrollController.animateTo(
      clampedTarget,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showScrollbar = widget.suggestions.length > 4;

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: showScrollbar,
      interactive: true,
      radius: const Radius.circular(999),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: _scrollViewportKey,
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.suggestions.length, (index) {
                return Builder(
                  builder: (itemContext) {
                    final highlighted = widget.highlightedIndex != null
                        ? widget.highlightedIndex == index
                        : AutocompleteHighlightedOption.of(itemContext) ==
                            index;
                    if (highlighted &&
                        _lastAutoScrolledHighlightedIndex != index) {
                      _lastAutoScrolledHighlightedIndex = index;
                      widget.onHighlightedIndexChanged?.call(index);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!itemContext.mounted) return;
                        _scrollHighlightedIntoView(itemContext);
                      });
                    }

                    final child = widget.suggestionBuilder(
                      itemContext,
                      widget.suggestions[index],
                      widget.onSelected,
                      Matrix.of(itemContext).client,
                      highlighted,
                    );

                    if (!widget.showSeparators ||
                        index == widget.suggestions.length - 1) {
                      return child;
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        child,
                        Divider(
                          height: 1,
                          indent: 64,
                          endIndent: 16,
                          color: Theme.of(
                            itemContext,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ],
                    );
                  },
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _MentionAutocompleteLayout {
  final double maxHeight;
  final double maxWidth;
  final double horizontalInset;
  final double verticalGap;
  final double borderRadius;
  final bool isCompact;
  final bool showSubtitle;
  final bool mobileSheetStyle;

  const _MentionAutocompleteLayout({
    required this.maxHeight,
    required this.maxWidth,
    required this.horizontalInset,
    required this.verticalGap,
    required this.borderRadius,
    required this.isCompact,
    required this.showSubtitle,
    required this.mobileSheetStyle,
  });
}
