import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../navigation/navigation_service.dart';
import '../navigation/app_routes.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connecto',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildAppTheme(isDark: false),
      darkTheme: buildAppTheme(isDark: true),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: appRoutes,
    );
  }
}
