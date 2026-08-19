import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../navigation/navigation_service.dart';
import '../navigation/app_routes.dart';
import '../di/app_providers.dart';

class ConnectoApp extends StatelessWidget {
  const ConnectoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      child: MaterialApp(
        title: 'Connecto',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildAppTheme(isDark: false),
        darkTheme: buildAppTheme(isDark: true),
        themeMode: ThemeMode.system,
        initialRoute: '/',
        routes: appRoutes,
      ),
    );
  }
}
