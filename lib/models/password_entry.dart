import 'package:flutter/material.dart';

enum EntryCategory {
  login('Login', Icons.lock_outline_rounded, Color(0xFF0EA5E9)),
  card('Card', Icons.credit_card_rounded, Color(0xFF8B5CF6)),
  identity('Identity', Icons.badge_outlined, Color(0xFFF59E0B)),
  note('Secure note', Icons.sticky_note_2_outlined, Color(0xFF10B981)),
  wifi('Wi-Fi', Icons.wifi_rounded, Color(0xFFEC4899)),
  totp('Authenticator', Icons.shield_moon_outlined, Color(0xFF06B6D4));

  final String label;
  final IconData icon;
  final Color accent;
  const EntryCategory(this.label, this.icon, this.accent);
}

enum PasswordStrength { weak, fair, good, strong }
