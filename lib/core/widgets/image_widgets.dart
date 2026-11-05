import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../images/attachment_storage.dart';
import '../images/image_models.dart';

/// Asks where the image should come from.
///
/// Returns null if the sheet is dismissed.
Future<ImageSourceKind?> askImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSourceKind>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () =>
                Navigator.of(sheetContext).pop(ImageSourceKind.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () =>
                Navigator.of(sheetContext).pop(ImageSourceKind.gallery),
          ),
          const SizedBox(height: kSpace),
        ],
      ),
    ),
  );
}

/// An image held in a private bucket, fetched through a signed URL.
class AttachmentImage extends ConsumerWidget {
  const AttachmentImage({
    required this.bucket,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.enlargeOnTap = true,
    this.semanticLabel,
    super.key,
  });

  final StorageBucket bucket;
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool enlargeOnTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(signedAttachmentUrlProvider(bucket, path));

    // The label wraps every state, not just the loaded one: an image that is
    // still fetching, or that failed to load, still needs a name for a screen
    // reader (spec §11).
    return Semantics(
      label: semanticLabel,
      image: true,
      child: _body(context, url),
    );
  }

  Widget _body(BuildContext context, AsyncValue<String> url) {
    return url.when(
      loading: () => _Placeholder(
        width: width,
        height: height,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => _Placeholder(
        width: width,
        height: height,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      data: (signed) {
        final image = Image.network(
          signed,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, _, _) => _Placeholder(
            width: width,
            height: height,
            child: const Icon(Icons.broken_image_outlined),
          ),
        );

        if (!enlargeOnTap) return image;

        return GestureDetector(
          onTap: () => showFullScreenImage(context, signed, semanticLabel),
          child: image,
        );
      },
    );
  }
}

/// Full-screen viewer with pinch to zoom (spec §9: tap to enlarge).
void showFullScreenImage(BuildContext context, String url, String? label) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (viewerContext) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url, semanticLabel: label),
          ),
        ),
      ),
    ),
  );
}

/// A thumbnail of an image that has been picked but not yet uploaded.
class PendingImageThumb extends StatelessWidget {
  const PendingImageThumb({
    required this.bytes,
    required this.onRemove,
    this.size = 72,
    super.key,
  });

  final Uint8List bytes;
  final VoidCallback onRemove;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kRadiusMd),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            // A picked file that will not decode should show as broken, not
            // bring the form down.
            errorBuilder: (context, _, _) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: const Icon(Icons.close, size: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.child, this.width, this.height});

  final Widget child;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height ?? 72,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox.square(dimension: 20, child: child),
    );
  }
}
