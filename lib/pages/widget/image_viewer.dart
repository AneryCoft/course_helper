import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../../utils/logger.dart';
import 'avatar.dart';

/// 显示全屏图片查看器
///
/// [imageUrl] 与 [imageBytes] 至少提供一个。[imageUrl] 会复用 [AvatarCache]
/// （携带当前平台 Cookie），适合查看需要登录态的头像/封面。
Future<void> showImageViewer(
  BuildContext context, {
  String? imageUrl,
  Uint8List? imageBytes,
  String? heroTag,
  String? title,
}) async {
  if (imageUrl == null && imageBytes == null) return;

  late Uint8List? bytes = imageBytes;
  if (bytes == null && imageUrl != null) {
    bytes = await AvatarCache.getImage(imageUrl);
  }

  if (!context.mounted) return;

  if (bytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片加载失败')),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewerPage(
        bytes: bytes!,
        heroTag: heroTag,
        title: title,
      ),
    ),
  );
}

class _ImageViewerPage extends StatelessWidget {
  final Uint8List bytes;
  final String? heroTag;
  final String? title;

  const _ImageViewerPage({
    required this.bytes,
    this.heroTag,
    this.title,
  });

  Widget _buildImage(BuildContext context) {
    final image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
      ),
    );

    final viewer = InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: heroTag != null
          ? Hero(tag: heroTag!, child: image)
          : image,
    );

    return viewer;
  }

  Future<void> _saveImage(BuildContext context) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth && !permission.hasAccess) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未授予相册权限，无法保存')),
          );
        }
        return;
      }

      final fileName =
          'course_helper_${DateTime.now().millisecondsSinceEpoch}.png';
      // saveImage 返回非空 AssetEntity，失败会抛异常（由下方 catch 处理）
      await PhotoManager.editor.saveImage(bytes, filename: fileName);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      logger.e('保存图片失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _shareImage(BuildContext context) async {
    try {
      final file = XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'course_helper_image.png',
      );
      await Share.shareXFiles(
        [file],
        text: title,
      );
    } catch (e) {
      logger.e('分享图片失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: title != null ? Text(title!) : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: '保存到相册',
            onPressed: () => _saveImage(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享',
            onPressed: () => _shareImage(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _buildImage(context),
        ),
      ),
    );
  }
}
