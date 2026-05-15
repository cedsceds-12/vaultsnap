import 'package:flutter/material.dart';

/// Shared modal-sheet wrapper tuned for keyboard-heavy security forms.
///
/// The child is passed in pre-built so keyboard inset changes only animate a
/// lightweight padding wrapper instead of rebuilding every text field.
Future<T?> showVaultBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool showDragHandle = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    showDragHandle: showDragHandle,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final reduceMotion = MediaQuery.disableAnimationsOf(sheetContext);
      final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return AnimatedPadding(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: RepaintBoundary(child: child),
      );
    },
  );
}
