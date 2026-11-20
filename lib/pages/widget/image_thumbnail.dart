import 'dart:io';
import 'package:flutter/material.dart';

import '../../api/api_service.dart';
import '../../api/image.dart';

/// 预览图片
///
/// 图片来源三选一：[file]、[url]（加入学习通Headers）、[objectId]。
/// 传入 [heroTag] 时用 Hero 包裹大图，与缩略图配合实现过渡动画。
void showImageViewer(
  BuildContext context, {
  File? file,
  String? url,
  String? objectId,
  String? heroTag
}) {
  if (file == null && url == null && objectId == null) {
    return;
  }

  Widget image;
  if (file != null) {
    image = Image.file(file, fit: BoxFit.contain);
  } else {
    final imageUrl = url ?? CXImageApi.getImageUrl(objectId!);
    image = Image.network(
      imageUrl,
      headers: HeadersManager.chaoxingHeaders,
      fit: BoxFit.contain
    );
  }

  if (heroTag != null) {
    image = Hero(tag: heroTag, child: image);
  }

  showDialog<void>(
    context: context,
    builder: (context) => GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: Colors.black12,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(child: image),
        ),
      ),
    ),
  );
}

/// 图片缩略图组件
class ImageThumbnail extends StatelessWidget {
  const ImageThumbnail({
    super.key,
    this.file,
    this.url,
    this.objectId,
    this.thumbnailUrl,
    this.width = 80,
    this.height = 80,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
    this.onDelete,
    this.heroTag,
    this.overlay,
  });

  final File? file;

  final String? url;

  final String? objectId;

  /// 可选：缩略图专用 URL。
  final String? thumbnailUrl;

  final double width;
  final double height;
  final BoxFit fit;
  final double borderRadius;

  final VoidCallback? onDelete;

  final String? heroTag;

  final Widget? overlay;

  String? get _previewUrl =>
      url ?? (objectId != null ? CXImageApi.getImageUrl(objectId!) : null);

  void _preview(BuildContext context) {
    showImageViewer(context, file: file, url: _previewUrl, heroTag: heroTag);
  }

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage();
    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return Stack(
      children: [
        GestureDetector(
          onTap: () => _preview(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: image,
          ),
        ),
        if (overlay != null) Positioned.fill(child: overlay!),
        if (onDelete != null)
          Positioned(right: 4, top: 4, child: _DeleteBadge(onTap: onDelete!)),
      ],
    );
  }

  Widget _buildImage() {
    if (file != null) {
      return Image.file(file!, width: width, height: height, fit: fit);
    }

    final imageUrl = thumbnailUrl ?? _previewUrl;
    if (imageUrl == null) {
      return SizedBox(width: width, height: height);
    }

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      headers: HeadersManager.chaoxingHeaders,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image, color: Colors.grey),
      ),
    );
  }
}

class _DeleteBadge extends StatelessWidget {
  const _DeleteBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}
