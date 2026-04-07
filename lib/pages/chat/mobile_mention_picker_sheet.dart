import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/services/agent_service.dart';
import 'package:psygo/utils/matrix_input_mention.dart';
import 'package:psygo/widgets/avatar.dart';

Future<List<String>?> showMobileMentionPickerSheet({
  required BuildContext context,
  required Room room,
  required List<User> participants,
  String initialQuery = '',
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: _MobileMentionPickerSheet(
        room: room,
        participants: participants,
        initialQuery: initialQuery,
      ),
    ),
  );
}

class _MobileMentionPickerSheet extends StatefulWidget {
  final Room room;
  final List<User> participants;
  final String initialQuery;

  const _MobileMentionPickerSheet({
    required this.room,
    required this.participants,
    required this.initialQuery,
  });

  @override
  State<_MobileMentionPickerSheet> createState() =>
      _MobileMentionPickerSheetState();
}

class _MobileMentionPickerSheetState extends State<_MobileMentionPickerSheet> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.initialQuery,
  )..addListener(_handleSearchChanged);
  final FocusNode _searchFocusNode = FocusNode();
  bool _multiSelectEnabled = false;
  final Set<String> _selectedKeys = <String>{};

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchChanged() => setState(() {});

  void _toggleMultiSelect(bool enabled) {
    setState(() {
      _multiSelectEnabled = enabled;
      if (!enabled) {
        _selectedKeys.clear();
      }
    });
  }

  void _toggleCandidate(_MentionCandidate candidate) {
    setState(() {
      if (_selectedKeys.contains(candidate.key)) {
        _selectedKeys.remove(candidate.key);
      } else {
        _selectedKeys.add(candidate.key);
      }
    });
  }

  void _confirmSelection() {
    final mentions = _selectedMentions();
    if (mentions.isEmpty) {
      return;
    }
    Navigator.of(context).pop(mentions);
  }

  List<String> _selectedMentions() {
    final l10n = L10n.of(context);
    return _allCandidates(l10n)
        .where((candidate) => _selectedKeys.contains(candidate.key))
        .map((candidate) => candidate.mention)
        .toList();
  }

  String _multiSelectLabel(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    if (languageCode.startsWith('zh')) {
      return '多选';
    }
    return 'Multi';
  }

  List<_MentionCandidate> _allCandidates(L10n l10n) {
    final mentionEveryone = _normalizedEveryoneMentionLabel(
      l10n.mentionEveryone,
    );
    final candidates = <_MentionCandidate>[];
    candidates.add(
      _MentionCandidate(
        key: '@room',
        mention: mentionEveryone,
        title: mentionEveryone,
        isEveryone: true,
      ),
    );

    final sortedParticipants = widget.participants.toList()
      ..sort((a, b) {
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

    for (final user in sortedParticipants) {
      AgentService.instance.ensureMatrixProfilePresentation(user);
      final displayName = AgentService.instance.resolveDisplayName(user);
      final avatarUri = AgentService.instance.resolveAvatarUri(user);
      final mention = buildInputMentionByUser(room: widget.room, user: user);
      candidates.add(
        _MentionCandidate(
          key: user.id,
          mention: mention,
          title: displayName,
          subtitle: user.id,
          avatarUri: avatarUri,
        ),
      );
    }

    return candidates;
  }

  List<_MentionCandidate> _buildCandidates(L10n l10n) {
    final normalizedQuery = _searchController.text.trim().toLowerCase();
    final allCandidates = _allCandidates(l10n);
    if (normalizedQuery.isEmpty) {
      return allCandidates;
    }

    final everyoneAliases = <String>{
      '@room',
      '@all',
      '@everyone',
      '@所有人',
      '@所有',
      _normalizedEveryoneMentionLabel(l10n.mentionEveryone).toLowerCase(),
    };

    return allCandidates.where((candidate) {
      if (candidate.isEveryone) {
        return everyoneAliases.any((alias) => alias.contains(normalizedQuery));
      }

      final title = candidate.title.toLowerCase();
      final userId = (candidate.subtitle ?? '').toLowerCase();
      final userIdParts = userId.split(':');
      final localpart = userIdParts.isEmpty ? userId : userIdParts.first;
      return title.contains(normalizedQuery) ||
          slugify(title).contains(normalizedQuery) ||
          localpart.contains(normalizedQuery);
    }).toList();
  }

  String _normalizedEveryoneMentionLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '@room';
    return trimmed.startsWith('@') ? trimmed : '@$trimmed';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final candidates = _buildCandidates(l10n);

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                children: [
                  const SizedBox(width: 72),
                  Expanded(
                    child: Text(
                      l10n.mentionHintTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: _multiSelectEnabled
                        ? TextButton(
                            onPressed: () => _toggleMultiSelect(false),
                            child: Text(l10n.cancel),
                          )
                        : TextButton(
                            onPressed: () => _toggleMultiSelect(true),
                            child: Text(_multiSelectLabel(context)),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.secondaryContainer,
                  hintText: l10n.search,
                  prefixIcon: const Icon(Icons.search_outlined),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            Expanded(
              child: candidates.isEmpty
                  ? Center(
                      child: Text(
                        l10n.nothingFound,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: candidates.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        indent: 72,
                        endIndent: 16,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        final selected = _selectedKeys.contains(candidate.key);
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          leading: candidate.isEveryone
                              ? CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.groups_rounded,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : Avatar(
                                  mxContent: candidate.avatarUri,
                                  name: candidate.title,
                                  client: widget.room.client,
                                ),
                          title: Text(
                            candidate.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: candidate.subtitle == null
                              ? null
                              : Text(
                                  candidate.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: _multiSelectEnabled
                              ? Checkbox.adaptive(
                                  value: selected,
                                  onChanged: (_) => _toggleCandidate(candidate),
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            if (_multiSelectEnabled) {
                              _toggleCandidate(candidate);
                              return;
                            }
                            Navigator.of(context).pop([candidate.mention]);
                          },
                        );
                      },
                    ),
            ),
            if (_multiSelectEnabled)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _selectedKeys.isEmpty ? null : _confirmSelection,
                      child: Text(l10n.confirm),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MentionCandidate {
  final String key;
  final String mention;
  final String title;
  final String? subtitle;
  final Uri? avatarUri;
  final bool isEveryone;

  const _MentionCandidate({
    required this.key,
    required this.mention,
    required this.title,
    this.subtitle,
    this.avatarUri,
    this.isEveryone = false,
  });
}
