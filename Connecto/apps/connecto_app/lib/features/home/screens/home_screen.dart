import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';
import '../../calling/screens/keypad_tab.dart';
import '../../calling/screens/recent_calls_tab.dart';
import '../../contacts/screens/contacts_tab.dart';
import '../widgets/android_unified_home.dart';
import '../widgets/macos_quick_actions.dart';
import '../../../main.dart';

class HomeScreen extends StatefulWidget {
  final DeviceSessionState sessionState;

  const HomeScreen({
    super.key,
    this.sessionState = DeviceSessionState.connected,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2; // Default to Contacts
  Map<String, dynamic>? _batteryData;
  String _phoneMode = 'normal';
  String _previousPhoneMode = 'normal';
  bool _phoneModeUpdating = false;
  bool _flashlightOn = false;
  bool _isRinging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ws = context.read<WebSocketService>();
      ws.onBatteryStatus = (data) {
        if (mounted) {
          setState(() {
            _batteryData = data;
          });
        }
      };
      ws.onDeviceState = (data) {
        if (mounted) {
          setState(() {
            if (data['ringing'] != null) _isRinging = data['ringing'] == true;
            if (data['flashlight'] != null) _flashlightOn = data['flashlight'] == true;
            if (data['mode'] != null) {
              _phoneMode = data['mode'] as String;
              _previousPhoneMode = _phoneMode;
            }
          });
        }
      };
      ws.onActionStatus = (action, status, error, data) {
        if (!mounted) return;
        if (action == 'ring') {
          if (status == 'success' && data['enabled'] != null) {
            setState(() {
              _isRinging = data['enabled'] == true;
            });
          }
        } else if (action == 'flashlight') {
          if (status == 'success' && data['enabled'] != null) {
            setState(() {
              _flashlightOn = data['enabled'] == true;
            });
          }
        } else if (action == 'set_ringer_mode') {
          if (status == 'permission_required') {
            setState(() { _phoneMode = _previousPhoneMode; _phoneModeUpdating = false; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grant Do Not Disturb access on your phone.')));
          } else if (status == 'success') {
            setState(() => _phoneModeUpdating = false);
          } else {
            setState(() { _phoneMode = _previousPhoneMode; _phoneModeUpdating = false; });
          }
        } else if (action == 'lock' && status == 'permission_required') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable Device Admin on your phone.')));
        } else if (status == 'error') {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error')));
        }
      };
    });
  }


  Widget _buildMacStatusRow(String label, String value, CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: colors.lightText, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                  color: colors.lightText.withAlpha(178), fontSize: 13),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacStatusPanel(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    final isConnected = widget.sessionState == DeviceSessionState.connected;
    final statusText = isConnected
        ? '● Connected'
        : (widget.sessionState == DeviceSessionState.paused
            ? '● Paused'
            : '● Offline');
    final statusColor = isConnected
        ? Colors.green
        : (widget.sessionState == DeviceSessionState.paused ? Colors.orange : Colors.red);
    final contactCount = ws.cachedContacts.length;

    Widget batteryWidget = const SizedBox();
    if (_batteryData != null) {
      final level = _batteryData!['level'] as int? ?? 0;
      final charging = _batteryData!['charging'] as bool? ?? false;
      
      batteryWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('$level%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colors.lightText)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(charging ? Icons.battery_charging_full : Icons.battery_full, size: 16, color: colors.lightText.withAlpha(150)),
              const SizedBox(width: 6),
              Text('Battery', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: colors.lightText.withAlpha(150))),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: level / 100.0,
              minHeight: 4,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation<Color>(charging ? colors.accent : Colors.white.withAlpha(200)),
            ),
          ),
          if (charging) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt, size: 16, color: colors.accent),
                const SizedBox(width: 4),
                Text('Charging', style: TextStyle(fontSize: 13, color: colors.accent, fontWeight: FontWeight.w500)),
              ],
            )
          ],
        ],
      );
    } else {
      batteryWidget = const Center(child: Text('Battery\nUnknown', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)));
    }

    return Container(
      width: 240,
      color: colors.background.withAlpha(240),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: ListView(
        children: [
          Row(
            children: [
              Text(statusText,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 32),
          batteryWidget,
          const SizedBox(height: 32),
          Text('Phone Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colors.lightText)),
          const SizedBox(height: 12),
          _buildPhoneModeSegmentedControl(colors, ws),
          const SizedBox(height: 32),
          Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colors.lightText)),
          const SizedBox(height: 12),
          MacOsQuickActions(colors: colors, ws: ws, flashlightOn: _flashlightOn, isRinging: _isRinging),
          const SizedBox(height: 32),
          _buildMacStatusRow('Contacts', '$contactCount', colors),
        ],
      ),
    );
  }

  Widget _buildPhoneModeSegmentedControl(CustomColors colors, WebSocketService ws) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              _buildPhoneModeSegment('normal', Icons.notifications_none, 'Normal', colors, ws),
              _buildPhoneModeSegment('vibrate', Icons.vibration, 'Vibrate', colors, ws),
              _buildPhoneModeSegment('silent', Icons.notifications_off, 'Silent', colors, ws),
            ],
          ),
        ),
        if (_phoneModeUpdating)
          const CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildPhoneModeSegment(String mode, IconData icon, String tooltip, CustomColors colors, WebSocketService ws) {
    final isSelected = _phoneMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _previousPhoneMode = _phoneMode;
            _phoneMode = mode;
            _phoneModeUpdating = true;
          });
          ws.setRingerMode(mode);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? colors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(2),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : colors.lightText.withAlpha(120),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMacLayout(
      BuildContext context, CustomColors colors, WebSocketService ws) {
    return Column(
      children: [
        if (widget.sessionState == DeviceSessionState.disconnected ||
            widget.sessionState == DeviceSessionState.reconnecting ||
            widget.sessionState == DeviceSessionState.connecting ||
            widget.sessionState == DeviceSessionState.paused)
          Container(
            width: double.infinity,
            color: widget.sessionState == DeviceSessionState.paused
                ? colors.warning.withAlpha(220)
                : (widget.sessionState == DeviceSessionState.connecting ||
                        widget.sessionState == DeviceSessionState.reconnecting)
                    ? colors.primary.withAlpha(220)
                    : colors.danger.withAlpha(220),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              widget.sessionState == DeviceSessionState.paused
                  ? 'Connection paused'
                  : (widget.sessionState == DeviceSessionState.connecting ||
                          widget.sessionState ==
                              DeviceSessionState.reconnecting)
                      ? 'Connecting...'
                      : 'Phone is offline',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          KeypadTab(isActive: _currentIndex == 0),
                          const RecentCallsTab(),
                          const ContactsTab(),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Container(
                          width: 260, // concise width
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(50),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: NavigationBar(
                              selectedIndex: _currentIndex,
                              onDestinationSelected: (idx) {
                                setState(() {
                                  _currentIndex = idx;
                                });
                                if (idx != 0) {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                }
                              },
                              height: 52, // smaller height
                              elevation: 0,
                              backgroundColor: Colors.transparent,
                              indicatorColor: colors.accent.withAlpha(80),
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysHide,
                              destinations: const [
                                NavigationDestination(
                                    icon: Icon(Icons.dialpad, size: 22),
                                    label: 'Keypad'),
                                NavigationDestination(
                                    icon: Icon(Icons.history, size: 22),
                                    label: 'Recents'),
                                NavigationDestination(
                                    icon: Icon(Icons.contacts, size: 22),
                                    label: 'Contacts'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, color: colors.surface),
              SizedBox(
                  width: 240, child: _buildMacStatusPanel(context, colors, ws)),
            ],
          ),
        ),

      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final ws = context.watch<WebSocketService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoAsset = isDark
        ? 'assets/images/connecto_logo_dark.png'
        : 'assets/images/connecto_logo_light.png';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Image.asset(
          logoAsset,
          height: 34,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Disconnect',
            onPressed: () async {
              // Step 1: Try to notify other device (best-effort, non-blocking) before closing socket
              if (Platform.isMacOS) {
                try {
                  await ws.send({'type': 'unpair'});
                  await Future.delayed(const Duration(milliseconds: 100)); // allow flush
                } catch (_) {}
              } else {
                try {
                  const platform = MethodChannel('com.connecto.app/platform');
                  platform.invokeMethod('unpair');
                } catch (_) {}
              }

              // Step 2: Clear all local paired state immediately (no network needed)
              final prefs = await SharedPreferences.getInstance();
              await clearAllPairedState(prefs);
              ws.reset(); // Clears credentials so we can't reconnect with stale secret

              // Step 3: Always navigate away regardless of network state
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: Platform.isMacOS
          ? _buildMacLayout(context, colors, ws)
          : AndroidUnifiedHome(sessionState: widget.sessionState, batteryData: _batteryData),
    );
  }
}
