// Tuut – Kontaktliste. Große Bedienelemente, mobil zuerst.
// Antippen eines bestätigten Kontakts öffnet den Chat; Hörer-Symbol startet einen Sprachanruf.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import '../matrix_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class ContactsScreen extends StatefulWidget {
  final MatrixService service;
  const ContactsScreen({super.key, required this.service});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  StreamSubscription? _sync;

  @override
  void initState() {
    super.initState();
    // Bei jedem Sync vom Server die Liste neu zeichnen.
    _sync = widget.service.client.onSync.stream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _sync?.cancel(); super.dispose(); }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addContact() async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kontakt hinzufügen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tuut-ID',
            hintText: '@anna:tuut.local',
            helperText: 'Die ID bekommst du von der Person selbst.',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Anfrage senden')),
        ],
      ),
    );
    if (id == null || id.trim().isEmpty) return;
    try {
      await widget.service.addContact(id);
      _toast('Kontaktanfrage an $id gesendet.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _logout() async {
    await widget.service.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginScreen(service: widget.service)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.service.client.userID ?? '';
    final contacts = widget.service.contacts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontakte'),
        actions: [
          IconButton(tooltip: 'Abmelden', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Kontakt hinzufügen'),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Deine Tuut-ID'),
            subtitle: SelectableText(me),
          ),
          const Divider(height: 1),
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Noch keine Kontakte.\nTippe unten auf „Kontakt hinzufügen".',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 18),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: contacts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ContactTile(room: contacts[i], service: widget.service, toast: _toast),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Room room;
  final MatrixService service;
  final void Function(String) toast;
  const _ContactTile({required this.room, required this.service, required this.toast});

  @override
  Widget build(BuildContext context) {
    final name = room.getLocalizedDisplayname();
    final invited = room.membership == Membership.invite; // ich wurde eingeladen
    final waiting = !invited && room.summary.mJoinedMemberCount == 1; // ich warte auf Annahme
    final preview = room.lastEvent?.body;
    final subtitle = invited
        ? 'Möchte dich als Kontakt hinzufügen'
        : waiting
            ? 'Anfrage gesendet – wartet auf Annahme'
            : (preview == null || preview.isEmpty ? 'Noch keine Nachrichten – tippen zum Schreiben' : preview);
    return ListTile(
      minTileHeight: 72,
      leading: CircleAvatar(radius: 26, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
      title: Text(name, style: const TextStyle(fontSize: 18)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: invited
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChatScreen(room: room, service: service)),
              ),
      trailing: invited
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Ablehnen', icon: const Icon(Icons.close), onPressed: () async {
                await service.declineInvite(room); toast('Anfrage abgelehnt.');
              }),
              FilledButton(onPressed: () async {
                await service.acceptInvite(room); toast('Kontakt angenommen.');
              }, child: const Text('Annehmen')),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Sprachanruf',
                iconSize: 28,
                icon: Icon(Icons.call, color: waiting ? null : Colors.green),
                onPressed: waiting
                    ? null
                    : () async {
                        try {
                          await service.calls.startVoiceCall(room);
                        } catch (e) {
                          toast('Anruf nicht möglich: ${e.toString().replaceFirst('Exception: ', '')}');
                        }
                      },
              ),
              IconButton(
                tooltip: 'Chat öffnen',
                iconSize: 28,
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatScreen(room: room, service: service)),
                ),
              ),
            ]),
    );
  }
}
