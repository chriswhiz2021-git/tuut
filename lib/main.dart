// Tuut – Version 0.2: echte App für Windows und Android (ein gemeinsamer Code).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:matrix/matrix.dart';
import 'database/tuut_database.dart';
import 'matrix_service.dart';
import 'screens/contacts_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = Client('Tuut', database: await openTuutDatabase());
  try {
    // Stellt eine gespeicherte Anmeldung wieder her. Höchstens 10 Sekunden warten,
    // damit die App bei nicht erreichbarem Server nicht hängen bleibt.
    await client.init().timeout(const Duration(seconds: 10));
  } catch (_) {
    // Kein Abbruch: Ohne Anmeldung erscheint der Login, sonst die Kontaktliste.
  }
  runApp(TuutApp(service: MatrixService(client)));
}

class TuutApp extends StatelessWidget {
  final MatrixService service;
  const TuutApp({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F6F5F); // Tuut-Grün
    return MaterialApp(
      title: 'Tuut',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      themeMode: ThemeMode.system,
      home: service.isLoggedIn ? ContactsScreen(service: service) : LoginScreen(service: service),
    );
  }
}
