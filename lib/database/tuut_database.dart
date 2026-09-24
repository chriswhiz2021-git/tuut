// Wählt beim Bauen automatisch den passenden Speicher:
// Windows/Android (und später iOS/macOS/Linux) -> SQLite-Datei, Browser -> IndexedDB.
export 'tuut_database_web.dart' if (dart.library.ffi) 'tuut_database_native.dart';
