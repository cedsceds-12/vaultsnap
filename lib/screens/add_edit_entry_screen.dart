import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/field_spec.dart';
import '../models/password_entry.dart';
import '../models/vault_entry.dart';
import '../providers/vault_locked_error.dart';
import '../providers/vault_repository_provider.dart';
import '../services/autofill_session_service.dart';
import '../services/totp_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/password_strength_meter.dart';
import '../widgets/vault_bottom_sheet.dart';
import '../widgets/vault_toast.dart';
import 'password_generator_screen.dart';

class AddEditEntryScreen extends ConsumerStatefulWidget {
  final VaultEntry? entry;
  final EntryCategory? initialCategory;
  const AddEditEntryScreen({super.key, this.entry, this.initialCategory});

  @override
  ConsumerState<AddEditEntryScreen> createState() => _AddEditEntryScreenState();
}

class _AddEditEntryScreenState extends ConsumerState<AddEditEntryScreen> {
  final _formKey = GlobalKey<FormState>();

  late EntryCategory _category;
  late List<FieldSpec> _fields;

  /// Long-lived controllers, lazily created per field key. Never disposed
  /// until the screen is torn down. Avoids the dispose+recreate churn that
  /// caused the category-switch animation to stutter and lose focus.
  final Map<String, TextEditingController> _controllers = {};

  /// Per-field obscure toggles (password / pin / cvv).
  final Map<String, bool> _obscure = {};

  /// Per-field GlobalKeys so we can `Scrollable.ensureVisible` to a field
  /// that failed validation — used by the missing-required-field toast so
  /// the user is taken straight to the offending input.
  final Map<String, GlobalKey> _fieldKeys = {};

  /// Single package for Android autofill (login only). No text field.
  String? _linkedAndroidPackage;
  String? _linkedAndroidLabel;
  Uint8List? _linkedAndroidIconPng;

  @override
  void initState() {
    super.initState();
    _category = widget.entry?.category
        ?? widget.initialCategory
        ?? EntryCategory.login;

    _fields = CategoryFields.forCategory(_category);
    _ensureControllers();

    if (widget.entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadExistingEntry();
      });
    }
  }

  Future<void> _loadExistingEntry() async {
    final e = widget.entry;
    if (e == null || !mounted) return;
    try {
      final map = await ref
          .read(vaultRepositoryProvider.notifier)
          .decryptEntryPayload(e);
      if (!mounted) return;
      setState(() {
        for (final kv in map.entries) {
          _controllers.putIfAbsent(kv.key, TextEditingController.new);
          _controllers[kv.key]!.text = kv.value;
        }
        for (final spec in CategoryFields.forCategory(_category)) {
          if (_isSensitive(spec.type)) {
            _obscure.putIfAbsent(spec.key, () => true);
          }
        }
        final pkgs = e.androidPackages;
        if (pkgs.isNotEmpty) {
          _linkedAndroidPackage = pkgs.first;
          _linkedAndroidLabel = null;
          _linkedAndroidIconPng = null;
        }
      });
      final pkg = _linkedAndroidPackage;
      if (pkg != null && Platform.isAndroid) {
        unawaited(_hydrateLinkedAndroidFromPackage(pkg));
      }
    } catch (_) {
      if (!mounted) return;
      VaultToast.showError(context, 'Could not load entry');
    }
  }

  /// Lazily create controllers for the visible category. Existing controllers
  /// are reused so shared keys (name/username/notes/password) preserve text
  /// across category switches.
  void _ensureControllers() {
    for (final f in _fields) {
      _controllers.putIfAbsent(f.key, TextEditingController.new);
      if (_isSensitive(f.type)) {
        _obscure.putIfAbsent(f.key, () => true);
      }
    }
  }

  bool _isSensitive(FieldType t) =>
      t == FieldType.password || t == FieldType.pin;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isEdit => widget.entry != null;

  void _changeCategory(EntryCategory c) {
    if (c == _category) return;
    setState(() {
      _category = c;
      _fields = CategoryFields.forCategory(c);
      if (c != EntryCategory.login) {
        _linkedAndroidPackage = null;
        _linkedAndroidLabel = null;
        _linkedAndroidIconPng = null;
      }
      _ensureControllers();
    });
  }

  /// Returns the first required field whose value is blank, or `null` if
  /// every required field has a value. Used to surface a toast that names
  /// the missing field so the user doesn't have to scroll back up to find
  /// the inline form-validation error.
  FieldSpec? _firstMissingRequired() {
    for (final spec in _fields) {
      if (!spec.required) continue;
      final value = _controllers[spec.key]?.text.trim() ?? '';
      if (value.isEmpty) return spec;
    }
    return null;
  }

  void _scrollToField(String key) {
    final ctx = _fieldKeys[key]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.15,
    );
  }

  void _showMissingFieldToast(FieldSpec spec) {
    VaultToast.showError(context, '${spec.label} is required');
  }

  Future<void> _save() async {
    final missing = _firstMissingRequired();
    if (missing != null) {
      HapticFeedback.heavyImpact();
      _showMissingFieldToast(missing);
      _scrollToField(missing.key);
      // Trigger inline error on the field as well.
      _formKey.currentState?.validate();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    final fields = <String, String>{};
    for (final spec in CategoryFields.forCategory(_category)) {
      fields[spec.key] = _controllers[spec.key]?.text ?? '';
    }
    if (_category == EntryCategory.login) {
      fields['android_packages'] = _linkedAndroidPackage ?? '';
    }
    if (_category == EntryCategory.login) {
      final totp = _controllers['totp']?.text.trim() ?? '';
      if (totp.isNotEmpty) {
        fields['totp'] = totp;
      }
    }

    try {
      if (_isEdit) {
        await ref.read(vaultRepositoryProvider.notifier).updateEntry(
              existing: widget.entry!,
              category: _category,
              fields: fields,
            );
      } else {
        await ref.read(vaultRepositoryProvider.notifier).addEntry(
              category: _category,
              fields: fields,
            );
      }
    } on VaultLockedError {
      if (!mounted) return;
      VaultToast.showError(context, 'Unlock the vault first');
      return;
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Save failed: $e');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    VaultToast.showSuccess(
      context,
      _isEdit ? 'Entry updated' : 'Entry created',
    );
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete entry?',
      message:
          'This will permanently remove “${_controllers['name']?.text ?? widget.entry?.name ?? ''}” from this device. This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(vaultRepositoryProvider.notifier)
          .deleteEntry(widget.entry!.id);
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Delete failed: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    VaultToast.show(
      context,
      'Entry deleted',
      icon: Icons.delete_outline_rounded,
    );
  }

  Future<void> _hydrateLinkedAndroidFromPackage(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      final apps = await AutofillSessionService.queryLaunchableApps();
      if (!mounted) return;
      LaunchableApp? found;
      for (final a in apps) {
        if (a.packageName == packageName) {
          found = a;
          break;
        }
      }
      if (found == null || !mounted) return;
      final resolved = found;
      setState(() {
        _linkedAndroidLabel = resolved.label;
        _linkedAndroidIconPng = resolved.iconPng;
      });
    } catch (_) {
      // Uninstalled or launcher query failed — keep package name only.
    }
  }

  Future<void> _pickLinkedAndroidApp() async {
    if (!Platform.isAndroid) return;
    if (!mounted) return;
    // Goes through showVaultBottomSheet so the keyboard-inset animation is
    // handled by the wrapper's single AnimatedPadding + RepaintBoundary —
    // the picker child must NOT read MediaQuery.viewInsetsOf or it'll
    // rebuild the FutureBuilder + ListView every keyboard frame.
    final picked = await showVaultBottomSheet<LaunchableApp>(
      context: context,
      child: const _LinkedAndroidAppPickerSheet(),
    );
    if (picked != null && mounted) {
      setState(() {
        _linkedAndroidPackage = picked.packageName;
        _linkedAndroidLabel = picked.label;
        _linkedAndroidIconPng = picked.iconPng;
      });
    }
  }

  void _clearLinkedAndroidApp() {
    setState(() {
      _linkedAndroidPackage = null;
      _linkedAndroidLabel = null;
      _linkedAndroidIconPng = null;
    });
  }

  Future<void> _openGenerator(String fieldKey) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PasswordGeneratorScreen(pickerMode: true),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      _controllers[fieldKey]?.text = result;
    }
  }

  Future<void> _pickDate(String fieldKey) async {
    final initial = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _controllers[fieldKey]?.text = formatted;
    }
  }

  /// Reads `otpauth://` text from the system clipboard, parses it, and
  /// auto-populates the TOTP fields. Designed so the user can copy the URI
  /// from any other authenticator (Aegis, andOTP, 2FAS) and skip manual
  /// entry. Re-encodes the secret as base32 (capital letters) before
  /// writing into the field — the parser stores raw bytes internally.
  Future<void> _pasteOtpauthUri() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      VaultToast.showError(context, 'Clipboard is empty');
      return;
    }
    final spec = TotpService.parseUri(text);
    if (spec == null) {
      if (!mounted) return;
      VaultToast.showError(context, 'Not a valid otpauth:// URI');
      return;
    }
    if (!mounted) return;
    setState(() {
      _controllers['secret']?.text = _encodeBase32(spec.secret);
      if (spec.issuer != null && (spec.issuer ?? '').isNotEmpty) {
        _controllers['issuer']?.text = spec.issuer!;
      }
      if (spec.account != null && (spec.account ?? '').isNotEmpty) {
        _controllers['account']?.text = spec.account!;
      }
      _controllers['algorithm']?.text = switch (spec.algorithm) {
        TotpAlgorithm.sha1 => 'SHA1',
        TotpAlgorithm.sha256 => 'SHA256',
        TotpAlgorithm.sha512 => 'SHA512',
      };
      _controllers['digits']?.text = spec.digits.toString();
      _controllers['period']?.text = spec.period.toString();
      // Default the entry name to issuer · account if both unfilled.
      final nameCtl = _controllers['name'];
      if (nameCtl != null && nameCtl.text.trim().isEmpty) {
        final n = spec.issuer ?? spec.account ?? '';
        if (n.isNotEmpty) nameCtl.text = n;
      }
    });
    HapticFeedback.lightImpact();
    VaultToast.showSuccess(context, 'otpauth:// URI loaded');
  }

  static String _encodeBase32(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    if (bytes.isEmpty) return '';
    final buf = StringBuffer();
    var carry = 0;
    var bits = 0;
    for (final b in bytes) {
      carry = (carry << 8) | (b & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        buf.write(alphabet[(carry >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      buf.write(alphabet[(carry << (5 - bits)) & 0x1f]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit entry' : 'New entry'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: RepaintBoundary(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _CategoryPicker(
                value: _category,
                onChanged: _changeCategory,
              ),
              const SizedBox(height: 24),
              if (_category == EntryCategory.totp) ...[
                _OtpauthPasteCard(onPaste: _pasteOtpauthUri),
                const SizedBox(height: 18),
              ],
              // Category switch: use AnimatedSize for a smooth height change
              // and avoid the AnimatedSwitcher cross-fade. The previous
              // implementation kept TWO Columns mounted simultaneously during
              // the fade, both bound to the same shared TextEditingController
              // instances (name/password/notes are reused across categories) —
              // which trips the Flutter debug assertion "controller already
              // attached to another widget" and made the transition feel
              // laggy from the doubled rebuild cost.
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Builder(
                  key: ValueKey(_category),
                  builder: (context) {
                    // Primary fields render directly. `advanced: true`
                    // fields (TOTP algorithm/digits/period) are tucked
                    // under an ExpansionTile inserted *just before*
                    // Notes — that way the optional/quiet stuff sits
                    // between the meaningful fields and the free-form
                    // notes block instead of getting buried at the
                    // very bottom of the form.
                    final primary =
                        _fields.where((f) => !f.advanced).toList();
                    final advancedFields =
                        _fields.where((f) => f.advanced).toList();
                    final notesIdx =
                        primary.indexWhere((f) => f.key == 'notes');

                    final children = <Widget>[];
                    for (var i = 0; i < primary.length; i++) {
                      // Insert the Advanced expander right before the
                      // Notes field, if any. If there's no Notes field
                      // (e.g. categories without one), we drop the
                      // expander at the end further below.
                      if (i == notesIdx && advancedFields.isNotEmpty) {
                        children.add(_AdvancedSection(
                          fields: advancedFields,
                          buildField: _buildField,
                          fieldKeys: _fieldKeys,
                        ));
                      }
                      final spec = primary[i];
                      if (_category == EntryCategory.login &&
                          spec.key == 'url') {
                        children.add(KeyedSubtree(
                          key: _fieldKeys.putIfAbsent(
                            'url',
                            GlobalKey.new,
                          ),
                          child: _autofillSection(spec),
                        ));
                      } else {
                        children.add(KeyedSubtree(
                          key: _fieldKeys.putIfAbsent(
                            spec.key,
                            GlobalKey.new,
                          ),
                          child: _buildField(spec),
                        ));
                      }
                      children.add(const SizedBox(height: 18));
                    }
                    if (notesIdx < 0 && advancedFields.isNotEmpty) {
                      children.add(_AdvancedSection(
                        fields: advancedFields,
                        buildField: _buildField,
                        fieldKeys: _fieldKeys,
                      ));
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(_isEdit ? Icons.check_rounded : Icons.add_rounded),
                label: Text(_isEdit ? 'Save changes' : 'Add to vault'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Combined "Autofill matching" section shown for login entries. Groups the
  /// Android app picker and the website URL field into one visual unit so
  /// users understand both feed the same autofill engine. Renders the URL
  /// field as a normal `_buildField` for the supplied [urlSpec] so existing
  /// validation / formatting / save-path stays unchanged.
  Widget _autofillSection(FieldSpec urlSpec) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final showApp = Platform.isAndroid;

    return Container(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: isDark ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: isDark ? 0.32 : 0.20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Autofill matching',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            showApp
                ? 'Link an app and/or website so VaultSnap can fill this entry automatically.'
                : 'Add a website so VaultSnap can fill this entry automatically.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          if (showApp) ...[
            const _Label('App'),
            const SizedBox(height: 6),
            _appPickerRow(),
            const SizedBox(height: 16),
          ],
          _Label(urlSpec.label),
          const SizedBox(height: 6),
          _basicField(
            urlSpec,
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
        ],
      ),
    );
  }

  Widget _appPickerRow() {
    if (!Platform.isAndroid) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final pkg = _linkedAndroidPackage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => unawaited(_pickLinkedAndroidApp()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        _linkedAppLeading(scheme),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pkg == null
                              ? Text(
                                  'Choose app',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _linkedAndroidLabel ?? pkg,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    if (_linkedAndroidLabel != null)
                                      Text(
                                        pkg,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (pkg != null)
                IconButton(
                  tooltip: 'Remove app',
                  onPressed: _clearLinkedAndroidApp,
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linkedAppLeading(ColorScheme scheme) {
    final bytes = _linkedAndroidIconPng;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.apps_rounded,
            color: scheme.primary,
            size: 28,
          ),
        ),
      );
    }
    return Icon(Icons.apps_rounded, color: scheme.primary, size: 28);
  }

  Widget _buildField(FieldSpec spec) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(spec.label, required: spec.required),
        const SizedBox(height: 6),
        switch (spec.type) {
          FieldType.text => _basicField(spec),
          FieldType.email => _basicField(
              spec,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
          FieldType.url => _basicField(
              spec,
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          FieldType.number => _basicField(
              spec,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          FieldType.cardNumber => _basicField(
              spec,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
                _CardNumberFormatter(),
              ],
            ),
          FieldType.expiry => _basicField(
              spec,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
                _ExpiryFormatter(),
              ],
            ),
          FieldType.multiline => _multilineField(spec),
          FieldType.date => _dateField(spec),
          FieldType.password => _passwordField(spec),
          FieldType.pin => _passwordField(spec, numeric: true),
          FieldType.select => _selectField(spec),
        },
      ],
    );
  }

  TextFormField _basicField(
    FieldSpec spec, {
    TextInputType? keyboardType,
    bool autocorrect = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: _controllers[spec.key],
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      textCapitalization: spec.key == 'name' || spec.key == 'cardholder'
          ? TextCapitalization.words
          : TextCapitalization.sentences,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: spec.hint,
        prefixIcon: Icon(spec.icon),
      ),
      validator: spec.required
          ? (v) =>
              (v == null || v.trim().isEmpty) ? '${spec.label} is required' : null
          : null,
    );
  }

  TextFormField _multilineField(FieldSpec spec) {
    return TextFormField(
      controller: _controllers[spec.key],
      minLines: spec.key == 'content' ? 6 : 3,
      maxLines: spec.key == 'content' ? 14 : 6,
      decoration: InputDecoration(
        hintText: spec.hint,
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: Icon(spec.icon),
        ),
      ),
    );
  }

  Widget _dateField(FieldSpec spec) {
    return TextFormField(
      controller: _controllers[spec.key],
      readOnly: true,
      onTap: () => _pickDate(spec.key),
      decoration: InputDecoration(
        hintText: 'YYYY-MM-DD',
        prefixIcon: Icon(spec.icon),
        suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
      ),
    );
  }

  Widget _passwordField(FieldSpec spec, {bool numeric = false}) {
    final obscure = _obscure[spec.key] ?? true;
    final isPassword = spec.type == FieldType.password;
    final controller = _controllers[spec.key]!;

    // The TextFormField is built ONCE here. Only the strength meter rebuilds
    // on every keystroke (via its own ValueListenableBuilder below). Wrapping
    // the field itself in a listenable was the cause of the laggy typing on
    // password fields.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: numeric
              ? TextInputType.number
              : TextInputType.visiblePassword,
          inputFormatters:
              numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            hintText: spec.hint,
            prefixIcon: Icon(spec.icon),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: obscure ? 'Show' : 'Hide',
                  onPressed: () =>
                      setState(() => _obscure[spec.key] = !obscure),
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                if (spec.generator)
                  IconButton(
                    tooltip: 'Generate',
                    onPressed: () => _openGenerator(spec.key),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
        if (isPassword && spec.showStrengthMeter)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) =>
                PasswordStrengthMeter(password: value.text),
          ),
      ],
    );
  }

  Widget _selectField(FieldSpec spec) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final current = _controllers[spec.key]?.text ?? '';

    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: spec.options!.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final option = spec.options![i];
          final selected = current == option;
          return Material(
            color: selected
                ? scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                _controllers[spec.key]?.text = option;
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? scheme.primary.withValues(alpha: isDark ? 0.5 : 0.4)
                        : scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      spec.icon,
                      size: 16,
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      option,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                            color:
                                selected ? scheme.primary : scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool required;
  const _Label(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 0),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
            ),
            if (required)
              TextSpan(
                text: '  *',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w800,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final EntryCategory value;
  final ValueChanged<EntryCategory> onChanged;

  const _CategoryPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Category'),
        const SizedBox(height: 10),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: EntryCategory.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = EntryCategory.values[i];
              final selected = c == value;
              final scheme = Theme.of(context).colorScheme;
              final isDark = scheme.brightness == Brightness.dark;
              return GestureDetector(
                onTap: () => onChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? c.accent.withValues(alpha: isDark ? 0.18 : 0.12)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? c.accent.withValues(alpha: isDark ? 0.5 : 0.4)
                          : scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        c.icon,
                        size: 18,
                        color: selected
                            ? c.accent
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        c.label,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(
                              color: selected
                                  ? c.accent
                                  : scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Loads apps after the sheet is visible so the tap feels instant; work runs on
/// the native side off the UI thread (see [MainActivity] `queryLaunchableApps`).
class _LinkedAndroidAppPickerSheet extends StatefulWidget {
  const _LinkedAndroidAppPickerSheet();

  @override
  State<_LinkedAndroidAppPickerSheet> createState() =>
      _LinkedAndroidAppPickerSheetState();
}

class _LinkedAndroidAppPickerSheetState extends State<_LinkedAndroidAppPickerSheet> {
  late final Future<List<LaunchableApp>> _load;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load = AutofillSessionService.queryLaunchableApps();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q == _query) return;
    setState(() => _query = q);
  }

  /// Case-insensitive substring match against both label and package — package
  /// matching catches niche cases where the user knows the bundle id but not
  /// the user-facing name (e.g. searching "twitter" still finds X / com.twitter.android).
  List<LaunchableApp> _filter(List<LaunchableApp> apps) {
    if (_query.isEmpty) return apps;
    return apps
        .where(
          (a) =>
              a.label.toLowerCase().contains(_query) ||
              a.packageName.toLowerCase().contains(_query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Modest sheet height (~58% of screen). Keyboard inset handling is
    // intentionally delegated to the showVaultBottomSheet wrapper's
    // AnimatedPadding — reading MediaQuery.viewInsetsOf here would force
    // a full subtree rebuild on every keyboard animation frame (the
    // FutureBuilder + ListView + Image.memory decompression), which is
    // the original cause of the laggy keyboard-lift the user reported.
    final h = MediaQuery.sizeOf(context).height * 0.58;

    return SizedBox(
      height: h,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search apps',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<LaunchableApp>>(
              future: _load,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Loading apps...',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _AppPickerError(
                    message: 'Could not load app list',
                  );
                }
                final apps = snapshot.data ?? const <LaunchableApp>[];
                if (apps.isEmpty) {
                  return _AppPickerError(
                    message: 'Could not load app list',
                  );
                }
                final filtered = _filter(apps);
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 36,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No apps match "${_searchController.text}"',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final a = filtered[i];
                    final bytes = a.iconPng;
                    final leading = (bytes != null && bytes.isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              bytes,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                Icons.apps_rounded,
                                color: scheme.primary,
                              ),
                            ),
                          )
                        : Icon(Icons.apps_rounded, color: scheme.primary);
                    return ListTile(
                      leading: leading,
                      title: Text(a.label),
                      subtitle: Text(
                        a.packageName,
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      onTap: () => Navigator.pop(ctx, a),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppPickerError extends StatelessWidget {
  final String message;
  const _AppPickerError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inserts spaces every 4 digits for readability while typing card numbers.
/// Collapsed-by-default group for fields most users never touch (TOTP
/// algorithm/digits/period). Stays out of the main column so the editor
/// reads cleanly for the 99% case; users who need Steam / 8-digit / 60s
/// can tap to expand. Defaults pre-fill on category switch via the
/// existing controller-cache so values persist if the user toggles open.
class _AdvancedSection extends StatelessWidget {
  final List<FieldSpec> fields;
  final Widget Function(FieldSpec) buildField;
  final Map<String, GlobalKey> fieldKeys;

  const _AdvancedSection({
    required this.fields,
    required this.buildField,
    required this.fieldKeys,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Theme(
        // Strip the default ExpansionTile divider lines — looks cluttered
        // next to the rest of the borderless form fields.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            iconColor: scheme.onSurfaceVariant,
            collapsedIconColor: scheme.onSurfaceVariant,
            title: Text(
              'Advanced (optional)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              'Defaults work for most issuers',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            children: [
              for (final spec in fields) ...[
                KeyedSubtree(
                  key: fieldKeys.putIfAbsent(spec.key, GlobalKey.new),
                  child: buildField(spec),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap target above the TOTP fields. Reads the system clipboard and
/// hands it to [TotpService.parseUri]; on success the form populates
/// every TOTP field. On failure the user gets a clean toast and the
/// form stays as it was.
class _OtpauthPasteCard extends StatelessWidget {
  final VoidCallback onPaste;
  const _OtpauthPasteCard({required this.onPaste});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = scheme.primary;
    return Material(
      color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPaste,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste otpauth:// URI',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Auto-fills every field below.',
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.content_paste_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Auto-inserts the slash for MM/YY expiry input.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    String formatted;
    if (digits.length >= 3) {
      formatted = '${digits.substring(0, 2)}/${digits.substring(2)}';
    } else {
      formatted = digits;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
