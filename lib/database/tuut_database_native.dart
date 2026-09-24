import 'dart:io';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// Windows und Android: SQLite-Datei im App-Datenordner.
/// SQLite selbst wird beim Bauen automatisch mitgeliefert (Paket sqlite3 ab Version 3).
Future<MatrixSdkDatabase> openTuutDatabase() async {
  ffi.sqfliteFfiInit();
  final dir = await getApplicationSupportDirectory();
  final path = '${dir.path}${Platform.pathSeparator}tuut.sqlite';
  final db = await ffi.databaseFactoryFfi.openDatabase(path);
  return MatrixSdkDatabase.init(
    'tuut',
    database: db,
    sqfliteFactory: ffi.databaseFactoryFfi,
  );
}
