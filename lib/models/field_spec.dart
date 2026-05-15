import 'package:flutter/material.dart';

import 'password_entry.dart';

/// Different visual/keyboard treatments a form field can take.
enum FieldType {
  text,
  email,
  password,
  pin,
  url,
  multiline,
  date,
  number,
  cardNumber,
  expiry,
  select,
}

/// Declarative description of a single form field for the Add/Edit screen.
/// The renderer in [AddEditEntryScreen] reads a `List<FieldSpec>` for the
/// currently-selected category and builds the appropriate input widget.
@immutable
class FieldSpec {
  final String key;
  final String label;
  final String? hint;
  final IconData icon;
  final FieldType type;

  /// Used for [FieldType.select].
  final List<String>? options;

  /// True if this field is required for validation.
  final bool required;

  /// Allow the password generator button on password-type fields.
  final bool generator;

  /// Hide this field behind the editor's "Advanced (optional)" expander.
  /// Used for fields most users never touch — TOTP algorithm/digits/period
  /// are the canonical case (defaults cover ~99% of issuers; users only
  /// override when adding a Steam / Microsoft / 8-digit / 60s entry).
  final bool advanced;

  /// Whether to render the password-strength meter beneath this field
  /// when [type] is [FieldType.password]. Default true (matches the
  /// existing behaviour for login / wifi passwords). Set to false for
  /// secrets that aren't user-chosen — TOTP base32 secrets are 80- or
  /// 160-bit random, so a strength meter against them is meaningless
  /// and visually noisy.
  final bool showStrengthMeter;

  const FieldSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.type,
    this.hint,
    this.options,
    this.required = false,
    this.generator = false,
    this.advanced = false,
    this.showStrengthMeter = true,
  });
}

/// Field schemas per category. Common keys (`name`, `password`, `notes`)
/// are reused across categories so values are preserved when the user
/// switches the category in the Add/Edit screen.
class CategoryFields {
  static List<FieldSpec> forCategory(EntryCategory c) {
    switch (c) {
      case EntryCategory.login:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. GitHub',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'username',
            label: 'Username or email',
            hint: 'you@example.com',
            icon: Icons.alternate_email_rounded,
            type: FieldType.email,
          ),
          FieldSpec(
            key: 'password',
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            type: FieldType.password,
            generator: true,
          ),
          FieldSpec(
            key: 'url',
            label: 'Website',
            hint: 'example.com',
            icon: Icons.public_rounded,
            type: FieldType.url,
          ),
          FieldSpec(
            key: 'notes',
            label: 'Notes',
            hint: 'Recovery codes, security questions, etc.',
            icon: Icons.notes_rounded,
            type: FieldType.multiline,
          ),
        ];

      case EntryCategory.card:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Card name',
            hint: 'e.g. Travel Visa',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'cardholder',
            label: 'Cardholder name',
            hint: 'JOHN DOE',
            icon: Icons.person_outline_rounded,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'number',
            label: 'Card number',
            hint: '1234 5678 9012 3456',
            icon: Icons.credit_card_rounded,
            type: FieldType.cardNumber,
          ),
          FieldSpec(
            key: 'expiry',
            label: 'Expiry',
            hint: 'MM/YY',
            icon: Icons.calendar_month_rounded,
            type: FieldType.expiry,
          ),
          FieldSpec(
            key: 'cvv',
            label: 'CVV',
            hint: '•••',
            icon: Icons.vpn_key_outlined,
            type: FieldType.pin,
          ),
          FieldSpec(
            key: 'pin',
            label: 'PIN',
            hint: '••••',
            icon: Icons.dialpad_rounded,
            type: FieldType.pin,
          ),
          FieldSpec(
            key: 'notes',
            label: 'Notes',
            icon: Icons.notes_rounded,
            type: FieldType.multiline,
          ),
        ];

      case EntryCategory.identity:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Title',
            hint: 'e.g. Driver\'s licence',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'fullName',
            label: 'Full name',
            hint: 'As shown on document',
            icon: Icons.badge_outlined,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'documentType',
            label: 'Document type',
            icon: Icons.description_outlined,
            type: FieldType.select,
            options: [
              'Passport',
              'Driver\'s licence',
              'National ID',
              'Social security',
              'Tax ID',
              'Other',
            ],
          ),
          FieldSpec(
            key: 'documentNumber',
            label: 'Document number',
            hint: 'Number / reference',
            icon: Icons.numbers_rounded,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'dateOfBirth',
            label: 'Date of birth',
            icon: Icons.cake_outlined,
            type: FieldType.date,
          ),
          FieldSpec(
            key: 'issued',
            label: 'Issued',
            icon: Icons.event_available_outlined,
            type: FieldType.date,
          ),
          FieldSpec(
            key: 'expires',
            label: 'Expires',
            icon: Icons.event_busy_outlined,
            type: FieldType.date,
          ),
          FieldSpec(
            key: 'notes',
            label: 'Notes',
            icon: Icons.notes_rounded,
            type: FieldType.multiline,
          ),
        ];

      case EntryCategory.note:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Title',
            hint: 'e.g. Recovery codes',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'content',
            label: 'Content',
            hint: 'Type your secure note here…',
            icon: Icons.edit_note_rounded,
            type: FieldType.multiline,
          ),
        ];

      case EntryCategory.wifi:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. Home Wi-Fi',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'ssid',
            label: 'Network (SSID)',
            hint: 'MyNetwork',
            icon: Icons.wifi_rounded,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'password',
            label: 'Wi-Fi password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            type: FieldType.password,
            generator: true,
          ),
          FieldSpec(
            key: 'notes',
            label: 'Notes',
            icon: Icons.notes_rounded,
            type: FieldType.multiline,
          ),
        ];

      case EntryCategory.totp:
        return const [
          FieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. GitHub 2FA',
            icon: Icons.label_outline_rounded,
            type: FieldType.text,
            required: true,
          ),
          FieldSpec(
            key: 'issuer',
            label: 'Issuer',
            hint: 'e.g. GitHub',
            icon: Icons.business_outlined,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'account',
            label: 'Account',
            hint: 'you@example.com',
            icon: Icons.person_outline_rounded,
            type: FieldType.text,
          ),
          FieldSpec(
            key: 'secret',
            label: 'Secret Code',
            hint: 'JBSWY3DPEHPK3PXP',
            icon: Icons.vpn_key_outlined,
            type: FieldType.password,
            required: true,
            // TOTP secrets are random bytes — a strength meter on them
            // is meaningless and clutters the form.
            showStrengthMeter: false,
          ),
          FieldSpec(
            key: 'algorithm',
            label: 'Algorithm',
            icon: Icons.functions_rounded,
            type: FieldType.select,
            options: ['SHA1', 'SHA256', 'SHA512'],
            advanced: true,
          ),
          FieldSpec(
            key: 'digits',
            label: 'Digits',
            icon: Icons.pin_outlined,
            type: FieldType.select,
            options: ['6', '8'],
            advanced: true,
          ),
          FieldSpec(
            key: 'period',
            label: 'Period (seconds)',
            icon: Icons.timer_outlined,
            type: FieldType.select,
            options: ['30', '60'],
            advanced: true,
          ),
          FieldSpec(
            key: 'notes',
            label: 'Notes',
            icon: Icons.notes_rounded,
            type: FieldType.multiline,
          ),
        ];
    }
  }
}
