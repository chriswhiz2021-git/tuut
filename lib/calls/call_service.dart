// Tuut – Sprachanrufe zwischen App-Nutzern (WebRTC über Matrix-Signalisierung).
// Die Verbindung selbst stellt das Matrix-SDK her; diese Klasse liefert ihm nur
// die WebRTC-Bausteine des Geräts (flutter_webrtc) und meldet neue Anrufe an die Oberfläche.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc_impl;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

class TuutCallService implements WebRTCDelegate {
  final Client client;
  late final VoIP voip;

  /// Der gerade laufende Anruf (eingehend oder ausgehend), sonst null.
  CallSession? currentCall;

  /// Meldet der Oberfläche einen neuen Anruf (Session) oder das Ende (null).
  final StreamController<CallSession?> onCallChanged = StreamController.broadcast();

  /// Anrufliste der App-Anrufe: gespeichert in den Kontodaten beim Matrix-Server,
  /// dadurch auf allen Geräten gleich und ohne eigene Datenbank.
  static const callLogType = 'de.tuut.anrufliste';

  final Map<String, DateTime> _connectedAt = {};
  final Map<String, StreamSubscription> _subs = {};
  final Set<String> _logged = {};

  TuutCallService(this.client) {
    voip = VoIP(client, this);
  }

  /// Sprachanruf zu einem Kontakt starten.
  Future<CallSession> startVoiceCall(Room room) async {
    final session = await voip.inviteToCall(room, CallType.kVoice);
    currentCall = session;
    _track(session);
    onCallChanged.add(session);
    return session;
  }

  void _track(CallSession s) {
    if (_subs.containsKey(s.callId)) return;
    _subs[s.callId] = s.onCallStateChanged.stream.listen((state) {
      if (state == CallState.kConnected) _connectedAt.putIfAbsent(s.callId, () => DateTime.now());
    });
  }

  List<Map<String, Object?>> get callLog {
    final raw = client.accountData[callLogType]?.content['eintraege'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<void> _log(CallSession s) async {
    if (!_logged.add(s.callId)) return;
    _subs.remove(s.callId)?.cancel();
    final started = _connectedAt.remove(s.callId);
    final dauer = started == null ? 0 : DateTime.now().difference(started).inSeconds;
    final ergebnis = started != null ? 'verbunden' : (s.isOutgoing ? 'nicht angenommen' : 'verpasst');
    final uid = client.userID;
    if (uid == null) return;
    final entry = <String, Object?>{
      'zeit': DateTime.now().toUtc().toIso8601String(),
      'name': s.remoteUser?.calcDisplayname() ?? s.room.getLocalizedDisplayname(),
      'raum': s.room.id,
      'richtung': s.isOutgoing ? 'aus' : 'ein',
      'dauer': dauer,
      'ergebnis': ergebnis,
    };
    final list = <Object?>[entry, ...callLog.take(99)];
    try {
      await client.setAccountData(uid, callLogType, {'eintraege': list});
    } catch (e) {
      debugPrint('Anrufliste konnte nicht gespeichert werden: $e');
    }
  }

  // ---- WebRTCDelegate ----

  @override
  bool get canHandleNewCall => currentCall == null || currentCall!.callHasEnded;

  @override
  bool get isWeb => kIsWeb;

  @override
  EncryptionKeyProvider? get keyProvider => null; // nur für Gruppenanrufe nötig

  @override
  MediaDevices get mediaDevices => webrtc_impl.navigator.mediaDevices;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) =>
      webrtc_impl.createPeerConnection(configuration, constraints);

  @override
  Future<void> handleNewCall(CallSession session) async {
    currentCall = session;
    _track(session);
    onCallChanged.add(session);
  }

  @override
  Future<void> handleCallEnded(CallSession session) async {
    if (currentCall?.callId == session.callId) currentCall = null;
    onCallChanged.add(null);
    await _log(session);
  }

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {}

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> playRingtone() async {} // Klingelton folgt

  @override
  Future<void> stopRingtone() async {}
}
