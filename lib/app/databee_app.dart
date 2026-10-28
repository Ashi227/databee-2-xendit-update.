import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/auth_screen.dart';
import '../screens/store_shell.dart';
import 'theme.dart';

class DataBeeApp extends StatelessWidget {
  const DataBeeApp({super.key, required this.backendConfigured});

  final bool backendConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DataBee',
      debugShowCheckedModeBanner: false,
      theme: dataBeeTheme,
      home: backendConfigured
          ? StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                if (Supabase.instance.client.auth.currentSession == null) {
                  return const AuthScreen();
                }
                return const StoreShell();
              },
            )
          : const StoreShell(demoMode: true),
    );
  }
}
