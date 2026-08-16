import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/constants/app_theme.dart';
import '../services/settings_service.dart';
import '../../../features/clipboard/services/clipboard_sync_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final settings = context.watch<SettingsService>();
    final clipboardManager = context.watch<ClipboardSyncManager>();
    
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              _buildSectionHeader('General', colors),
              _buildCard(
                colors,
                children: [
                  if (Platform.isMacOS)
                    _buildSwitchTile(
                      title: 'Launch at login',
                      subtitle: 'Start Connecto automatically when you log in',
                      value: settings.launchAtStartup,
                      onChanged: settings.setLaunchAtStartup,
                      colors: colors,
                      isTop: true,
                      isBottom: false,
                    ),
                  if (Platform.isMacOS)
                    _buildDivider(colors),
                  _buildThemeDropdown(
                    colors: colors,
                    currentTheme: settings.themeMode,
                    onChanged: (val) {
                      if (val != null) settings.setThemeMode(val);
                    },
                    isTop: !Platform.isMacOS,
                    isBottom: true,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              _buildSectionHeader('Transfers', colors),
              _buildCard(
                colors,
                children: [
                  _buildSwitchTile(
                    title: 'Auto-open folder',
                    subtitle: 'Show files in Finder after receiving',
                    value: settings.autoOpenFolder,
                    onChanged: settings.setAutoOpenFolder,
                    colors: colors,
                    isTop: true,
                    isBottom: true,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              _buildSectionHeader('Clipboard', colors),
              _buildCard(
                colors,
                children: [
                  _buildSwitchTile(
                    title: 'Universal Clipboard',
                    subtitle: 'Sync clipboard text between paired devices',
                    value: clipboardManager.enabled,
                    onChanged: clipboardManager.setEnabled,
                    colors: colors,
                    isTop: true,
                    isBottom: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: colors.textSecondary.withAlpha(150),
        ).copyWith(fontFamily: '.SF Pro Text'),
      ),
    );
  }

  Widget _buildCard(CustomColors colors, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withAlpha(50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required CustomColors colors,
    bool isTop = false,
    bool isBottom = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.vertical(
          top: isTop ? const Radius.circular(16) : Radius.zero,
          bottom: isBottom ? const Radius.circular(16) : Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ).copyWith(fontFamily: '.SF Pro Text'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ).copyWith(fontFamily: '.SF Pro Text'),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: colors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 1,
        color: colors.border.withAlpha(100),
      ),
    );
  }

  Widget _buildThemeDropdown({
    required ThemeMode currentTheme,
    required ValueChanged<ThemeMode?> onChanged,
    required CustomColors colors,
    bool isTop = false,
    bool isBottom = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Appearance',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ).copyWith(fontFamily: '.SF Pro Text'),
          ),
          DropdownButton<ThemeMode>(
            value: currentTheme,
            underline: const SizedBox(),
            icon: Icon(Icons.arrow_drop_down, color: colors.textSecondary),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ).copyWith(fontFamily: '.SF Pro Text'),
            dropdownColor: colors.surface2,
            onChanged: onChanged,
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
        ],
      ),
    );
  }
}
