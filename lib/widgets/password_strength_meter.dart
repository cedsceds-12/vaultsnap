import 'package:flutter/material.dart';

/// Lightweight visual heuristic — NOT a real strength estimate.
/// Real implementation should use zxcvbn (or similar) once logic is added.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  const PasswordStrengthMeter({super.key, required this.password});

  static const _labels = ['Too short', 'Weak', 'Fair', 'Good', 'Strong'];
  static const _colors = [
    Color(0xFF9CA3AF),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF22C55E),
  ];

  int get _score {
    if (password.isEmpty) return 0;
    if (password.length < 6) return 0;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 14) score++;
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasNum = password.contains(RegExp(r'[0-9]'));
    final hasSym = password.contains(RegExp(r'[^A-Za-z0-9]'));
    final classes =
        [hasLower, hasUpper, hasNum, hasSym].where((b) => b).length;
    if (classes >= 2) score++;
    if (classes >= 4) score++;
    if (score > 4) score = 4;
    return score;
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final scheme = Theme.of(context).colorScheme;
    final color = _colors[score];
    final label = _labels[score];

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final active = i < score;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: 4,
                    decoration: BoxDecoration(
                      color: active
                          ? color
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                score >= 3
                    ? Icons.check_circle_rounded
                    : score >= 1
                        ? Icons.error_outline_rounded
                        : Icons.info_outline_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 6),
              if (password.isNotEmpty)
                Text(
                  '· ${password.length} chars',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
