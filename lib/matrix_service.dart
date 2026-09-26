// Tuut – dünne Schicht über dem Matrix-SDK: Konto, Kontakte, Verschlüsselung, Anrufe.
import 'package:matrix/matrix.dart';
import 'calls/call_service.dart';

class MatrixService {
  final Client client;
  late final TuutCallService calls;

  MatrixService(this.client) {
    calls = TuutCallService(client);
  }

  bool get isLoggedIn => client.isLogged();

  /// true, wenn die Verschlüsselungsbibliothek geladen wurde und das Konto Schlüssel hat.
  bool get encryptionAvailable => client.encryptionEnabled;

  Future<void> connect(String homeserverUrl) async {
    await client.checkHomeserver(Uri.parse(homeserverUrl.trim()));
  }

  Future<void> login(String username, String password) async {
    await client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username.trim()),
      password: password,
    );
  }

  Future<void> register(String username, String password) async {
    await client.register(
      username: username.trim(),
      password: password,
      auth: AuthenticationData(type: AuthenticationTypes.dummy),
    );
  }

  /// Kontakte = Direktchat-Räume, inklusive offener Anfragen.
  List<Room> get contacts =>
      client.rooms.where((r) => r.isDirectChat).toList()
        ..sort((a, b) => a.getLocalizedDisplayname().compareTo(b.getLocalizedDisplayname()));

  /// Kontaktanfrage = neuer Direktchat. Verschlüsselt, sobald die Bibliothek verfügbar ist.
  Future<void> addContact(String matrixId) async {
    final id = matrixId.trim();
    if (!id.startsWith('@') || !id.contains(':')) {
      throw Exception('Bitte eine vollständige ID eingeben, z. B. @anna:tuut.local');
    }
    await client.startDirectChat(id, enableEncryption: encryptionAvailable);
  }

  /// Bestehenden, unverschlüsselten Chat auf Ende-zu-Ende-Verschlüsselung umstellen.
  /// Lässt sich nicht rückgängig machen (Matrix-Regel).
  Future<void> enableEncryption(Room room) => room.enableEncryption();

  Future<void> acceptInvite(Room room) => room.join();
  Future<void> declineInvite(Room room) => room.leave();

  Future<void> logout() => client.logout();
}
