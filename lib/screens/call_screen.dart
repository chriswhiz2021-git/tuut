// Tuut – Anrufbildschirm: Annehmen/Ablehnen, Stummschalten, Auflegen, Gesprächsdauer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class CallScreen extends StatefulWidget {
  final CallSession session;
  const CallScreen({super.key, required this.session});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription? _stateSub;
  Timer? _ticker;
  DateTime? _connectedAt;
  bool _closing = false;

  CallSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _stateSub = s.onCallStateChanged.stream.listen(_onState);
    _onState(s.state);
  }

  void _onState(CallState state) {
    if (!mounted) return;
    if (state == CallState.kConnected && _connectedAt == null) {
      _connectedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    }
    if ((state == CallState.kEnded || s.callHasEnded) && !_closing) {
      _closing = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  bool get _ended => s.callHasEnded || s.state == CallState.kEnded;
  bool get _connected => s.state == CallState.kConnected;
  bool get _incomingUnanswered => !s.isOutgoing && !s.answeredByUs && !_connected && !_ended;

  String get _status {
    if (_ended) return 'Anruf beendet';
    if (_connected) {
      final d = DateTime.now().difference(_connectedAt ?? DateTime.now());
      final m = d.inMinutes.toString().padLeft(2, '0');
      final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
      return 'Verbunden · $m:$sec';
    }
    if (_incomingUnanswered) return 'Eingehender Sprachanruf';
    return s.isOutgoing ? 'Ruft an …' : 'Verbindung wird aufgebaut …';
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = s.remoteUser?.calcDisplayname() ?? s.room.getLocalizedDisplayname();
    return PopScope(
      canPop: _ended,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerHighest,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(radius: 56, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 44))),
              const SizedBox(height: 24),
              Text(name, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_status, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                s.room.encrypted ? 'Anruf ist verschlüsselt (WebRTC-DTLS/SRTP)' : 'Anruf über WebRTC (DTLS/SRTP)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: _incomingUnanswered
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundButton(
                            icon: Icons.call_end, label: 'Ablehnen', color: Colors.red,
                            onTap: () => _run(() => s.reject()),
                          ),
                          _RoundButton(
                            icon: Icons.call, label: 'Annehmen', color: Colors.green,
                            onTap: () => _run(() => s.answer()),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundButton(
                            icon: s.isMicrophoneMuted ? Icons.mic_off : Icons.mic,
                            label: s.isMicrophoneMuted ? 'Stumm' : 'Mikrofon',
                            color: s.isMicrophoneMuted ? Colors.orange : scheme.primary,
                            onTap: _ended ? null : () => _run(() => s.setMicrophoneMuted(!s.isMicrophoneMuted)),
                          ),
                          _RoundButton(
                            icon: Icons.call_end, label: 'Auflegen', color: Colors.red,
                            onTap: _ended ? null : () => _run(() => s.hangup(reason: CallErrorCode.userHangup)),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76, height: 76,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(backgroundColor: color, shape: const CircleBorder(), padding: EdgeInsets.zero),
            child: Icon(icon, size: 34, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 16)),
      ],
    );
  }
}
