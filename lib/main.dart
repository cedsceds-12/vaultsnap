import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'navigation/vault_root_navigator.dart';
import 'screens/app_router.dart';
import 'services/settings_storage.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_crossfade.dart';

void main() {
  // Wrap startup so any synchronous OR asynchronous exception flows
  // through `PlatformDispatcher.instance.onError` below — without this,
  // uncaught async errors in release builds crash the isolate silently.
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // Surface framework-level widget errors (build/layout/paint) into
      // FlutterError.dumpErrorToConsole AND a no-secrets sentinel.
      // Release builds default to swallowing these — the user just sees
      // a frozen frame with no recovery.
      final defaultOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        // Delegate to the framework default (logs to console in debug,
        // no-op in release) so behaviour matches Flutter conventions.
        defaultOnError?.call(details);
        // Project rule (CLAUDE.md): never log sensitive material. We log
        // only the exception type + library, not the message or stack —
        // a thrown VMK or master password could appear in `details`.
        debugPrint('[VaultSnap] FlutterError in '
            '${details.library ?? "unknown"}: '
            '${details.exception.runtimeType}');
      };

      // Engine / platform-side uncaught errors (MethodChannel failures,
      // isolate-level throws). Returning `true` marks the error handled
      // so it doesn't crash the engine.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('[VaultSnap] Uncaught platform error: '
            '${error.runtimeType}');
        return true;
      };

      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );

      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();

      runApp(
        ProviderScope(
          child: VaultSnapApp(
            lightTheme: lightTheme,
            darkTheme: darkTheme,
            initialThemeMode: ThemeMode.system,
          ),
        ),
      );
    },
    (Object error, StackTrace stack) {
      // Belt-and-braces — anything that escapes both handlers above lands
      // here. Same redaction policy.
      debugPrint('[VaultSnap] Zone-uncaught error: ${error.runtimeType}');
    },
  );
}

Future<ThemeMode> _loadThemeMode() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final storage = SettingsStorage('${dir.path}/vaultsnap_settings.json');
    final data = await storage.load();
    return switch (data['themeMode'] as String?) {
      'system' => ThemeMode.system,
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {
    return ThemeMode.system;
  }
}

Future<void> _syncNativeThemeMode(ThemeMode mode) async {
  try {
    const channel = MethodChannel('com.vaultsnap.app/window');
    await channel.invokeMethod('setThemeMode', {'mode': mode.name});
  } on MissingPluginException {
    // Tests / non-Android platforms won't have the native channel.
  }
}

class VaultSnapApp extends StatefulWidget {
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeMode initialThemeMode;

  const VaultSnapApp({
    super.key,
    required this.lightTheme,
    required this.darkTheme,
    required this.initialThemeMode,
  });

  @override
  State<VaultSnapApp> createState() => _VaultSnapAppState();
}

class _VaultSnapAppState extends State<VaultSnapApp> {
  late final ThemeController _themeController;
  final _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _themeController = ThemeController(initial: widget.initialThemeMode);
    _themeController.captureKey = _captureKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPersistedThemeMode());
    });
  }

  Future<void> _loadPersistedThemeMode() async {
    final mode = await _loadThemeMode();
    if (!mounted) return;
    _themeController.setMode(mode);
    unawaited(_syncNativeThemeMode(mode));
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _themeController,
      child: ListenableBuilder(
        listenable: _themeController,
        builder: (context, _) {
          return MaterialApp(
            navigatorKey: vaultRootNavigatorKey,
            title: 'VaultSnap',
            debugShowCheckedModeBanner: false,
            theme: widget.lightTheme,
            darkTheme: widget.darkTheme,
            themeMode: _themeController.mode,
            // The theme is applied INSTANTLY (single frame). The visual
            // smoothness is provided by ThemeCrossfade below — a snapshot
            // of the old frame fades out on top. This avoids Flutter's
            // built-in per-frame ThemeData.lerp() which is what was
            // dropping frames on high-refresh-rate displays.
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              // Keep the controller's pixelRatio in sync so captured
              // snapshots match the screen resolution exactly.
              _themeController.pixelRatio = mq.devicePixelRatio;
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.3,
                  ),
                ),
                child: ThemeCrossfade(
                  controller: _themeController,
                  captureKey: _captureKey,
                  child: child!,
                ),
              );
            },
            home: const AppRouter(),
          );
        },
      ),
    );
  }
}
