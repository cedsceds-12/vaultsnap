import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../widgets/vault_lock_scope.dart';
import 'home_shell.dart';
import 'setup_wizard_screen.dart';

/// Root widget that decides the initial screen based on vault state:
///   • vault_meta.json exists → [VaultLockScope] + [HomeShell]
///   • no vault file yet     → [SetupWizardScreen]
///
/// Uses [vaultMetaProvider] (FutureProvider) so the decision is async
/// and naturally handles loading / error states.
class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultAsync = ref.watch(vaultMetaProvider);

    return vaultAsync.when(
      loading: () => const _BootSurface(),
      error: (err, _) => _SplashError(error: err),
      data: (meta) {
        if (meta == null) {
          return const SetupWizardScreen();
        }
        return const VaultLockScope(child: HomeShell());
      },
    );
  }
}

class _BootSurface extends StatelessWidget {
  const _BootSurface();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }
}

class _SplashError extends StatelessWidget {
  final Object error;
  const _SplashError({required this.error});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: scheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load vault',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
