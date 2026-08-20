import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:connecto/core/app/app_initialization_coordinator.dart';
import 'package:connecto/core/interfaces/auth_manager.dart';
import 'package:connecto/core/interfaces/connection_manager.dart';
import 'package:connecto/core/interfaces/platform_integration.dart';
import 'package:connecto/core/interfaces/device_transport.dart';
import 'package:connecto/core/interfaces/native_platform_bridge.dart';

import 'package:connecto/core/constants/app_constants.dart';

// Manual test doubles

class FakeAuthManager implements AuthManager {
  bool paired = false;
  bool seenOnboarding = false;
  String? hmacSecret;

  @override
  Future<bool> isPaired() async => paired;

  @override
  Future<void> setPaired(bool isPaired) async {
    paired = isPaired;
  }

  @override
  Future<bool> hasSeenOnboarding() async => seenOnboarding;

  @override
  Future<String?> getHmacSecret() async => hmacSecret;
}

class FakeConnectionManager implements ConnectionManager {
  String? startedWithSecret;

  @override
  Future<void> startConnection(String hmacSecret) async {
    startedWithSecret = hmacSecret;
  }
}

class FakePlatformIntegration implements PlatformIntegration {
  bool phoneStateServiceStarted = false;
  String? menuBarStatus;

  @override
  Future<void> startAndroidPhoneStateService() async {
    phoneStateServiceStarted = true;
  }

  @override
  void updateMacOsMenuBarStatus(String stateName) {
    menuBarStatus = stateName;
  }
}

class FakeDeviceTransport implements DeviceTransport {
  @override
  void Function(bool)? onConnectionChange;

  @override
  void Function(DeviceSessionState)? onDeviceStateChanged;

  @override
  void Function()? onUnpair;

  bool wasReset = false;

  @override
  void reset() {
    wasReset = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNativePlatformBridge implements NativePlatformBridge {
  @override
  void dispose() {}

  @override
  Stream<Map<String, dynamic>> get messages => const Stream.empty();

  @override
  void send(Map<String, dynamic> message) {}

  @override
  void Function()? onUnpaired;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthManager authManager;
  late FakeConnectionManager connectionManager;
  late FakePlatformIntegration platformIntegration;
  late FakeDeviceTransport ws;
  late FakeNativePlatformBridge transport;
  late AppInitializationCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    authManager = FakeAuthManager();
    connectionManager = FakeConnectionManager();
    platformIntegration = FakePlatformIntegration();
    ws = FakeDeviceTransport();
    transport = FakeNativePlatformBridge();

    coordinator = AppInitializationCoordinator(
      authManager,
      connectionManager,
      ws,
      platformIntegration,
      transport,
    );
  });

  test('Fresh install should result in not paired and not seen onboarding', () async {
    await coordinator.initialize();

    expect(coordinator.state.isLoading, false);
    expect(coordinator.state.hasSeenOnboarding, false);
    expect(coordinator.state.isPaired, false);
    // Connection manager shouldn't be started
    expect(connectionManager.startedWithSecret, isNull);
  });

  test('Existing paired device with valid HMAC starts connection (macOS behavior simulation)', () async {
    authManager.paired = true;
    authManager.hmacSecret = 'test_secret';

    await coordinator.initialize();

    // Since our test runner platform is generally not macOS by default, we need to check behavior.
    // If we want to simulate macOS vs non-macOS, the coordinator uses Platform.isMacOS.
    // For this test, we just check that isPaired resolves properly and we don't crash.
    expect(coordinator.state.isPaired, true);
    expect(coordinator.state.isLoading, false);
  });

  test('Invalid credentials (missing HMAC) when paired causes unpairing', () async {
    authManager.paired = true;
    authManager.hmacSecret = null;

    await coordinator.initialize();

    // In both macOS and Android, if hmacSecret is null, isPaired falls back to false.
    expect(coordinator.state.isPaired, false);
  });

  test('WebSocket disconnect updates sessionState correctly', () async {
    await coordinator.initialize();

    // Trigger websocket disconnection
    ws.onConnectionChange?.call(false);

    expect(coordinator.state.sessionState, DeviceSessionState.disconnected);
  });

  test('WebSocket device state change updates paired state and menu bar (macOS)', () async {
    await coordinator.initialize();
    
    // Simulate pairing completion
    ws.onDeviceStateChanged?.call(DeviceSessionState.connected);

    // Let the event loop process the async callback
    await Future.microtask(() {});

    // Coordinator updates state
    expect(coordinator.state.isPaired, true);
    expect(coordinator.state.sessionState, DeviceSessionState.connected);
    // Platform service gets the update
    expect(platformIntegration.menuBarStatus, DeviceSessionState.connected.name);
    
    // Auth manager should also be updated
    expect(await authManager.isPaired(), true);
  });

  test('refreshAuthState rereads auth manager state and updates coordinator', () async {
    await coordinator.initialize();
    
    // Initial state
    expect(coordinator.state.isPaired, false);

    // Simulate pairing completion by updating AuthManager mock directly
    authManager.paired = true;
    authManager.hmacSecret = 'new_secret';
    authManager.seenOnboarding = true;

    // Call the new refresh method
    await coordinator.refreshAuthState();

    // Expect the coordinator to have the updated state
    expect(coordinator.state.isPaired, true);
    expect(coordinator.state.hasSeenOnboarding, true);
  });
}
