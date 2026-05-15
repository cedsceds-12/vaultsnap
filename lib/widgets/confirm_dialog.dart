import 'package:flutter/material.dart';

/// Reusable Material 3 confirmation dialog.
///
/// Non-destructive: standard side-by-side actions.
/// Destructive: stacked full-width buttons (confirm on top, cancel below)
/// with extra breathing room between the message and the action area —
/// the layout iOS/Telegram use for "are you sure" prompts.
///
/// Returns true if the user confirms.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.warning_amber_rounded,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final accent = destructive ? scheme.error : scheme.primary;

  final result = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (context) {
      // Custom Dialog (instead of AlertDialog) gives us full control over
      // the spacing between content and actions — AlertDialog clamps
      // actionsPadding tighter than what looks premium for destructive
      // confirmations.
      return Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: accent, size: 30),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
                // Generous breathing room between the message and the
                // action area — this is what makes destructive prompts
                // feel calm and intentional rather than cramped.
                const SizedBox(height: 28),
                if (destructive)
                  _StackedActions(
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
                    accent: accent,
                    onConfirmColor: scheme.onError,
                  )
                else
                  _SideBySideActions(
                    confirmLabel: confirmLabel,
                    cancelLabel: cancelLabel,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _StackedActions extends StatelessWidget {
  final String confirmLabel;
  final String cancelLabel;
  final Color accent;
  final Color onConfirmColor;

  const _StackedActions({
    required this.confirmLabel,
    required this.cancelLabel,
    required this.accent,
    required this.onConfirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: onConfirmColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(context).colorScheme.onSurfaceVariant,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
        ),
      ],
    );
  }
}

class _SideBySideActions extends StatelessWidget {
  final String confirmLabel;
  final String cancelLabel;

  const _SideBySideActions({
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }
}
