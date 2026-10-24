import 'package:flutter/material.dart';

/// 统一的轻量级 UI 辅助方法，避免各页面重复拼装 SnackBar / Loading / 空状态。
class UiHelper {
  UiHelper._();

  /// 显示一条普通提示
  static void toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 显示一条成功提示
  static void success(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// 显示一条错误提示
  static void error(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: cs.error,
      ),
    );
  }

  /// 全屏加载态
  static Widget loading({String? message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  /// 空状态占位（图标 + 文案）
  static Widget empty({
    IconData icon = Icons.inbox_outlined,
    String message = '暂无数据',
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
