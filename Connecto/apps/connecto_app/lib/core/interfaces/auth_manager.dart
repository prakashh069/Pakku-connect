abstract class AuthManager {
  Future<bool> isPaired();
  Future<void> setPaired(bool paired);
  Future<bool> hasSeenOnboarding();
  Future<String?> getHmacSecret();
}
