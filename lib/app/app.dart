import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/screen_protector_service.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

class BharosaApp extends ConsumerStatefulWidget {
  const BharosaApp({super.key});

  @override
  ConsumerState<BharosaApp> createState() => _BharosaAppState();
}

class _BharosaAppState extends ConsumerState<BharosaApp> with WidgetsBindingObserver {
  DateTime? _pausedTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSecurity();
  }

  Future<void> _initSecurity() async {
    final storage = ref.read(secureStorageProvider);
    final blocked = await storage.isScreenshotBlocked();
    if (blocked) {
      await ScreenProtectorService.setSecure(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedTime != null) {
        final lockState = ref.read(appLockProvider);
        if (lockState.isPinSet) {
          final diff = DateTime.now().difference(_pausedTime!).inSeconds;
          if (diff >= lockState.lockTimeoutSeconds) {
            ref.read(appLockProvider.notifier).lock();
            appRouter.go('/lock');
          }
        }
      }
      _pausedTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bharosa',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light, // Strict light theme only per design specifications
      routerConfig: appRouter,
    );
  }
}
