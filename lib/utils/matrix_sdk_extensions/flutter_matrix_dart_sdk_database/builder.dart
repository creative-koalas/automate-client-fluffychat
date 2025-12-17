import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:universal_html/html.dart' as html;

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/client_manager.dart';
import 'package:psygo/utils/platform_infos.dart';
import 'cipher.dart';

import 'sqlcipher_stub.dart'
    if (dart.library.io) 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

Future<DatabaseApi> flutterMatrixSdkDatabaseBuilder(String clientName) async {
  developer.log('[Database] flutterMatrixSdkDatabaseBuilder called for: $clientName', name: 'Database');
  MatrixSdkDatabase? database;
  try {
    database = await _constructDatabase(clientName);
    developer.log('[Database] Database constructed, now opening...', name: 'Database');
    await database.open();
    developer.log('[Database] Database opened, builder complete!', name: 'Database');
    return database;
  } catch (e, s) {
    developer.log('[Database] FATAL: Unable to construct database! $e', name: 'Database', error: e, stackTrace: s);
    Logs().wtf('Unable to construct database!', e, s);

    try {
      // Send error notification:
      final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
      ClientManager.sendInitNotification(
        l10n.initAppError,
        e.toString(),
      );
    } catch (e, s) {
      Logs().e('Unable to send error notification', e, s);
    }

    // Try to delete database so that it can created again on next init:
    database?.delete().catchError(
          (e, s) => Logs().wtf(
            'Unable to delete database, after failed construction',
            e,
            s,
          ),
        );

    // Delete database file:
    if (!kIsWeb) {
      final dbFile = File(await _getDatabasePath(clientName));
      if (await dbFile.exists()) await dbFile.delete();
    }

    rethrow;
  }
}

Future<MatrixSdkDatabase> _constructDatabase(String clientName) async {
  developer.log('[Database] Starting database construction for $clientName', name: 'Database');

  if (kIsWeb) {
    html.window.navigator.storage?.persist();
    return await MatrixSdkDatabase.init(clientName);
  }

  final cipher = await getDatabaseCipher();

  Directory? fileStorageLocation;
  try {
    developer.log('[Database] Getting temporary directory...', name: 'Database');
    fileStorageLocation = await getTemporaryDirectory();
    developer.log('[Database] Temporary directory: ${fileStorageLocation.path}', name: 'Database');
  } on MissingPlatformDirectoryException catch (_) {
    developer.log('[Database] No temporary directory for file cache available on this platform.', name: 'Database');
    Logs().w(
      'No temporary directory for file cache available on this platform.',
    );
  }

  developer.log('[Database] Getting database path...', name: 'Database');
  final path = await _getDatabasePath(clientName);
  developer.log('[Database] Database path: $path', name: 'Database');

  // iOS FIX: Don't load SQLCipher library on iOS (not available in Release mode)
  // Android: Load SQLCipher for database encryption
  developer.log('[Database] Creating database factory...', name: 'Database');
  final factory = cipher != null
      ? createDatabaseFactoryFfi(ffiInit: SQfLiteEncryptionHelper.ffiInit)
      : createDatabaseFactoryFfi();
  developer.log('[Database] Database factory created', name: 'Database');

  // fix dlopen for old Android (only if using SQLCipher)
  if (cipher != null) {
    developer.log('[Database] Applying SQLCipher workaround for old Android...', name: 'Database');
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  }

  // required for [getDatabasesPath]
  databaseFactory = factory;

  // migrate from potential previous SQLite database path to current one
  developer.log('[Database] Checking for legacy database location...', name: 'Database');
  await _migrateLegacyLocation(path, clientName);
  developer.log('[Database] Legacy migration check complete', name: 'Database');

  // in case we got a cipher, we use the encryption helper
  // to manage SQLite encryption
  final helper = cipher != null
      ? SQfLiteEncryptionHelper(
          factory: factory,
          path: path,
          cipher: cipher,
        )
      : null;

  // check whether the DB is already encrypted and otherwise do so
  await helper?.ensureDatabaseFileEncrypted();

  developer.log('[Database] Opening database at: $path', name: 'Database');
  final database = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      // most important : apply encryption when opening the DB
      onConfigure: helper?.applyPragmaKey,
    ),
  );
  developer.log('[Database] Database opened successfully', name: 'Database');

  developer.log('[Database] Initializing MatrixSdkDatabase...', name: 'Database');
  Logs().i('[Database] Initializing MatrixSdkDatabase...');
  final matrixDb = await MatrixSdkDatabase.init(
    clientName,
    database: database,
    maxFileSize: 1000 * 1000 * 10,
    fileStorageLocation: fileStorageLocation?.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );
  developer.log('[Database] MatrixSdkDatabase initialized successfully', name: 'Database');
  Logs().i('[Database] MatrixSdkDatabase initialized successfully');
  return matrixDb;
}

Future<String> _getDatabasePath(String clientName) async {
  final databaseDirectory = PlatformInfos.isIOS || PlatformInfos.isMacOS
      ? await getLibraryDirectory()
      : await getApplicationSupportDirectory();

  return join(databaseDirectory.path, '$clientName.sqlite');
}

Future<void> _migrateLegacyLocation(
  String sqlFilePath,
  String clientName,
) async {
  final oldPath = PlatformInfos.isDesktop
      ? (await getApplicationSupportDirectory()).path
      : await getDatabasesPath();

  final oldFilePath = join(oldPath, clientName);
  if (oldFilePath == sqlFilePath) return;

  final maybeOldFile = File(oldFilePath);
  if (await maybeOldFile.exists()) {
    Logs().i(
      'Migrate legacy location for database from "$oldFilePath" to "$sqlFilePath"',
    );
    await maybeOldFile.copy(sqlFilePath);
    await maybeOldFile.delete();
  }
}
