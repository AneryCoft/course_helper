import 'package:flutter/material.dart';

/// 设计令牌：统一间距、圆角、动画时长与阴影，避免各页面硬编码魔法数字。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 页面统一水平内边距
  static const double page = 16;

  /// 底部导航等悬浮元素避让高度
  static const double bottomInset = 96;
}

class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 100;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// 常用渐变与光晕，供头部卡片和强调区域使用。
class AppGradients {
  AppGradients._();

  /// 主色渐变（用于 Hero 头部）
  static LinearGradient primary(ColorScheme cs) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.55)!],
      );

  /// 柔和容器渐变（用于次级卡片）
  static LinearGradient surface(ColorScheme cs) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [cs.surfaceContainerHigh, cs.surfaceContainer],
      );

  /// 头像/图标底色
  static LinearGradient tint(Color color) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.55)],
      );
}

/// 从任意字符串稳定派生一个可复现的强调色，用于给课程卡片做视觉区分。
Color accentFromSeed(ColorScheme cs, String seed) {
  if (seed.isEmpty) return cs.primary;
  final hash = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
  final palette = <Color>[
    cs.primary,
    cs.tertiary,
    cs.secondary,
    Color.lerp(cs.primary, cs.tertiary, 0.5)!,
    Color.lerp(cs.tertiary, cs.secondary, 0.4)!,
  ];
  return palette[hash % palette.length];
}
