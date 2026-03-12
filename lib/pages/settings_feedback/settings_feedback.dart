import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:psygo/backend/api_client.dart';
import 'package:psygo/config/themes.dart';
import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/file_selector.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/widgets/future_loading_dialog.dart';
import 'package:psygo/widgets/layouts/max_width_body.dart';

class SettingsFeedback extends StatefulWidget {
  const SettingsFeedback({super.key});

  @override
  State<SettingsFeedback> createState() => _SettingsFeedbackState();
}

class _SettingsFeedbackState extends State<SettingsFeedback> {
  static const int _maxAttachmentTotalBytes = 10 * 1024 * 1024;
  static const String _maxAttachmentTotalLabel = '10 MB';

  final _contentController = TextEditingController();
  final _emailController = TextEditingController();
  String _selectedCategory = 'suggestion';
  final List<XFile> _attachments = [];

  final _categories = const [
    ('bug', Icons.bug_report_outlined),
    ('suggestion', Icons.lightbulb_outlined),
    ('complaint', Icons.report_outlined),
    ('other', Icons.more_horiz),
  ];

  @override
  void dispose() {
    _contentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _categoryLabel(L10n l10n, String value) {
    switch (value) {
      case 'bug':
        return l10n.settingsFeedbackTypeBug;
      case 'suggestion':
        return l10n.settingsFeedbackTypeSuggestion;
      case 'complaint':
        return l10n.settingsFeedbackTypeComplaint;
      default:
        return l10n.settingsFeedbackTypeOther;
    }
  }

  String _fileName(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty) return name;

    final path = file.path.trim();
    if (path.isNotEmpty) {
      final segments = path.split(RegExp(r'[\\/]'));
      final last = segments.isNotEmpty ? segments.last.trim() : '';
      if (last.isNotEmpty) return last;
    }

    return 'attachment';
  }

  bool _isImageFile(XFile file) {
    final mimeType = file.mimeType;
    if (mimeType != null && mimeType.startsWith('image/')) return true;

    final lowerName = _fileName(file).toLowerCase();
    const imageExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.heic',
      '.svg',
      '.tiff',
      '.tif',
    ];
    return imageExtensions.any(lowerName.endsWith);
  }

  Future<int> _attachmentSize(XFile file) async {
    try {
      return await file.length();
    } catch (_) {
      try {
        return (await file.readAsBytes()).length;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<int> _totalAttachmentBytes(Iterable<XFile> files) async {
    final sizes = await Future.wait(files.map(_attachmentSize));
    return sizes.fold<int>(0, (sum, size) => sum + size);
  }

  Future<void> _pickAttachments(FileSelectorType type) async {
    final picked = await selectFiles(
      context,
      type: type,
      allowMultiple: true,
    );
    if (!mounted || picked.isEmpty) return;

    final currentKeys = _attachments
        .map((file) => '${file.path}::${file.name}')
        .toSet();

    final newAttachments = <XFile>[];
    for (final file in picked) {
      final key = '${file.path}::${file.name}';
      if (currentKeys.add(key)) {
        newAttachments.add(file);
      }
    }
    if (newAttachments.isEmpty) return;

    final totalBytes = await _totalAttachmentBytes([
      ..._attachments,
      ...newAttachments,
    ]);
    if (!mounted) return;
    if (totalBytes > _maxAttachmentTotalBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.of(context).fileIsTooBigForServer(_maxAttachmentTotalLabel),
          ),
        ),
      );
      return;
    }

    setState(() {
      _attachments.addAll(newAttachments);
    });
  }

  void _showAttachmentBottomSheet() {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 20),
              child: Text(
                l10n.pleaseChoose,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _FeedbackAttachmentItem(
              icon: Icons.image_outlined,
              iconColor: const Color(0xFF2196F3),
              iconBgColor: const Color(0xFFE3F2FD),
              title: l10n.sendImage,
              subtitle: l10n.openGallery,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAttachments(FileSelectorType.images);
              },
            ),
            const SizedBox(height: 12),
            _FeedbackAttachmentItem(
              icon: Icons.attach_file,
              iconColor: const Color(0xFF4CAF50),
              iconBgColor: const Color(0xFFE8F5E9),
              title: l10n.sendFile,
              subtitle: l10n.sendFile,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAttachments(FileSelectorType.any);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<String> _ensurePreviewPath(XFile file) async {
    final filePath = file.path.trim();
    if (filePath.isNotEmpty) return filePath;

    final bytes = await file.readAsBytes();
    final tempDir = await getTemporaryDirectory();
    final fileName = _fileName(file);
    final tempPath = path_lib.join(
      tempDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$fileName',
    );
    await File(tempPath).writeAsBytes(bytes, flush: true);
    return tempPath;
  }

  Future<void> _openAttachmentPreview(XFile file) async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (_isImageFile(file)) {
      await showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: FutureBuilder<Uint8List>(
                  future: file.readAsBytes(),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return const CircularProgressIndicator.adaptive();
                    }
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (PlatformInfos.isWeb) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.sendFileWebPreviewNotSupported)),
      );
      return;
    }

    final previewPath = await _ensurePreviewPath(file);
    try {
      final result = await OpenFile.open(previewPath);
      if (result.type != ResultType.done) {
        final message =
            result.message.isNotEmpty ? result.message : l10n.sendFileCannotOpen;
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.sendFileCannotOpen)),
      );
    }
  }

  Future<void> _submitFeedback() async {
    final l10n = L10n.of(context);
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsFeedbackContentRequired)),
      );
      return;
    }

    final totalBytes = await _totalAttachmentBytes(_attachments);
    if (!mounted) return;
    if (totalBytes > _maxAttachmentTotalBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.fileIsTooBigForServer(_maxAttachmentTotalLabel),
          ),
        ),
      );
      return;
    }

    String? appVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {}

    final deviceInfo = defaultTargetPlatform.name;
    final apiClient = context.read<PsygoApiClient>();

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => apiClient.submitFeedback(
        content: content,
        category: _selectedCategory,
        replyEmail: _emailController.text.trim(),
        appVersion: appVersion,
        deviceInfo: deviceInfo,
        attachments: _attachments,
      ),
    );

    if (!mounted || success.error != null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsFeedbackSubmitted)),
    );
    context.go('/rooms/settings');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsFeedbackTitle),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        leading: FluffyThemes.isColumnMode(context)
            ? null
            : BackButton(
                onPressed: () => context.go('/rooms/settings'),
              ),
      ),
      body: MaxWidthBody(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsFeedbackType,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories.map((cat) {
                  final value = cat.$1;
                  final icon = cat.$2;
                  final isSelected = _selectedCategory == value;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(_categoryLabel(l10n, value)),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _selectedCategory = value);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    l10n.settingsFeedbackContent,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l10n.sendFile,
                    onPressed: _showAttachmentBottomSheet,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.45),
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contentController,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: l10n.settingsFeedbackContentHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in _attachments)
                      InputChip(
                        avatar: Icon(
                          _isImageFile(attachment)
                              ? Icons.image_outlined
                              : Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            _fileName(attachment),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onDeleted: () =>
                            setState(() => _attachments.remove(attachment)),
                        onPressed: () => _openAttachmentPreview(attachment),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text(
                l10n.settingsFeedbackReplyEmailOptional,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: l10n.settingsFeedbackReplyEmailHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => context.go('/rooms/settings'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.cancel,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _submitFeedback,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.submit,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackAttachmentItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeedbackAttachmentItem({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
