import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/vault_providers.dart';
import '../services/password_generator_service.dart';
import '../widgets/large_page_header.dart';
import '../widgets/vault_toast.dart';

class PasswordGeneratorScreen extends ConsumerStatefulWidget {
  /// When [pickerMode] is true, the screen is opened from Add/Edit entry
  /// and exposes a "Use this password" button that pops a String result.
  final bool pickerMode;
  const PasswordGeneratorScreen({super.key, this.pickerMode = false});

  @override
  ConsumerState<PasswordGeneratorScreen> createState() =>
      _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState
    extends ConsumerState<PasswordGeneratorScreen> {
  static const int _minLength = 8;
  static const int _maxLength = 64;

  final _generator = PasswordGenerator();
  final _symbolsController =
      TextEditingController(text: PasswordGenerator.defaultSymbols);

  double _length = 18;
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;

  String _preview = '';

  @override
  void initState() {
    super.initState();
    _preview = _generate();
  }

  @override
  void dispose() {
    _symbolsController.dispose();
    super.dispose();
  }

  String _generate() {
    return _generator.generate(
      length: _length.round(),
      useLowercase: _lowercase,
      useUppercase: _uppercase,
      useDigits: _numbers,
      useSymbols: _symbols,
      customSymbols: _symbolsController.text,
    );
  }

  void _regenerate() {
    HapticFeedback.selectionClick();
    setState(() => _preview = _generate());
  }

  void _refreshPreview() {
    setState(() => _preview = _generate());
  }

  Future<void> _copy() async {
    if (_preview.isEmpty) return;
    await ref.read(clipboardServiceProvider).copyAndScheduleClear(_preview);
    if (!mounted) return;
    VaultToast.show(
      context,
      'Password copied · auto-clear in 30s',
      icon: Icons.content_copy_rounded,
      duration: const Duration(milliseconds: 1400),
    );
  }

  bool get _canGenerate {
    if (!(_lowercase || _uppercase || _numbers || _symbols)) return false;
    if (_symbols && !(_lowercase || _uppercase || _numbers)) {
      return _symbolsController.text.trim().isNotEmpty;
    }
    return true;
  }

  ({String label, Color color}) _strengthOf(String value) {
    if (value.isEmpty) return (label: 'Weak', color: const Color(0xFFEF4444));
    final classes = [
      RegExp(r'[a-z]').hasMatch(value),
      RegExp(r'[A-Z]').hasMatch(value),
      RegExp(r'[0-9]').hasMatch(value),
      RegExp(r'[^A-Za-z0-9]').hasMatch(value),
    ].where((b) => b).length;

    if (value.length >= 16 && classes >= 3) {
      return (label: 'Strong', color: const Color(0xFF22C55E));
    }
    if (value.length >= 12 && classes >= 2) {
      return (label: 'Good', color: const Color(0xFF10B981));
    }
    return (label: 'Weak', color: const Color(0xFFEF4444));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strength = _strengthOf(_preview);

    if (widget.pickerMode) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Generator'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: _buildBody(scheme, strength.label, strength.color),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const LargePageHeader(title: 'Generator'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverList.list(
              children: _buildBody(scheme, strength.label, strength.color),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(
    ColorScheme scheme,
    String strength,
    Color strengthColor,
  ) {
    return [
      _PasswordPreviewCard(
        value: _preview,
        onCopy: _copy,
        onRegenerate: _regenerate,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: strengthColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            strength,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: strengthColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 6),
          Text(
            '· ${_length.round()} chars',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Length',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    '${_length.round()}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
              Slider(
                value: _length,
                min: _minLength.toDouble(),
                max: _maxLength.toDouble(),
                divisions: _maxLength - _minLength,
                label: _length.round().toString(),
                onChanged: (v) {
                  setState(() => _length = v);
                  _refreshPreview();
                },
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            _OptionTile(
              icon: Icons.text_fields_rounded,
              title: 'Uppercase letters',
              subtitle: 'A–Z',
              value: _uppercase,
              onChanged: (v) {
                setState(() => _uppercase = v);
                _refreshPreview();
              },
            ),
            _divider(scheme),
            _OptionTile(
              icon: Icons.text_format_rounded,
              title: 'Lowercase letters',
              subtitle: 'a–z',
              value: _lowercase,
              onChanged: (v) {
                setState(() => _lowercase = v);
                _refreshPreview();
              },
            ),
            _divider(scheme),
            _OptionTile(
              icon: Icons.tag_rounded,
              title: 'Numbers',
              subtitle: '0–9',
              value: _numbers,
              onChanged: (v) {
                setState(() => _numbers = v);
                _refreshPreview();
              },
            ),
            _divider(scheme),
            _OptionTile(
              icon: Icons.alternate_email_rounded,
              title: 'Symbols',
              subtitle: 'Customize the set below',
              value: _symbols,
              onChanged: (v) {
                setState(() => _symbols = v);
                _refreshPreview();
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              child: _symbols
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: TextField(
                        controller: _symbolsController,
                        decoration: InputDecoration(
                          labelText: 'Allowed symbols',
                          prefixIcon: const Icon(Icons.attach_file_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Reset',
                            icon: const Icon(Icons.restart_alt_rounded),
                            onPressed: () {
                              _symbolsController.text =
                                  PasswordGenerator.defaultSymbols;
                              _refreshPreview();
                            },
                          ),
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontFeatures: [FontFeature.tabularFigures()],
                          letterSpacing: 1.2,
                        ),
                        onChanged: (_) => _refreshPreview(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (widget.pickerMode)
        FilledButton.icon(
          onPressed: _canGenerate && _preview.isNotEmpty
              ? () => Navigator.of(context).pop(_preview)
              : null,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Use this password'),
        )
      else
        FilledButton.icon(
          onPressed: _canGenerate && _preview.isNotEmpty ? _copy : null,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy password'),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _canGenerate ? _regenerate : null,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Regenerate'),
      ),
    ];
  }

  Widget _divider(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(left: 60),
        child: Divider(
          height: 1,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      );
}

class _PasswordPreviewCard extends StatelessWidget {
  final String value;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;

  const _PasswordPreviewCard({
    required this.value,
    required this.onCopy,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEmpty = value.isEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.16),
            scheme.tertiary.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pick at least one character set',
                style: TextStyle(
                  fontSize: 16,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            SelectableText(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFeatures: [FontFeature.tabularFigures()],
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                height: 1.3,
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              IconButton.filledTonal(
                onPressed: isEmpty ? null : onCopy,
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: isEmpty ? null : onRegenerate,
                tooltip: 'Regenerate',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: scheme.primary),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle),
    );
  }
}
