import 'package:flutter/material.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';

class MacOsQuickActions extends StatelessWidget {
  final CustomColors colors;
  final WebSocketService ws;
  final bool flashlightOn;
  final bool isRinging;

  const MacOsQuickActions({
    super.key,
    required this.colors,
    required this.ws,
    required this.flashlightOn,
    required this.isRinging,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildActionTile(
          icon: Icons.flashlight_on,
          title: 'Flashlight',
          isActive: flashlightOn,
          colors: colors,
          onTap: () {
            ws.sendDeviceAction('flashlight', enabled: !flashlightOn);
          },
        ),
        _buildActionTile(
          icon: Icons.notifications_active,
          title: 'Ring Phone',
          isActive: isRinging,
          colors: colors,
          onTap: () {
            ws.sendDeviceAction('ring', enabled: !isRinging);
          },
        ),
        _buildActionTile(
          icon: Icons.lock_outline,
          title: 'Lock',
          isActive: false,
          colors: colors,
          onTap: () => ws.sendDeviceAction('lock'),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required bool isActive,
    required CustomColors colors,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface2,
            border: Border.all(
              color: isActive ? colors.accent.withAlpha(150) : colors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: colors.accent.withAlpha(50),
                      blurRadius: 12,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: isActive ? colors.accent : colors.lightText),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      color: isActive ? colors.accent : colors.lightText,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
