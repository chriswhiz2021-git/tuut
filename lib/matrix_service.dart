// Tuut – Schritt 1b: dünne Schicht über dem Matrix-SDK.
// Noch OHNE Verschlüsselung (kommt in Schritt 2).
import 'package:matrix/matrix.dart';

class MatrixService {
  final Client client;
  MatrixService(this.client);

  bool get isLoggedIn => client.isLogged();

  /// Prüft, ob unter [homeserverUrl] ein Matrix-Server antwortet.
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

  /// Registrierung ohne E-Mail-Bestätigung – passt zur lokalen Server-Konfiguration.
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

  /// Legt einen Direktchat mit einer Matrix-ID an (= Kontaktanfrage).
  Future<void> addContact(String matrixId) async {
    final id = matrixId.trim();
    if (!id.startsWith('@') || !id.contains(':')) {
      throw Exception('Bitte eine vollständige ID eingeben, z. B. @anna:tuut.local');
    }
    await client.startDirectChat(id, enableEncryption: false);
  }

  Future<void> acceptInvite(Room room) => room.join();
  Future<void> declineInvite(Room room) => room.leave();

  Future<void> logout() => client.logout();
}
