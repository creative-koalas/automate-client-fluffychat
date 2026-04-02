import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:psygo/utils/markdown_context_builder.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/mxc_image.dart';
import '../../widgets/avatar.dart';
import '../../widgets/matrix.dart';
import 'command_hints.dart';

class InputBar extends StatelessWidget {
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

  int get _effectiveTextLengthLimit {
    final configuredLimit = AppSettings.textMessageMaxLength.value;
    final pduLimit = (maxPDUSize / 3).floor();
    return configuredLimit < pduLimit ? configuredLimit : pduLimit;
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

  TextEditingValue _suggestionTextEditingValue(
    TextEditingValue value,
    Map<String, String?> suggestion,
  ) {
    final fullText = value.text;
    final rawOffset = value.selection.baseOffset;
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
    final suggestions = getSuggestions(textController.value, context);
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

  List<Map<String, String?>> getSuggestions(
    TextEditingValue text,
    BuildContext context,
  ) {
    if (text.selection.baseOffset != text.selection.extentOffset ||
        text.selection.baseOffset < 0) {
      return []; // no entries if there is selected text
    }
    final l10n = L10n.of(context);
    final mentionEveryone = _normalizedEveryoneMentionLabel(
      l10n.mentionEveryone,
    );
    final searchText = text.text.substring(0, text.selection.baseOffset);
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

          final displayNameA = AgentService.instance.resolveDisplayName(a);
          final displayNameB = AgentService.instance.resolveDisplayName(b);
          final displayNameCompare = displayNameA.toLowerCase().compareTo(
                displayNameB.toLowerCase(),
              );
          if (displayNameCompare != 0) {
            return displayNameCompare;
          }

          return a.id.toLowerCase().compareTo(b.id.toLowerCase());
        });

      for (final user in participants) {
        AgentService.instance.ensureMatrixProfilePresentation(user);
        final resolvedDisplayName = AgentService.instance.resolveDisplayName(
          user,
        );
        final resolvedAvatar = AgentService.instance.resolveAvatarUri(user);
        final mentionText = buildInputMentionByUser(room: room, user: user);
        if ((resolvedDisplayName.toLowerCase().contains(userSearch) ||
                slugify(
                  resolvedDisplayName.toLowerCase(),
                ).contains(userSearch)) ||
            user.id.split(':')[0].toLowerCase().contains(userSearch)) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overlayLayout = _mentionAutocompleteLayout(context);
    final highlightedSuggestionIndex = ValueNotifier<int?>(null);
    return Autocomplete<Map<String, String?>>(
      focusNode: focusNode,
      textEditingController: controller,
      optionsBuilder: (text) => getSuggestions(text, context),
      fieldViewBuilder:
          (context, textController, autocompleteFocusNode, onFieldSubmitted) {
        final effectiveTextLengthLimit = _effectiveTextLengthLimit;
        final textField = TextField(
          controller: textController,
          focusNode: focusNode ?? autocompleteFocusNode,
          readOnly: readOnly,
          contextMenuBuilder: (c, e) =>
              markdownContextBuilder(c, e, textController),
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
              // Desktop Enter handling is routed through keyboard events so
              // IME commit actions do not bypass the send-on-enter guard.
              return;
            }
            if (PlatformInfos.isMacOS &&
                (macOsEnterImeGuard?.consumeSkippedSubmit() ?? false)) {
              return;
            }
            if (PlatformInfos.isDesktop && AppSettings.sendOnEnter.value) {
              final committedSuggestion = _commitHighlightedSuggestion(
                context: context,
                textController: textController,
                highlightedSuggestionIndex: highlightedSuggestionIndex,
              );
              if (committedSuggestion) {
                return;
              }
            }
            // fix for library for now
            // it sets the types for the callback incorrectly
            onSubmitted!(text);
          },
          maxLength: effectiveTextLengthLimit,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: decoration,
          onChanged: (text) {
            // fix for the library for now
            // it sets the types for the callback incorrectly
            onChanged!(text);
          },
          textCapitalization: TextCapitalization.sentences,
        );

        // PC 端：按 Enter 先确认当前高亮候选，无候选时发送消息。
        // Shift+Enter 仍然保留为换行。
        if (PlatformInfos.isDesktop && AppSettings.sendOnEnter.value) {
          return Focus(
            onKeyEvent: (node, event) {
              final isPlainEnter =
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
                      !HardwareKeyboard.instance.isShiftPressed &&
                      !HardwareKeyboard.instance.isControlPressed &&
                      !HardwareKeyboard.instance.isAltPressed &&
                      !HardwareKeyboard.instance.isMetaPressed;
              if (event is KeyDownEvent && isPlainEnter) {
                if (PlatformInfos.isMacOS &&
                    (macOsEnterImeGuard?.markSubmitToSkipIfComposing(
                            textController.value) ??
                        false)) {
                  return KeyEventResult.ignored;
                }

                final committedSuggestion = _commitHighlightedSuggestion(
                  context: context,
                  textController: textController,
                  highlightedSuggestionIndex: highlightedSuggestionIndex,
                );
                if (committedSuggestion) {
                  return KeyEventResult.handled;
                }

                final text = textController.text.trim();
                if (text.isNotEmpty) {
                  onSubmitted?.call(text);
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: textField,
          );
        }
        return textField;
      },
      optionsViewBuilder: (c, onSelected, s) {
        final suggestions = s.toList();
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
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.35),
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
                            onHighlightedIndexChanged: (index) {
                              highlightedSuggestionIndex.value = index;
                            },
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
      },
      displayStringForOption: insertSuggestion,
      optionsViewOpenDirection: OptionsViewOpenDirection.up,
    );
  }
}

class _AutocompleteOptionsList extends StatefulWidget {
  final List<Map<String, String?>> suggestions;
  final AutocompleteOnSelected<Map<String, String?>> onSelected;
  final bool showSeparators;
  final ValueChanged<int?>? onHighlightedIndexChanged;
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
    required this.suggestionBuilder,
  });

  @override
  State<_AutocompleteOptionsList> createState() =>
      _AutocompleteOptionsListState();
}

class _AutocompleteOptionsListState extends State<_AutocompleteOptionsList> {
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
    final renderObject = itemContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) return;

    final viewport = RenderAbstractViewport.of(renderObject);

    final position = _scrollController.position;
    final leading = viewport.getOffsetToReveal(renderObject, 0).offset - 8;
    final trailing = viewport.getOffsetToReveal(renderObject, 1).offset + 8;

    double? targetOffset;
    if (leading < position.pixels) {
      targetOffset = math.max(position.minScrollExtent, leading);
    } else if (trailing > position.pixels + position.viewportDimension) {
      targetOffset = math.min(
        position.maxScrollExtent,
        trailing - position.viewportDimension,
      );
    }

    if (targetOffset == null || (targetOffset - position.pixels).abs() < 1) {
      return;
    }

    _scrollController.animateTo(
      targetOffset,
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
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: widget.suggestions.length,
        itemBuilder: (context, index) => Builder(
          builder: (itemContext) {
            final highlighted =
                AutocompleteHighlightedOption.of(itemContext) == index;
            if (highlighted && _lastAutoScrolledHighlightedIndex != index) {
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
