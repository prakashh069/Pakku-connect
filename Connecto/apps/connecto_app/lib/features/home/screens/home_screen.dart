import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';
import '../../calling/screens/keypad_tab.dart';
import '../../calling/screens/recent_calls_tab.dart';
import '../../contacts/screens/contacts_tab.dart';
import '../../dashboard/screens/dashboard_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return DashboardScreen(sessionState: widget.sessionState);
    }

    final colors = Theme.of(context).extension<CustomColors>()!;
    
    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          // Left side: Navigation and Tabs
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
                      width: 260,
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
                          height: 52,
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          indicatorColor: colors.accent.withAlpha(80),
                          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
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
          Container(width: 1, color: colors.border.withAlpha(50)),
          // Right side: Dashboard
          SizedBox(
            width: 380,
            child: ClipRect(
              child: DashboardScreen(sessionState: widget.sessionState),
            ),
          ),
        ],
      ),
    );
  }
}
