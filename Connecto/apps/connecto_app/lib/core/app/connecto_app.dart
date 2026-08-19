import 'package:flutter/material.dart';

import '../di/app_providers.dart';
import 'app_shell.dart';

class ConnectoApp extends StatelessWidget {
  const ConnectoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppProviders(
      child: AppShell(),
    );
  }
}
