import 'package:flutter/material.dart';

import '../../features/settings/screens/settings_screen.dart';
import '../../features/home/screens/home_screen.dart';
import 'root_router.dart';

final Map<String, WidgetBuilder> appRoutes = {
  '/settings': (context) => const SettingsScreen(),
  '/': (_) => const RootRouter(),
  '/home': (_) => const HomeScreen(),
};
