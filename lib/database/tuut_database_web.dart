import 'package:matrix/matrix.dart';

/// Browser: Das Matrix-SDK speichert selbst in IndexedDB.
Future<MatrixSdkDatabase> openTuutDatabase() => MatrixSdkDatabase.init('tuut');
