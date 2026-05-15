import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vault_meta.dart';
import '../navigation/vault_root_navigator.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../providers/vault_setup_provider.dart';
import '../services/autofill_session_service.dart';
import '../services/recovery_backoff_controller.dart';
import 'vault_bottom_sheet.dart';

final vaultLockControllerProvider = Provider<VaultLockController>((ref) {
  final controller = VaultLockController();
  ref.onDispose(controller.dispose);
  return controller;
});

class VaultLockController extends ChangeNotifier {
  Uint8List? _vmk;

  /// Auto-lock timeout in minutes. 0 = lock immediately on background.
  int _autoLockMinutes = 5;

  /// Called whenever autoLockMinutes changes, so the scope can persist it.
  void Function(int minutes)? onAutoLockChanged;

  int get autoLockMinutes => _autoLockMinutes;

  set autoLockMinutes(int value) {
    if (_autoLockMinutes == value) return;
    _autoLockMinutes = value;
    onAutoLockChanged?.call(value);
    notifyListeners();
  }

  /// Set auto-lock without triggering the persist callback.
  /// Used during initial load from disk.
  void setAutoLockFromDisk(int value) {
    if (_autoLockMinutes == value) return;
    _autoLockMinutes = value;
    notifyListeners();
  }

  bool get isUnlocked => _vmk != null;
  bool get isLocked => _vmk == null;

  Uint8List? get vmk {
    final value = _vmk;
    return value == null ? null : Uint8List.fromList(value);
  }

  void unlock(Uint8List vmk) {
    _wipe();
    _vmk = Uint8List.fromList(vmk);
    notifyListeners();
  }

  void lock() {
    if (_vmk == null) return;
    _wipe();
    notifyListeners();
  }

  void _wipe() {
    final value = _vmk;
    if (value == null) return;
    for (var i = 0; i < value.length; i++) {
      value[i] = 0;
    }
    _vmk = null;
  }

  @override
  void dispose() {
    _wipe();
    super.dispose();
  }
}

class VaultLockScope extends ConsumerStatefulWidget {
  final Widget child;

  const VaultLockScope({super.key, required this.child});

  static VaultLockController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_VaultLockInherited>();
    assert(scope != null, 'No VaultLockScope found in context');
    return scope!.controller;
  }

  @override
  ConsumerState<VaultLockScope> createState() => _VaultLockScopeState();
}

class _VaultLockScopeState extends ConsumerState<VaultLockScope>
    with WidgetsBindingObserver {
  late final VaultLockController _controller;
  Timer? _autoLockTimer;
  Timer? _lockExitTimer;
  DateTime? _backgroundedAt;
  bool _showLockOverlay = true;
  bool _lockOverlayExiting = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(vaultLockControllerProvider);
    _controller.addListener(_onLockStateChanged);
    _controller.onAutoLockChanged = _persistAutoLock;
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    try {
      final storage = await ref.read(settingsStorageProvider.future);
      final data = await storage.load();
      final minutes = data['autoLockMinutes'] as int?;
      if (minutes != null) {
        _controller.setAutoLockFromDisk(minutes);
      }
      final clipClear = data['clipboardClear'] as bool?;
      if (clipClear != null) {
        ref.read(clipboardServiceProvider).enabled = clipClear;
      }
      final secure = data['flagSecure'] as bool?;
      if (secure == true) {
        await ref.read(windowServiceProvider).setSecure(true);
      }
    } catch (_) {
      // First run or corrupted settings — use defaults.
    }
  }

  Future<void> _persistAutoLock(int minutes) async {
    try {
      final storage = await ref.read(settingsStorageProvider.future);
      final data = await storage.load();
      data['autoLockMinutes'] = minutes;
      await storage.save(data);
    } catch (_) {
      // Non-critical — the in-memory value still works this session.
    }
  }

  @override
  void dispose() {
    unawaited(AutofillSessionService.clear());
    _autoLockTimer?.cancel();
    _lockExitTimer?.cancel();
    _controller.removeListener(_onLockStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLockStateChanged() {
    _lockExitTimer?.cancel();
    if (_controller.isUnlocked) {
      final vmk = _controller.vmk;
      if (vmk != null) {
        unawaited(AutofillSessionService.syncAfterUnlock(vmk: vmk));
      }
      _resetAutoLockTimer();
      if (!mounted) return;
      setState(() => _lockOverlayExiting = true);
      _lockExitTimer = Timer(const Duration(milliseconds: 240), () {
        if (!mounted || _controller.isLocked) return;
        setState(() {
          _showLockOverlay = false;
          _lockOverlayExiting = false;
        });
      });
    } else {
      unawaited(AutofillSessionService.clear());
      _autoLockTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = vaultRootNavigatorKey.currentState;
        if (nav != null && nav.mounted) {
          nav.popUntil((route) => route.isFirst);
        }
      });
      if (!mounted) return;
      setState(() {
        _showLockOverlay = true;
        _lockOverlayExiting = false;
      });
    }
  }

  void _resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    final minutes = _controller.autoLockMinutes;
    if (minutes <= 0) return;
    _autoLockTimer = Timer(Duration(minutes: minutes), () {
      if (_controller.isUnlocked) _controller.lock();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final minutes = _controller.autoLockMinutes;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!_controller.isUnlocked) return;
      // The autofill flow programmatically minimizes us via moveTaskToBack
      // right after a successful unlock. That pause must NOT trigger
      // auto-lock — otherwise the session is cleared before
      // AutofillAuthActivity can read it and deliver the FillResponse.
      if (AutofillSessionService.consumeBackgroundLockSuppression()) {
        return;
      }
      if (minutes == 0) {
        _controller.lock();
        return;
      }
      // Android can pause Dart timers while we're backgrounded, so the
      // in-process [_autoLockTimer] is unreliable across long pauses.
      // Record wall-clock background time only on real background states;
      // transient inactive states (app switcher/taskbar peek) should not lock.
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _controller.isUnlocked) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && minutes > 0) {
        final elapsed = DateTime.now().difference(since);
        if (elapsed >= Duration(minutes: minutes)) {
          _controller.lock();
          return;
        }
      }
      _resetAutoLockTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _VaultLockInherited(
      controller: _controller,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              if (_showLockOverlay)
                _LockOverlay(
                  controller: _controller,
                  exiting: _lockOverlayExiting,
                ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _VaultLockInherited extends InheritedNotifier<VaultLockController> {
  final VaultLockController controller;

  const _VaultLockInherited({required this.controller, required super.child})
    : super(notifier: controller);
}

class _LockOverlay extends ConsumerStatefulWidget {
  final VaultLockController controller;
  final bool exiting;

  const _LockOverlay({required this.controller, required this.exiting});

  @override
  ConsumerState<_LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends ConsumerState<_LockOverlay> {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  bool _verifying = false;
  String? _error;
  bool _biometricBusy = false;
  bool _autoBiometricAttempted = false;
  final _recoveryBackoff = RecoveryBackoffController();

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your master password');
      return;
    }
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final service = await ref.read(vaultSetupServiceProvider.future);
      final meta = await ref.read(vaultMetaProvider.future);
      if (meta == null || !mounted) return;

      final vmk = await service.verifyPassword(
        masterPassword: password,
        meta: meta,
      );

      if (!mounted) return;
      if (vmk == null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _verifying = false;
          _error = 'Wrong password';
        });
        return;
      }

      await service.recordUnlock(meta);
      ref.invalidate(vaultMetaProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _focusNode.unfocus();
      widget.controller.unlock(vmk);
      unawaited(
        ref
            .read(vaultRepositoryProvider.notifier)
            .refreshSecurityFlags()
            .catchError((_) {}),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Unlock failed';
      });
    }
  }

  List<Widget> _buildBiometricSection(ColorScheme scheme) {
    final metaAsync = ref.watch(vaultMetaProvider);
    final hasBio = metaAsync.whenOrNull(data: (m) => m?.hasBiometric) ?? false;
    if (!hasBio) return const [];
    return [
      const SizedBox(height: 18),
      _OrDivider(scheme: scheme),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: (_verifying || _biometricBusy) ? null : _unlockBiometric,
        icon: _biometricBusy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              )
            : const Icon(Icons.fingerprint_rounded),
        label: Text(_biometricBusy ? 'Verifying...' : 'Use biometrics'),
      ),
    ];
  }

  void _maybeStartAutoBiometric(bool hasBio) {
    if (!hasBio ||
        _autoBiometricAttempted ||
        _biometricBusy ||
        _verifying ||
        widget.controller.isUnlocked) {
      return;
    }
    _autoBiometricAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller.isUnlocked) return;
      unawaited(_unlockBiometric());
    });
  }

  Future<void> _unlockBiometric() async {
    if (_biometricBusy || _verifying) return;
    setState(() => _biometricBusy = true);

    try {
      final service = await ref.read(vaultSetupServiceProvider.future);
      final meta = await ref.read(vaultMetaProvider.future);
      if (meta == null || !meta.hasBiometric || !mounted) {
        setState(() => _biometricBusy = false);
        return;
      }

      final vmk = await service.unlockWithBiometric(meta: meta);
      if (!mounted) return;

      if (vmk == null) {
        setState(() => _biometricBusy = false);
        return;
      }

      await service.recordUnlock(meta);
      ref.invalidate(vaultMetaProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.controller.unlock(vmk);
      unawaited(
        ref
            .read(vaultRepositoryProvider.notifier)
            .refreshSecurityFlags()
            .catchError((_) {}),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _biometricBusy = false);
    }
  }

  Future<void> _openRecoveryReset() async {
    final meta = await ref.read(vaultMetaProvider.future);
    if (!mounted || meta == null) return;

    await showVaultBottomSheet<void>(
      context: context,
      child: _RecoveryResetSheet(
        controller: widget.controller,
        meta: meta,
        backoff: _recoveryBackoff,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasBio =
        ref.watch(vaultMetaProvider).whenOrNull(data: (m) => m?.hasBiometric) ??
        false;
    _maybeStartAutoBiometric(hasBio);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: widget.exiting,
        child: AnimatedSlide(
          duration: duration,
          curve: widget.exiting ? Curves.easeInQuart : Curves.easeOutCubic,
          offset: widget.exiting ? const Offset(0, -0.025) : Offset.zero,
          child: AnimatedScale(
            duration: duration,
            curve: widget.exiting ? Curves.easeInQuart : Curves.easeOutCubic,
            scale: widget.exiting ? 0.985 : 1,
            child: AnimatedOpacity(
              duration: duration,
              curve: widget.exiting ? Curves.easeInQuart : Curves.easeOutCubic,
              opacity: widget.exiting ? 0 : 1,
              child: Material(
                color: scheme.surface,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 28),
                            _BrandMark(scheme: scheme),
                            const SizedBox(height: 48),
                            TextField(
                              controller: _passwordController,
                              focusNode: _focusNode,
                              obscureText: _obscure,
                              enabled: !_verifying,
                              autocorrect: false,
                              enableSuggestions: false,
                              // K-14: opt this field out of autofill so a
                              // *different* installed autofill service can't
                              // see, suggest into, or log VaultSnap's master
                              // password — the keystone credential that
                              // unlocks every other entry. Empty list is
                              // Flutter's documented "disable autofill"
                              // signal (sets IMPORTANT_FOR_AUTOFILL_NO on
                              // the underlying Android view).
                              autofillHints: const <String>[],
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _unlock(),
                              decoration: InputDecoration(
                                hintText: 'Master password',
                                errorText: _error,
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _verifying ? null : _unlock,
                              icon: _verifying
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: scheme.onPrimary,
                                      ),
                                    )
                                  : const Icon(Icons.lock_open_rounded),
                              label: Text(
                                _verifying ? 'Unlocking...' : 'Unlock',
                              ),
                            ),
                            ..._buildBiometricSection(scheme),
                            const SizedBox(height: 22),
                            TextButton(
                              onPressed: (_verifying || _biometricBusy)
                                  ? null
                                  : _openRecoveryReset,
                              child: Text(
                                'Forgot password?',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),
                            _PrivacyFooter(scheme: scheme),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryResetSheet extends ConsumerStatefulWidget {
  final VaultLockController controller;
  final VaultMeta meta;
  final RecoveryBackoffController backoff;

  const _RecoveryResetSheet({
    required this.controller,
    required this.meta,
    required this.backoff,
  });

  @override
  ConsumerState<_RecoveryResetSheet> createState() =>
      _RecoveryResetSheetState();
}

class _RecoveryResetSheetState extends ConsumerState<_RecoveryResetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _answerController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _answerController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final wait = widget.backoff.remaining;
    if (wait > Duration.zero) {
      setState(() {
        _error = 'Try again in ${wait.inSeconds + 1}s';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = await ref.read(vaultSetupServiceProvider.future);
      final reset = await service.resetMasterPasswordWithRecovery(
        recoveryAnswer: _answerController.text,
        newPassword: _passwordController.text,
        meta: widget.meta,
      );

      if (!mounted) return;
      if (reset == null) {
        widget.backoff.registerFailure();
        final nextWait = widget.backoff.remaining;
        HapticFeedback.heavyImpact();
        setState(() {
          _busy = false;
          _error = nextWait > Duration.zero
              ? 'Wrong answer. Try again in ${nextWait.inSeconds + 1}s'
              : 'Wrong answer';
        });
        return;
      }

      widget.backoff.reset();
      await service.recordUnlock(reset.meta);
      ref.invalidate(vaultMetaProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      widget.controller.unlock(reset.vmk);
      unawaited(
        ref
            .read(vaultRepositoryProvider.notifier)
            .refreshSecurityFlags()
            .catchError((_) {}),
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Master password reset')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Recovery failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final question = widget.meta.recovery.question.trim();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recover vault',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                question.isEmpty
                    ? 'Answer your recovery question, then choose a new master password.'
                    : question,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _answerController,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                // K-14: recovery answer is equivalent in security weight to
                // the master password (it can decrypt the recovery-wrapped
                // VMK). Opt out of cross-app autofill.
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'Recovery answer',
                  prefixIcon: Icon(Icons.help_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: InputDecoration(
                  labelText: 'New master password',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 8) return 'Must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const <String>[],
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.check_rounded),
                ),
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.lock_reset_rounded),
                label: Text(_busy ? 'Recovering...' : 'Reset and unlock'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  final ColorScheme scheme;
  const _BrandMark({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final primary = scheme.primary;
    final tertiary = scheme.tertiary;

    return Center(
      child: Column(
        children: [
          RepaintBoundary(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, tertiary.withValues(alpha: 0.85)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.32),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.shield_rounded,
                size: 46,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'VaultSnap',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  final ColorScheme scheme;
  const _OrDivider({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = scheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: color, height: 1)),
      ],
    );
  }
}

class _PrivacyFooter extends StatelessWidget {
  final ColorScheme scheme;
  const _PrivacyFooter({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.2,
      height: 1.4,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Encrypted on this device · Nothing leaves your phone',
            style: style,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
