// Tuut – Anmelden oder Konto erstellen.
// PC: Server läuft auf demselben Rechner (localhost).
// Handy: Adresse des Laptops im WLAN eintragen (zeigt das Server-Fenster an).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../matrix_service.dart';
import 'contacts_screen.dart';

class LoginScreen extends StatefulWidget {
  final MatrixService service;
  const LoginScreen({super.key, required this.service});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static final bool _isPhone = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final _server = TextEditingController(text: _isPhone ? '' : 'http://localhost:8008');
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Ergänzt "http://" und den Standard-Port, falls der Nutzer nur die IP eintippt.
  String _normalizedServer() {
    var s = _server.text.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri != null && !uri.hasPort && uri.scheme == 'http') s = '$s:8008';
    return s;
  }

  Future<void> _run(Future<void> Function() action) async {
    final server = _normalizedServer();
    if (server.isEmpty) {
      setState(() => _error = 'Bitte die Serveradresse eintragen. Sie steht im Server-Fenster auf dem Laptop.');
      return;
    }
    if (_user.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Bitte Benutzername und Passwort eingeben.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.service.connect(server);
      await action();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ContactsScreen(service: widget.service)),
      );
    } catch (e) {
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _readable(Object e) {
    final text = e.toString();
    if (text.contains('M_FORBIDDEN')) return 'Benutzername oder Passwort ist falsch.';
    if (text.contains('M_USER_IN_USE')) return 'Dieser Benutzername ist schon vergeben.';
    if (text.contains('M_INVALID_USERNAME')) return 'Benutzername nur mit Kleinbuchstaben, Ziffern, Punkt oder Unterstrich.';
    if (text.contains('M_WEAK_PASSWORD')) return 'Das Passwort ist zu kurz oder zu einfach.';
    if (text.contains('SocketException') || text.contains('Failed host lookup') ||
        text.contains('ClientException') || text.contains('TimeoutException')) {
      return _isPhone
          ? 'Server nicht erreichbar. Läuft der Server auf dem Laptop, ist das Handy im selben WLAN und stimmt die Adresse?'
          : 'Server nicht erreichbar. Läuft das Server-Fenster (SERVER-START) auf diesem PC?';
    }
    return text.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, size: 64),
                    const SizedBox(height: 8),
                    Text('Tuut', textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _user,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Benutzername', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Passwort', border: OutlineInputBorder()),
                      onSubmitted: (_) => _busy ? null : _run(() => widget.service.login(_user.text, _password.text)),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      initiallyExpanded: _isPhone,
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Server'),
                      subtitle: Text(_isPhone ? 'Adresse aus dem Server-Fenster am Laptop' : 'Nur für Tests ändern'),
                      children: [
                        TextField(
                          controller: _server,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Serveradresse',
                            hintText: 'z. B. 192.168.178.20',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(() => widget.service.login(_user.text, _password.text)),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      child: _busy
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Anmelden', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _run(() => widget.service.register(_user.text, _password.text)),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      child: const Text('Neues Konto erstellen', style: TextStyle(fontSize: 18)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
