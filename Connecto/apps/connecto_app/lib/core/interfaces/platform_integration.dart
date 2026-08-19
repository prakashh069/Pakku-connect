abstract class PlatformIntegration {
  Future<void> startAndroidPhoneStateService();
  void updateMacOsMenuBarStatus(String stateName);
}
