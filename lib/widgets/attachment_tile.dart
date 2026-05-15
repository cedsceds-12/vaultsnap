import 'package:flutter/material.dart';

import '../models/attachment.dart';

/// A single row in the entry-detail Attachments section. Renders the
/// mime-derived icon, file name, and a "1.2 MB · png" subtitle. Tap
/// opens the viewer; long-press triggers a delete-confirm in the
/// parent. Stateless — all interaction routes through callbacks.
class AttachmentTile extends StatelessWidget {
  final VaultAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final iconBg = accent.withValues(alpha: isDark ? 0.18 : 0.12);
    final iconBorder = accent.withValues(alpha: isDark ? 0.38 : 0.28);

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: iconBorder),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _iconFor(attachment),
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(attachment),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(VaultAttachment a) {
    if (a.isImage) return Icons.image_outlined;
    if (a.isPdf) return Icons.picture_as_pdf_outlined;
    if (a.mime == 'text/plain') return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _subtitle(VaultAttachment a) {
    final size = formatBytes(a.blobSize);
    final ext = a.name.contains('.')
        ? a.name.split('.').last.toLowerCase()
        : a.mime.split('/').last;
    return '$size · $ext';
  }
}

/// Tiny human-readable bytes formatter ("12 KB", "3.4 MB"). Used by
/// the tile subtitle and the viewer's metadata card.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(bytes < 10 * kb ? 1 : 0)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(bytes < 10 * mb ? 1 : 0)} MB';
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}
