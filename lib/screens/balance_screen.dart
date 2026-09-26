// Tuut – Guthaben: Stand, Aufladen über Stripe, alle Buchungen nachvollziehbar.
// Gutgeschrieben wird erst, wenn Stripe die Zahlung bestätigt hat (prüft der Server).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../billing/billing_api.dart';
import '../matrix_service.dart';

class BalanceScreen extends StatefulWidget {
  final MatrixService service;
  final ValueNotifier<int> tab;
  final int myIndex;
  const BalanceScreen({super.key, required this.service, required this.tab, required this.myIndex});

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> with WidgetsBindingObserver {
  late final BillingApi _api = BillingApi(widget.service.client);
  Map<String, dynamic>? _status;
  List<dynamic> _entries = const [];
  String? _error;
  bool _loading = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (widget.tab.value == widget.myIndex) _refresh();
  }

  // Nach der Rückkehr aus dem Browser (Zahlung) automatisch aktualisieren.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.tab.value == widget.myIndex) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final s = await _api.getJson('/api/status');
      final j = await _api.getJson('/api/journal');
      if (!mounted) return;
      setState(() {
        _status = s;
        _entries = (j['eintraege'] as List?) ?? const [];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topup(int cents) async {
    setState(() => _paying = true);
    try {
      final r = await _api.postJson('/api/aufladen', {'betrag_cent': cents});
      final url = r['url'];
      if (url is! String) throw BillingException('Keine Zahlungsseite erhalten.');
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) throw BillingException('Browser konnte nicht geöffnet werden.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Zahlung im Browser abschließen. Danach hier auf „Aktualisieren“ tippen.'),
        duration: Duration(seconds: 6),
      ));
    } on BillingException catch (e) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aufladen nicht möglich'),
          content: Text(e.message),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _euro(int cents) => '${cents ~/ 100} €';

  String _date(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _status;
    final amounts = ((s?['aufladebetraege_cent'] as List?) ?? const [500, 1000, 2000, 5000]).whereType<int>().toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guthaben'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: scheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
              ),
            if (s == null && _error == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Tippe auf Aktualisieren.'))),
            if (s != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Text('Verfügbares Guthaben'),
                    const SizedBox(height: 6),
                    Text('${s['verfuegbar_text']}', style: Theme.of(context).textTheme.displaySmall),
                    if ((s['reserviert_cent'] as int? ?? 0) > 0)
                      Text('davon für laufendes Gespräch reserviert – Kontostand ${s['guthaben_text']}'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Text('Aufladen', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (s['stripe_aktiv'] != true)
                Card(
                  color: scheme.tertiaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Aufladen ist noch nicht eingerichtet: Auf dem Server fehlt der Stripe-Schlüssel '
                        '(Datei einstellungen.env, Zeile STRIPE_SECRET_KEY).'),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final c in amounts)
                      FilledButton.tonal(
                        onPressed: _paying ? null : () => _topup(c),
                        style: FilledButton.styleFrom(minimumSize: const Size(110, 56)),
                        child: Text(_euro(c), style: const TextStyle(fontSize: 18)),
                      ),
                  ],
                ),
              const SizedBox(height: 24),
              Text('Buchungen', style: Theme.of(context).textTheme.titleMedium),
              if (_entries.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Noch keine Buchungen.')),
              for (final e in _entries.whereType<Map>())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    (e['betrag_cent'] as int? ?? 0) >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    color: (e['betrag_cent'] as int? ?? 0) >= 0 ? Colors.green : scheme.error,
                  ),
                  title: Text('${e['text']}'),
                  subtitle: Text('${_date('${e['zeit']}')} · Saldo ${e['saldo_text']}'),
                  trailing: Text('${e['betrag_text']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
