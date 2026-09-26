// Tuut – Version 0.5: Kontakte, verschlüsselter Chat, App-Anrufe, Anrufliste, Wählfeld, Guthaben. Windows + Android.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';

import 'database/tuut_database.dart';
import 'matrix_service.dart';
import 'screens/call_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Verschlüsselungsbibliothek (vodozemac) laden – muss vor dem Client passieren.
    await vod.init();
  } catch (e) {
    debugPrint('Verschlüsselung nicht verfügbar: $e');
  }
  final client = Client('Tuut', database: await openTuutDatabase());
  try {
    await client.init().timeout(const Duration(seconds: 10));
  } catch (_) {
    // Ohne gespeicherte Anmeldung erscheint der Login; bei Netzproblemen läuft der Sync im Hintergrund weiter.
  }
  runApp(TuutApp(service: MatrixService(client)));
}

class TuutApp extends StatefulWidget {
  final MatrixService service;
  const TuutApp({super.key, required this.service});

  @override
  State<TuutApp> createState() => _TuutAppState();
}

class _TuutAppState extends State<TuutApp> {
  StreamSubscription? _callSub;
  bool _callScreenOpen = false;

  @override
  void initState() {
    super.initState();
    // Eingehende und ausgehende Anrufe öffnen den Anrufbildschirm.
    _callSub = widget.service.calls.onCallChanged.stream.listen((session) {
      if (session == null || _callScreenOpen) return;
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      _callScreenOpen = true;
      nav.push(MaterialPageRoute(builder: (_) => CallScreen(session: session)))
          .whenComplete(() => _callScreenOpen = false);
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F6F5F); // Tuut-Grün
    final service = widget.service;
    return MaterialApp(
      navigatorKey: navigatorKey,
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
      home: service.isLoggedIn ? HomeShell(service: service) : LoginScreen(service: service),
    );
  }
}
