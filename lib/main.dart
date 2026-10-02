import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'worker_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase for the web using the generated options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // ProviderScope enables Riverpod globally
  runApp(const ProviderScope(child: Kiosk()));
}

// Replace the old StateProvider line with this modern Notifier structure:
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void toggleTheme() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class Kiosk extends ConsumerWidget {
  const Kiosk({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the theme provider to rebuild when toggled
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

// GoRouter handles the web URLs cleanly
final _router = GoRouter(
  initialLocation: '/worker', // Defaulting to worker for now
  routes: [
   GoRoute(
  path: '/worker',
  builder: (context, state) => const WorkerScreen(),
),
    GoRoute(
      path: '/worker',
      builder: (context, state) => const Scaffold(body: Center(child: Text('Worker Data Entry'))),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const Scaffold(body: Center(child: Text('Admin Dashboard'))),
    ),
  ],
);