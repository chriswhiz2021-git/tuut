// Tuut – Anrufliste: App-Anrufe (aus den Kontodaten) und Festnetzgespräche (vom Guthaben-Dienst).
import 'dart:async';

import 'package:flutter/material.dart';
import '../billing/billing_api.dart';
import '../matrix_service.dart';

class CallLogScreen extends StatefulWidget {
  final MatrixService service;
  final ValueNotifier<int> tab;
  final int myIndex;
  const CallLogScreen({super.key, required this.service, required this.tab, required this.myIndex});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _Item {
  final DateTime time;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? color;
  final String? roomId;
  _Item(this.time, this.title, this.subtitle, this.icon, this.color, this.roomId);
}

class _CallLogScreenState extends State<CallLogScreen> {
  late final BillingApi _api = BillingApi(widget.service.client);
  StreamSubscription? _sync;
  List<dynamic> _pstn = const [];
  String? _pstnError;

  @override
  void initState() {
    super.initState();
    _sync = widget.service.client.onSync.stream.listen((_) { if (mounted) setState(() {}); });
    widget.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    _sync?.cancel();
    widget.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (widget.tab.value == widget.myIndex) _loadPstn();
  }

  Future<void> _loadPstn() async {
    try {
      final r = await _api.getJson('/api/gespraeche');
      if (mounted) setState(() { _pstn = (r['gespraeche'] as List?) ?? const []; _pstnError = null; });
    } catch (e) {
      if (mounted) setState(() => _pstnError = e.toString());
    }
  }

  String _dur(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} Min';

  String _date(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}. ${two(l.hour)}:${two(l.minute)}';
  }

  List<_Item> _items() {
    final out = <_Item>[];
    for (final e in widget.service.calls.callLog) {
      final t = DateTime.tryParse('${e['zeit']}');
      if (t == null) continue;
      final ergebnis = '${e['ergebnis']}';
      final out1 = e['richtung'] == 'aus';
      final missed = ergebnis == 'verpasst';
      out.add(_Item(
        t,
        '${e['name']}',
        'App-Anruf · ${_date(t)} · ${ergebnis == 'verbunden' ? _dur((e['dauer'] as int?) ?? 0) : ergebnis}',
        missed ? Icons.call_missed : (out1 ? Icons.call_made : Icons.call_received),
        missed ? Colors.red : null,
        e['raum'] as String?,
      ));
    }
    for (final g in _pstn.whereType<Map>()) {
      final t = DateTime.tryParse('${g['zeit']}');
      if (t == null) continue;
      out.add(_Item(
        t,
        '${g['nummer']}',
        'Festnetz · ${_date(t)} · ${_dur((g['sekunden'] as int?) ?? 0)} · ${g['kosten_text']}',
        Icons.phone_forwarded,
        null,
        null,
      ));
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  Future<void> _callBack(String roomId) async {
    final room = widget.service.client.getRoomById(roomId);
    if (room == null) return;
    try {
      await widget.service.calls.startVoiceCall(room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Anruf nicht möglich: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return Scaffold(
      appBar: AppBar(title: const Text('Anrufe')),
      body: items.isEmpty && _pstnError == null
          ? const Center(child: Text('Noch keine Anrufe.', style: TextStyle(fontSize: 18)))
          : ListView(
              children: [
                if (_pstnError != null)
                  ListTile(leading: const Icon(Icons.cloud_off), title: Text(_pstnError!)),
                for (final it in items)
                  ListTile(
                    minTileHeight: 64,
                    leading: Icon(it.icon, color: it.color),
                    title: Text(it.title, style: const TextStyle(fontSize: 17)),
                    subtitle: Text(it.subtitle),
                    trailing: it.roomId == null
                        ? null
                        : IconButton(
                            tooltip: 'Zurückrufen',
                            icon: const Icon(Icons.call, color: Colors.green),
                            onPressed: () => _callBack(it.roomId!),
                          ),
                  ),
              ],
            ),
    );
  }
}
