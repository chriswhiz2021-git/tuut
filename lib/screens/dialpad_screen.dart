// Tuut – Wählfeld für Anrufe ins Telefonnetz.
// Zeigt vor dem Anruf Preis, Takt, Verbindungsgebühr und wie lange das Guthaben reicht.
// Preise und Guthaben prüft ausschließlich der Server.
import 'dart:async';

import 'package:flutter/material.dart';
import '../billing/billing_api.dart';
import '../matrix_service.dart';

class DialpadScreen extends StatefulWidget {
  final MatrixService service;
  final ValueNotifier<int> tab;
  final int myIndex;
  final VoidCallback onOpenBalance;
  const DialpadScreen({super.key, required this.service, required this.tab, required this.myIndex, required this.onOpenBalance});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  late final BillingApi _api = BillingApi(widget.service.client);
  final _number = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic>? _status;
  String? _statusError;
  Map<String, dynamic>? _rate;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _number.addListener(_onNumberChanged);
    widget.tab.addListener(_onTab);
    _loadStatus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.tab.removeListener(_onTab);
    _number.dispose();
    super.dispose();
  }

  void _onTab() {
    if (widget.tab.value == widget.myIndex) _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await _api.getJson('/api/status');
      if (mounted) setState(() { _status = s; _statusError = null; });
    } catch (e) {
      if (mounted) setState(() => _statusError = e.toString());
    }
  }

  void _onNumberChanged() {
    if (mounted) setState(() {}); // Anruf-Knopf aktivieren/deaktivieren
    _debounce?.cancel();
    final text = _number.text.trim();
    if (text.length < 3) {
      if (_rate != null) setState(() => _rate = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await _api.getJson('/api/tarif', {'nummer': text});
        if (mounted && _number.text.trim() == text) setState(() => _rate = r);
      } catch (e) {
        if (mounted) setState(() => _rate = {'erlaubt': false, 'grund': e.toString()});
      }
    });
  }

  void _press(String c) {
    _number.text = _number.text + c;
    _number.selection = TextSelection.collapsed(offset: _number.text.length);
  }

  void _backspace() {
    final t = _number.text;
    if (t.isEmpty) return;
    _number.text = t.substring(0, t.length - 1);
    _number.selection = TextSelection.collapsed(offset: _number.text.length);
  }

  Future<void> _call() async {
    final number = _number.text.trim();
    if (number.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await _api.postJson('/api/gespraech/start', {'nummer': number});
      // Diese App-Version enthält noch keinen Telefonie-Anbieter: Reservierung sofort wieder freigeben.
      final id = r['gespraech_id'];
      if (id is String) await _api.postJson('/api/gespraech/$id/ende');
      _showMessage('Festnetz', 'Diese App-Version kann noch keine Festnetzgespräche aufbauen. Es wurde nichts abgebucht.');
    } on BillingException catch (e) {
      _showMessage('Anruf nicht möglich', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String title, String text) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text, style: const TextStyle(fontSize: 16)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final telefonieAktiv = status?['telefonie_aktiv'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wählfeld'),
        actions: [
          TextButton.icon(
            onPressed: widget.onOpenBalance,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(status == null ? 'Guthaben' : 'Guthaben: ${status['verfuegbar_text']}'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_statusError != null)
                  _Notice(color: scheme.errorContainer, icon: Icons.cloud_off, text: _statusError!),
                if (status != null && !telefonieAktiv)
                  _Notice(
                    color: scheme.tertiaryContainer,
                    icon: Icons.info_outline,
                    text: (status['telefonie_hinweis'] as String?) ?? 'Festnetz ist noch nicht freigeschaltet.',
                  ),
                TextField(
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, letterSpacing: 1),
                  decoration: const InputDecoration(hintText: 'Nummer mit Vorwahl', border: InputBorder.none),
                  onSubmitted: (_) => _call(),
                ),
                const SizedBox(height: 4),
                _RateInfo(rate: _rate),
                const SizedBox(height: 12),
                _Keypad(onKey: _press, onPlus: () => _press('+')),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 64),
                    const Spacer(),
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: FilledButton(
                        onPressed: _busy || _number.text.trim().isEmpty ? null : _call,
                        style: FilledButton.styleFrom(backgroundColor: Colors.green, shape: const CircleBorder(), padding: EdgeInsets.zero),
                        child: _busy
                            ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.call, size: 36, color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 64,
                      child: IconButton(
                        tooltip: 'Löschen',
                        iconSize: 30,
                        onPressed: _backspace,
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Kein Notruf über Tuut. Im Notfall 112 über das normale Telefon wählen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gespräche ins Telefonnetz sind nicht Ende-zu-Ende-verschlüsselt.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ]),
      ),
    );
  }
}

class _RateInfo extends StatelessWidget {
  final Map<String, dynamic>? rate;
  const _RateInfo({required this.rate});

  @override
  Widget build(BuildContext context) {
    final r = rate;
    if (r == null) {
      return const SizedBox(height: 44, child: Center(child: Text('Preis erscheint beim Eintippen der Nummer')));
    }
    if (r['erlaubt'] != true) {
      return SizedBox(
        height: 44,
        child: Center(
          child: Text(
            (r['grund'] as String?) ?? 'Ziel nicht erreichbar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    final minuten = r['max_minuten'];
    return SizedBox(
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${r['ziel']} · ${r['preis_text']} · Takt ${r['takt_text']}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Verbindungsgebühr: ${r['verbindungsgebuehr_text']} · Guthaben reicht für ca. $minuten Min.'),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onKey;
  final VoidCallback onPlus;
  const _Keypad({required this.onKey, required this.onPlus});

  static const _keys = [
    ('1', ''), ('2', 'ABC'), ('3', 'DEF'),
    ('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO'),
    ('7', 'PQRS'), ('8', 'TUV'), ('9', 'WXYZ'),
    ('*', ''), ('0', '+'), ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        for (final k in _keys)
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onKey(k.$1),
              onLongPress: k.$1 == '0' ? onPlus : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(k.$1, style: const TextStyle(fontSize: 28)),
                  if (k.$2.isNotEmpty) Text(k.$2, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
