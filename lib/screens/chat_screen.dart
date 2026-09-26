// Tuut – Einzelchat mit einem Kontakt.
// Aufbau nach dem offiziellen Beispiel des Matrix-SDK (Timeline + sendTextEvent).
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../matrix_service.dart';

class ChatScreen extends StatefulWidget {
  final Room room;
  final MatrixService service;
  const ChatScreen({super.key, required this.room, required this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Timeline? _timeline;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    // onUpdate feuert bei jeder Änderung – wir zeichnen dann einfach neu.
    widget.room
        .getTimeline(onUpdate: () { if (mounted) setState(() {}); })
        .then((t) { if (mounted) setState(() => _timeline = t); });
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _focus.requestFocus();
    try {
      await widget.room.sendTextEvent(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Senden fehlgeschlagen: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _call() async {
    try {
      await widget.service.calls.startVoiceCall(widget.room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Anruf nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
  }

  Future<void> _enableEncryption() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verschlüsselung einschalten?'),
        content: const Text('Ab dann sind alle Nachrichten in diesem Chat Ende-zu-Ende-verschlüsselt. '
            'Das lässt sich nicht mehr zurücknehmen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Einschalten')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.enableEncryption(widget.room);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehlgeschlagen: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder() async {
    final t = _timeline;
    if (t == null || _loadingHistory) return;
    setState(() => _loadingHistory = true);
    try {
      await t.requestHistory();
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    final myId = widget.room.client.userID;
    final messages = timeline?.events.where((e) => e.type == EventTypes.Message).toList() ?? [];
    final waiting = widget.room.summary.mJoinedMemberCount == 1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.room.getLocalizedDisplayname(), style: const TextStyle(fontSize: 18)),
            Text(
              widget.room.encrypted
                  ? 'Ende-zu-Ende-verschlüsselt'
                  : widget.service.encryptionAvailable
                      ? 'Unverschlüsselt – Schloss antippen zum Einschalten'
                      : 'Unverschlüsselt – Verschlüsselung auf diesem Gerät nicht verfügbar',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (!widget.room.encrypted && widget.service.encryptionAvailable)
            IconButton(
              tooltip: 'Verschlüsselung einschalten',
              icon: const Icon(Icons.lock_open),
              onPressed: _enableEncryption,
            ),
          if (widget.room.encrypted)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.lock, size: 20)),
          IconButton(
            tooltip: 'Sprachanruf',
            iconSize: 28,
            icon: const Icon(Icons.call),
            onPressed: waiting ? null : _call,
          ),
        ],
      ),
      body: timeline == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (waiting)
                  MaterialBanner(
                    content: const Text('Dein Kontakt hat die Anfrage noch nicht angenommen. Nachrichten werden zugestellt, sobald er sie annimmt.'),
                    actions: const [SizedBox.shrink()],
                  ),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text('Noch keine Nachrichten.\nSchreib die erste!', textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: messages.length + (timeline.canRequestHistory ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == messages.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: _loadingHistory ? null : _loadOlder,
                                  child: Text(_loadingHistory ? 'Lade …' : 'Ältere Nachrichten laden'),
                                ),
                              );
                            }
                            return _Bubble(event: messages[i], mine: messages[i].senderId == myId);
                          },
                        ),
                ),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: 'Nachricht schreiben …',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Senden',
                          iconSize: 28,
                          onPressed: _send,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Event event;
  final bool mine;
  const _Bubble({required this.event, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(event.originServerTs).format(context);
    final sent = event.status.isSent;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: sent ? 1 : 0.6,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(event.body, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                sent ? time : '$time · wird gesendet',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
