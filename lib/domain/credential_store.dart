import 'catalog.dart';

abstract interface class CredentialStore {
  Future<String?> readCredential(GameMode mode);
  Future<void> writeCredential(GameMode mode, String token);
  Future<void> removeCredential(GameMode mode);
}
