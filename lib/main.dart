import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/network/api_client.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'features/auth/controller/auth_controller.dart';
import 'features/auth/view/login_screen.dart';
import 'features/home/view/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiClient.create();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const DocSyncApp(),
    ),
  );
}

class DocSyncApp extends ConsumerStatefulWidget {
  const DocSyncApp({super.key});

  @override
  ConsumerState<DocSyncApp> createState() => _DocSyncAppState();
}

class _DocSyncAppState extends ConsumerState<DocSyncApp> {
  @override
  void initState() {
    super.initState();
    // Re-validate any persisted session cookie on startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authed = ref.watch(authControllerProvider.select((s) => s.authenticated));
    return MaterialApp(
      title: 'DocSync AI',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: authed ? const HomeScreen() : const LoginScreen(),
    );
  }
}
