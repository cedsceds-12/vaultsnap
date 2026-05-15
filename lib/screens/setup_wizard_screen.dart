import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../providers/vault_setup_provider.dart';
import '../services/biometric_service.dart';
import '../widgets/password_strength_meter.dart';
import '../widgets/vault_lock_scope.dart';

/// First-time setup wizard — 3 steps:
///   1. Welcome (explains local-only, no cloud)
///   2. Create master password (+ confirm + strength meter)
///   3. Recovery question + answer
///
/// After the user completes step 3, the vault is initialized
/// (VMK generated, keys derived, everything wrapped and saved)
/// and the user lands on [HomeShell].
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  // Page 2 — password
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();
  bool _obscure = true;

  // Page 3 — recovery
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _confirmAnswerController = TextEditingController();
  final _recoveryFormKey = GlobalKey<FormState>();
  bool _obscureAnswer = true;

  // Page 4 — biometric (Phase 10)
  // [_biometricCapable] is asynchronously discovered in initState by
  // calling [BiometricService.isAvailable]. While the check is in
  // flight (typically <100ms), the page renders a spinner. Once
  // resolved, either: a "Set up biometric unlock" + Skip option (if
  // capable) OR an info card + Continue button (if not capable).
  // [_biometricRequested] captures the user's choice so the Summary
  // page knows what to enrol after vault creation.
  bool _biometricChecked = false;
  bool _biometricCapable = false;
  bool _biometricRequested = false;

  // Page 5 — summary / "Open vault"
  bool _creating = false;

  static const _totalPages = 5;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Lay out page 1 off the critical path: two synchronous jumps in one
    // post-frame tick materialize the adjacent page's subtree before the
    // user ever taps Forward — restores smooth slide without the first-hit
    // jank of a cold PageView.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Touch page 2 then return — lays out the whole strip once so the
      // first user-facing slides don't pay cold layout on every hop.
      _pageController.jumpToPage(2);
      _pageController.jumpToPage(0);
    });
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final svc = ref.read(biometricServiceProvider);
      final ok = await svc.isAvailable();
      if (!mounted) return;
      setState(() {
        _biometricChecked = true;
        _biometricCapable = ok;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricChecked = true;
        _biometricCapable = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _questionController.dispose();
    _answerController.dispose();
    _confirmAnswerController.dispose();
    super.dispose();
  }

  void _next() {
    // Page-specific validation gates.
    if (_currentPage == 1) {
      if (!_passwordFormKey.currentState!.validate()) return;
    }
    if (_currentPage == 2) {
      if (!_recoveryFormKey.currentState!.validate()) return;
    }
    if (_currentPage < _totalPages - 1) {
      final next = _currentPage + 1;
      setState(() => _currentPage = next);
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _back() {
    if (_currentPage > 0) {
      final prev = _currentPage - 1;
      setState(() => _currentPage = prev);
      _pageController.animateToPage(
        prev,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Final commit — runs from the Summary page's "Open vault" button.
  /// Creates the vault, unlocks it, and (if the user opted in on the
  /// biometric page) enrols biometric unlock right after. Phase 10:
  /// vault creation moved here from the Recovery page so the wizard
  /// can show a real summary screen first.
  Future<void> _finish() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      final setupService = await ref.read(vaultSetupServiceProvider.future);
      var meta = await setupService.createVault(
        masterPassword: _passwordController.text,
        recoveryQuestion: _questionController.text.trim(),
        recoveryAnswer: _answerController.text,
      );
      final vmk = await setupService.verifyPassword(
        masterPassword: _passwordController.text,
        meta: meta,
      );

      // Optional biometric enrolment. Failures are surfaced as a
      // toast but don't roll back vault creation — the user can
      // re-try from Settings → Biometric unlock.
      if (_biometricRequested && _biometricCapable && vmk != null) {
        try {
          final updated = await setupService.enableBiometric(
            meta: meta,
            vmk: vmk,
          );
          if (updated != null) meta = updated;
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Biometric enrolment failed — enable it later in Settings.',
                ),
              ),
            );
          }
        }
      }

      ref.invalidate(vaultMetaProvider);

      if (!mounted) return;
      if (vmk != null) {
        ref.read(vaultLockControllerProvider).unlock(vmk);
      }
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Setup failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: _StepIndicator(
                current: _currentPage,
                total: _totalPages,
                scheme: scheme,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                allowImplicitScrolling: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  RepaintBoundary(
                    child: _WelcomePage(onNext: _next),
                  ),
                  RepaintBoundary(
                    child: _PasswordPage(
                      formKey: _passwordFormKey,
                      passwordController: _passwordController,
                      confirmController: _confirmController,
                      obscure: _obscure,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onNext: _next,
                      onBack: _back,
                    ),
                  ),
                  RepaintBoundary(
                    child: _RecoveryPage(
                      formKey: _recoveryFormKey,
                      questionController: _questionController,
                      answerController: _answerController,
                      confirmAnswerController: _confirmAnswerController,
                      obscureAnswer: _obscureAnswer,
                      onToggleObscure: () =>
                          setState(() => _obscureAnswer = !_obscureAnswer),
                      onNext: _next,
                      onBack: _back,
                    ),
                  ),
                  RepaintBoundary(
                    child: _BiometricPage(
                      checked: _biometricChecked,
                      capable: _biometricCapable,
                      requested: _biometricRequested,
                      onToggle: (v) =>
                          setState(() => _biometricRequested = v),
                      onNext: _next,
                      onBack: _back,
                    ),
                  ),
                  RepaintBoundary(
                    child: _SummaryPage(
                      questionController: _questionController,
                      biometricRequested:
                          _biometricRequested && _biometricCapable,
                      creating: _creating,
                      onFinish: _finish,
                      onBack: _back,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  final ColorScheme scheme;

  const _StepIndicator({
    required this.current,
    required this.total,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: 4,
              decoration: BoxDecoration(
                color: active ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 1 — Welcome
// ---------------------------------------------------------------------------

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              RepaintBoundary(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary,
                        scheme.tertiary.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.32),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.shield_rounded,
                    size: 52,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Welcome to VaultSnap',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                'Everything stays on this device.\n'
                'No sign-ups. No cloud sync. Completely offline.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              _FeatureRow(
                icon: Icons.lock_outline_rounded,
                label: 'AES-256 encryption',
                scheme: scheme,
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: Icons.wifi_off_rounded,
                label: 'Zero internet permission',
                scheme: scheme,
              ),
              const SizedBox(height: 14),
              _FeatureRow(
                icon: Icons.fingerprint_rounded,
                label: 'Biometric unlock support',
                scheme: scheme,
              ),
              const SizedBox(height: 44),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Get started'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme scheme;

  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 2 — Create master password
// ---------------------------------------------------------------------------

class _PasswordPage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _PasswordPage({
    required this.formKey,
    required this.passwordController,
    required this.confirmController,
    required this.obscure,
    required this.onToggleObscure,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.lock_rounded,
                      size: 30,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create master password',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick something you won\'t forget.\n'
                  'This single password locks and unlocks everything.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  // K-14: opt out of cross-app autofill — see comment in
                  // VaultLockScope's master-password field. Setup-wizard
                  // creates the keystone credential, so the same hardening
                  // applies here.
                  autofillHints: const <String>[],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Master password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show' : 'Hide',
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 8) return 'At least 8 characters';
                    return null;
                  },
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: passwordController,
                  builder: (context, value, _) =>
                      PasswordStrengthMeter(password: value.text),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onNext(),
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: const Icon(Icons.check_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Show' : 'Hide',
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 3 — Recovery question
// ---------------------------------------------------------------------------

class _RecoveryPage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController questionController;
  final TextEditingController answerController;
  final TextEditingController confirmAnswerController;
  final bool obscureAnswer;
  final VoidCallback onToggleObscure;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _RecoveryPage({
    required this.formKey,
    required this.questionController,
    required this.answerController,
    required this.confirmAnswerController,
    required this.obscureAnswer,
    required this.onToggleObscure,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 30,
                      color: scheme.tertiary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Set up recovery',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a question only you can answer.\n'
                  'This is your backup if you forget your password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                _RecoveryQuestionField(controller: questionController),
                const SizedBox(height: 16),
                TextFormField(
                  controller: answerController,
                  obscureText: obscureAnswer,
                  autocorrect: false,
                  enableSuggestions: false,
                  // K-14: recovery answer is equivalent in security weight
                  // to the master password — opt out of cross-app autofill.
                  autofillHints: const <String>[],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Answer',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscureAnswer ? 'Show' : 'Hide',
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscureAnswer
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (v.trim().length < 2) return 'Too short';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmAnswerController,
                  obscureText: obscureAnswer,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onNext(),
                  decoration: InputDecoration(
                    labelText: 'Confirm answer',
                    prefixIcon: const Icon(Icons.check_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscureAnswer ? 'Show' : 'Hide',
                      onPressed: onToggleObscure,
                      icon: Icon(
                        obscureAnswer
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') !=
                        answerController.text
                            .trim()
                            .toLowerCase()
                            .replaceAll(RegExp(r'\s+'), ' ')) {
                      return 'Answers do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'If you lose both your password and this answer, '
                            'your vault cannot be recovered. Keep them safe.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recovery question — curated dropdown + custom-text fallback
// ---------------------------------------------------------------------------

/// Curated recovery questions for the setup wizard. Dropdown picker
/// above a free-text fallback. Writes the selected (or typed) text
/// straight to the supplied [controller] so the existing form
/// validation + `RecoveryMeta.question` storage works unchanged.
class _RecoveryQuestionField extends StatefulWidget {
  final TextEditingController controller;
  const _RecoveryQuestionField({required this.controller});

  @override
  State<_RecoveryQuestionField> createState() =>
      _RecoveryQuestionFieldState();
}

class _RecoveryQuestionFieldState extends State<_RecoveryQuestionField> {
  static const _custom = '__custom__';

  // 9 curated + a "Custom question…" option. Picked for being personal,
  // hard to look up on social media, and not present in the common
  // 2024 phishing wordlists. Free-text is still available via the
  // last option for users with their own preferred prompt.
  static const _presets = <String>[
    'What was the name of your first pet?',
    'In what city were you born?',
    'What was your childhood nickname?',
    'What is the name of your favourite childhood teacher?',
    'What was the make of your first car?',
    "What is your father's middle name?",
    'In what city did your parents meet?',
    'What is the name of the street you grew up on?',
    'What was the name of your first school?',
  ];

  String? _selected;

  @override
  void initState() {
    super.initState();
    // If the form opens with a question pre-set (e.g. user navigated
    // back from a later page) match it to a preset, else fall to
    // custom. First-time setup gets the first preset by default so
    // the form validates without requiring user interaction.
    final cur = widget.controller.text.trim();
    if (cur.isNotEmpty && _presets.contains(cur)) {
      _selected = cur;
    } else if (cur.isNotEmpty) {
      _selected = _custom;
    } else {
      _selected = _presets.first;
      widget.controller.text = _presets.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selected,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Security question',
            prefixIcon: Icon(Icons.quiz_outlined),
          ),
          items: [
            for (final q in _presets)
              DropdownMenuItem(
                value: q,
                child: Text(q, overflow: TextOverflow.ellipsis),
              ),
            const DropdownMenuItem(
              value: _custom,
              child: Text('Custom question…'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selected = v);
            if (v != _custom) {
              widget.controller.text = v;
            } else {
              widget.controller.text = '';
            }
          },
        ),
        if (_selected == _custom) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: widget.controller,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Your question',
              hintText: 'Pick something only you would know',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.trim().length < 5) return 'Too short';
              return null;
            },
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Page 4 — Biometric (Phase 10)
// ---------------------------------------------------------------------------

/// Optional biometric-unlock enrolment. Renders a spinner until the
/// async [BiometricService.isAvailable] check resolves, then either
/// the toggle (capable) or an "unavailable" info card (not capable).
/// User's choice flows back via [onToggle]; the actual enrolment
/// happens in the wizard's `_finish()` after vault creation.
class _BiometricPage extends StatelessWidget {
  final bool checked;
  final bool capable;
  final bool requested;
  final ValueChanged<bool> onToggle;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _BiometricPage({
    required this.checked,
    required this.capable,
    required this.requested,
    required this.onToggle,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.fingerprint_rounded,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Biometric unlock',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Use your fingerprint or face to unlock VaultSnap '
                'instead of typing your master password every time. '
                'You can always fall back to the password.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (!checked)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!capable)
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Biometric unlock isn\'t available on this '
                          'device — either no fingerprint / face is '
                          'enrolled in your phone settings, or the '
                          'hardware doesn\'t support it. You can still '
                          'enable it later from Settings.',
                          style:
                              theme.textTheme.bodySmall?.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SwitchListTile.adaptive(
                  value: requested,
                  onChanged: onToggle,
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.fingerprint_rounded,
                    color: scheme.primary,
                  ),
                  title: const Text('Enable biometric unlock'),
                  subtitle: const Text(
                    'You\'ll be prompted to authenticate after vault setup',
                  ),
                ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Continue'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Page 5 — Summary / "Open vault"
// ---------------------------------------------------------------------------

/// Final wizard page. Lists every setup decision the user just made
/// with a check / dash mark, then commits — calls `_finish()` to run
/// vault creation + (optionally) biometric enrolment + auto-unlock.
class _SummaryPage extends StatelessWidget {
  final TextEditingController questionController;
  final bool biometricRequested;
  final bool creating;
  final Future<void> Function() onFinish;
  final VoidCallback onBack;

  const _SummaryPage({
    required this.questionController,
    required this.biometricRequested,
    required this.creating,
    required this.onFinish,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 32,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "You're all set",
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Tap below to create your vault and get started.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _SummaryRow(
                icon: Icons.lock_outline_rounded,
                title: 'Master password set',
                body: 'Argon2id-derived. We never store the password itself.',
                ok: true,
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.help_outline_rounded,
                title: 'Recovery question chosen',
                body:
                    '"${questionController.text.trim()}". Used if you forget '
                    'the master password — cannot be reset.',
                ok: true,
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.fingerprint_rounded,
                title: 'Biometric unlock',
                body: biometricRequested
                    ? "You'll authenticate right after vault setup."
                    : 'Skipped — you can enable it later in Settings.',
                ok: biometricRequested,
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.cloud_off_rounded,
                title: 'Local-only storage',
                body:
                    'Your vault never touches the internet. Confirmed by the '
                    'missing INTERNET permission.',
                ok: true,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: creating ? null : () => onFinish(),
                icon: creating
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(creating ? 'Creating vault…' : 'Open vault'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: creating ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool ok;

  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.remove_circle_outline,
            color: ok ? const Color(0xFF22C55E) : scheme.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
