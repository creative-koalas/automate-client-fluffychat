import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:share_plus/share_plus.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/download_save_directory.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'package:psygo/utils/size_string.dart';

extension MatrixFileExtension on MatrixFile {
  void save(BuildContext context) async {
    debugPrint(
      '[DownloadFile] Save requested: '
      'platform=${Theme.of(context).platform.name}, '
      'name="$name", mimeType=$mimeType, size=$size, msgType=$msgType',
    );
    if (PlatformInfos.isIOS) {
      debugPrint(
        '[DownloadFile] iOS detected, using share sheet instead of save dialog: '
        'name="$name"',
      );
      await share(context);
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final initialDirectory = await getPreferredDownloadSaveDirectory();
    debugPrint(
      '[DownloadFile] Opening save dialog: '
      'name="$name", initialDirectory=$initialDirectory, '
      'fileType=$filePickerFileType, mimeType=$mimeType, size=$size',
    );
    try {
      final downloadPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.saveFile,
        fileName: name,
        initialDirectory: initialDirectory,
        type: filePickerFileType,
        bytes: bytes,
      );
      if (downloadPath == null) {
        debugPrint('[DownloadFile] Save dialog canceled: name="$name"');
        return;
      }

      debugPrint(
        '[DownloadFile] Save dialog completed: name="$name", path=$downloadPath',
      );

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.fileHasBeenSavedAt(downloadPath))),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[DownloadFile] Save dialog failed: name="$name", error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  FileType get filePickerFileType {
    if (this is MatrixImageFile) return FileType.image;
    if (this is MatrixAudioFile) return FileType.audio;
    if (this is MatrixVideoFile) return FileType.video;
    return FileType.any;
  }

  Future<void> share(BuildContext context) async {
    // Workaround for iPad from
    // https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus#ipad
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    debugPrint(
      '[DownloadFile] Opening share sheet: '
      'name="$name", mimeType=$mimeType, size=$size, hasOrigin=${shareOrigin != null}',
    );
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: name, mimeType: mimeType)],
          sharePositionOrigin: shareOrigin,
        ),
      );
      debugPrint(
        '[DownloadFile] Share sheet completed: '
        'name="$name", status=${result.status}, raw=$result',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[DownloadFile] Share sheet failed: name="$name", error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  MatrixFile get detectFileType {
    if (msgType == MessageTypes.Image) {
      return MatrixImageFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Video) {
      return MatrixVideoFile(bytes: bytes, name: name);
    }
    if (msgType == MessageTypes.Audio) {
      return MatrixAudioFile(bytes: bytes, name: name);
    }
    return this;
  }

  String get sizeString => size.sizeString;
}
