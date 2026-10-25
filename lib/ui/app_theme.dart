import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';

/// 全局主题构建：Material 3 + 动态取色，统一视觉语言。
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF4F46E5);

  static ThemeData light([ColorScheme? dynamic]) =>
      _build(dynamic ?? ColorScheme.fromSeed(seedColor: _seed));

  static ThemeData dark([ColorScheme? dynamic]) => _build(
        dynamic ??
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
      );

  static ThemeData _build(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      visualDensity: VisualDensity.standard,

      // ---------- 文字 ----------
      textTheme: _textTheme(cs),

      // ---------- AppBar ----------
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: cs.onSurface,
        ),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      // ---------- 卡片 ----------
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page,
          vertical: AppSpacing.sm,
        ),
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      // ---------- 列表 ----------
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.page,
          vertical: AppSpacing.sm,
        ),
      ),

      // ---------- 按钮 ----------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: cs.outlineVariant),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      // ---------- 输入框 ----------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        helperStyle: TextStyle(fontSize: 12, color: cs.outline),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
      ),

      // ---------- 导航栏 ----------
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: cs.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          );
        }),
      ),

      // ---------- 其他组件 ----------
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: cs.outlineVariant.withValues(alpha: 0.5),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide.none,
        ),
        backgroundColor: cs.surfaceContainerHigh,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: cs.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        elevation: 3,
        insetPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        contentTextStyle: TextStyle(
          color: cs.onInverseSurface,
          fontSize: 14,
          height: 1.4,
        ),
        actionTextColor: cs.inversePrimary,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: cs.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? cs.primary
              : cs.surfaceContainerHighest,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.primary : cs.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? cs.primary : Colors.transparent,
        ),
        side: BorderSide(color: cs.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: cs.error,
        textColor: cs.onError,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }

  static TextTheme _textTheme(ColorScheme cs) {
    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: cs.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: cs.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: cs.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: cs.onSurface),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: cs.onSurface),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
