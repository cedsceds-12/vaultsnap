import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/attachment.dart';
import '../providers/vault_providers.dart';
import '../providers/vault_repository_provider.dart';
import '../widgets/attachment_tile.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/vault_toast.dart';

/// Full-screen viewer for a single [VaultAttachment]. Decrypts the
/// ciphertext on mount and either:
///   • shows the bytes directly via `Image.memory + InteractiveViewer`
///     when the attachment is an image, or
///   • shows a metadata card + "Export decrypted…" action for any
///     other type (PDFs, text, generic).
///
/// **PDF preview deferred to v1.1.** See pubspec.yaml — both `pdfx`
/// and `pdfrx` have unfixed Gradle build issues, and `flutter_pdfview`
/// would write decrypted bytes to a temp file. Until a working
/// FFI/in-memory PDF renderer ships, PDFs go through the
/// "Export decrypted…" path with the explicit plaintext warning.
///
/// Plaintext bytes live in [_bytes] for the screen's lifetime and
/// nowhere else. On [dispose] we zero-fill the buffer before dropping
/// the reference — Flutter's GC isn't deterministic, and a security
/// product shouldn't leave decrypted bytes lingering in RAM after the
/// user closes the viewer.
class AttachmentViewerScreen extends ConsumerStatefulWidget {
  final VaultAttachment attachment;

  const AttachmentViewerScreen({super.key, required this.attachment});

  @override
  ConsumerState<AttachmentViewerScreen> createState() =>
      _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState
    extends ConsumerState<AttachmentViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decrypt());
  }

  Future<void> _decrypt() async {
    try {
      final bytes = await ref
          .read(vaultRepositoryProvider.notifier)
          .decryptAttachment(widget.attachment);
      if (!mounted) {
        // Mount race — bytes won't be displayed; zero them now.
        _zero(bytes);
        return;
      }
      setState(() => _bytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    // Best-effort scrub of plaintext bytes before letting GC have
    // them. AES-GCM-decrypted material should not linger past the
    // viewer's lifetime — Flutter's GC is non-deterministic and a
    // security product needs "closed = gone" to mean exactly that.
    final b = _bytes;
    if (b != null) {
      _zero(b);
    }
    _bytes = null;
    super.dispose();
  }

  static void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  Future<void> _exportDecrypted() async {
    final bytes = _bytes;
    if (bytes == null || _exporting) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Export decrypted file?',
      message:
          'The file will be written in plaintext to a location you choose. '
          'Other apps on this device will be able to read it.',
      confirmLabel: 'Export anyway',
      icon: Icons.warning_amber_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _exporting = true);
    try {
      final saved = await ref.read(windowServiceProvider).saveBytes(
            bytes: bytes,
            suggestedName: widget.attachment.name,
            mime: widget.attachment.mime,
          );
      if (!mounted) return;
      if (saved != null) {
        VaultToast.showSuccess(context, 'Saved as $saved');
      }
    } catch (e) {
      if (!mounted) return;
      VaultToast.showError(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = widget.attachment;

    return Scaffold(
      backgroundColor: a.isImage ? Colors.black : scheme.surface,
      appBar: AppBar(
        backgroundColor: a.isImage ? Colors.black : scheme.surface,
        foregroundColor: a.isImage ? Colors.white : scheme.onSurface,
        elevation: 0,
        title: Text(a.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (!a.isImage && _bytes != null)
            IconButton(
              tooltip: 'Export decrypted…',
              onPressed: _exporting ? null : _exportDecrypted,
              icon: const Icon(Icons.save_alt_rounded),
            ),
        ],
      ),
      body: _error != null
          ? _ErrorBody(message: _error!)
          : (_bytes == null
              ? const Center(child: CircularProgressIndicator())
              : (a.isImage
                  ? _ImageBody(bytes: _bytes!)
                  : _NonImageBody(
                      attachment: a,
                      onExport: _exportDecrypted,
                      busy: _exporting,
                    ))),
    );
  }
}

class _ImageBody extends StatelessWidget {
  final Uint8List bytes;
  const _ImageBody({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InteractiveViewer(
        // Pinch-to-zoom up to 6x; below 1x is uninteresting for an
        // image preview and would let the user shrink it off-screen.
        minScale: 1,
        maxScale: 6,
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not decode image: $error',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NonImageBody extends StatelessWidget {
  final VaultAttachment attachment;
  final VoidCallback onExport;
  final bool busy;
  const _NonImageBody({
    required this.attachment,
    required this.onExport,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = scheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant
                  .withValues(alpha: isDark ? 0.4 : 0.5),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color:
                          accent.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accent
                            .withValues(alpha: isDark ? 0.38 : 0.28),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      attachment.isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.insert_drive_file_outlined,
                      color: accent,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.name,
                          style:
                              Theme.of(context).textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatBytes(attachment.blobSize)} · ${attachment.mime}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(
                      alpha: isDark ? 0.35 : 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.error
                        .withValues(alpha: isDark ? 0.5 : 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: scheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Exporting writes this file in plaintext to a '
                        'location of your choice. Other apps will be '
                        'able to read it.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy ? null : onExport,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.save_alt_rounded),
                label: Text(busy ? 'Exporting…' : 'Export decrypted…'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not open this attachment.\n\n$message',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
