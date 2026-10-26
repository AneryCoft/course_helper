import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 上课界面使用的自定义图标
///
/// 用 CustomPainter 手绘，替代通用 Material 图标，
/// 让「上课啦」「随机点名」这类课堂事件有更强的辨识度。
class ClassroomIcons {
  ClassroomIcons._();
}

/// 事件图标类型
enum ClassroomIconType {
  /// 上课啦（铃铛 + 声波）
  lessonStart,

  /// 下课
  lessonEnd,

  /// 开始放映
  presentationStart,

  /// 结束放映
  presentationEnd,

  /// 随堂练习
  problem,

  /// 随机点名
  randomPick,

  /// 位置签到
  checkIn,

  /// 签到结束
  checkInEnd,

  /// 其他
  info,
}

/// 通用绘制入口
class ClassroomIcon extends StatelessWidget {
  final ClassroomIconType type;
  final double size;
  final Color color;

  const ClassroomIcon(
    this.type, {
    super.key,
    this.size = 22,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ClassroomIconPainter(type: type, color: color),
      ),
    );
  }
}

class _ClassroomIconPainter extends CustomPainter {
  final ClassroomIconType type;
  final Color color;

  _ClassroomIconPainter({required this.type, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.085;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (type) {
      case ClassroomIconType.lessonStart:
        _drawBell(canvas, s, paint, fill);
        break;
      case ClassroomIconType.lessonEnd:
        _drawBell(canvas, s, paint, fill, muted: true);
        break;
      case ClassroomIconType.presentationStart:
        _drawScreen(canvas, s, paint, fill, playing: true);
        break;
      case ClassroomIconType.presentationEnd:
        _drawScreen(canvas, s, paint, fill, playing: false);
        break;
      case ClassroomIconType.problem:
        _drawQuiz(canvas, s, paint, fill);
        break;
      case ClassroomIconType.randomPick:
        _drawRandomPick(canvas, s, paint, fill);
        break;
      case ClassroomIconType.checkIn:
        _drawPin(canvas, s, paint, fill, checked: true);
        break;
      case ClassroomIconType.checkInEnd:
        _drawPin(canvas, s, paint, fill, checked: false);
        break;
      case ClassroomIconType.info:
        _drawInfo(canvas, s, paint, fill);
        break;
    }
  }

  /// 铃铛：上课/下课
  void _drawBell(
    Canvas canvas,
    double s,
    Paint paint,
    Paint fill, {
    bool muted = false,
  }) {
    final body = Path();
    final cx = s * 0.5;
    final top = s * 0.18;
    final bottom = s * 0.66;
    final halfW = s * 0.26;

    // 钟体
    body.moveTo(cx - halfW, bottom);
    body.quadraticBezierTo(cx - halfW * 0.92, top + s * 0.12, cx, top);
    body.quadraticBezierTo(cx + halfW * 0.92, top + s * 0.12, cx + halfW, bottom);
    body.close();

    canvas.drawPath(body, paint);

    // 底部横线
    canvas.drawLine(
      Offset(s * 0.16, bottom),
      Offset(s * 0.84, bottom),
      paint,
    );

    // 顶部提环
    canvas.drawCircle(Offset(cx, s * 0.13), s * 0.045, paint);

    // 钟锤
    canvas.drawCircle(Offset(cx, s * 0.78), s * 0.065, fill);

    if (!muted) {
      // 声波
      for (var i = 0; i < 2; i++) {
        final r = s * (0.3 + i * 0.13);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, s * 0.46), radius: r),
          -math.pi * 0.28,
          math.pi * 0.56,
          false,
          paint..strokeWidth = s * 0.06,
        );
      }
      paint.strokeWidth = s * 0.085;
    } else {
      // 下课：加一道斜杠表示结束
      canvas.drawLine(
        Offset(s * 0.7, s * 0.24),
        Offset(s * 0.86, s * 0.4),
        paint,
      );
    }
  }

  /// 投影幕布：放映开始/结束
  void _drawScreen(
    Canvas canvas,
    double s,
    Paint paint,
    Paint fill, {
    required bool playing,
  }) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.12, s * 0.16, s * 0.76, s * 0.5),
      Radius.circular(s * 0.06),
    );
    canvas.drawRRect(rect, paint);

    // 支架
    canvas.drawLine(
      Offset(s * 0.5, s * 0.66),
      Offset(s * 0.5, s * 0.84),
      paint,
    );
    canvas.drawLine(
      Offset(s * 0.32, s * 0.86),
      Offset(s * 0.68, s * 0.86),
      paint,
    );

    if (playing) {
      // 播放三角
      final tri = Path()
        ..moveTo(s * 0.43, s * 0.3)
        ..lineTo(s * 0.63, s * 0.41)
        ..lineTo(s * 0.43, s * 0.52)
        ..close();
      canvas.drawPath(tri, fill);
    } else {
      // 停止方块
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s * 0.42, s * 0.32, s * 0.16, s * 0.18),
          Radius.circular(s * 0.02),
        ),
        fill,
      );
    }
  }

  /// 随堂练习：纸 + 勾
  void _drawQuiz(Canvas canvas, double s, Paint paint, Paint fill) {
    final page = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.2, s * 0.14, s * 0.6, s * 0.72),
      Radius.circular(s * 0.08),
    );
    canvas.drawRRect(page, paint);

    // 三条横线
    for (var i = 0; i < 3; i++) {
      final y = s * (0.3 + i * 0.15);
      canvas.drawLine(
        Offset(s * 0.32, y),
        Offset(s * (i == 2 ? 0.5 : 0.68), y),
        paint..strokeWidth = s * 0.065,
      );
    }
    paint.strokeWidth = s * 0.085;

    // 勾
    final check = Path()
      ..moveTo(s * 0.56, s * 0.66)
      ..lineTo(s * 0.64, s * 0.74)
      ..lineTo(s * 0.8, s * 0.54);
    canvas.drawPath(check, paint..strokeWidth = s * 0.075);
    paint.strokeWidth = s * 0.085;
  }

  /// 随机点名：转盘 + 指针
  void _drawRandomPick(Canvas canvas, double s, Paint paint, Paint fill) {
    final center = Offset(s * 0.5, s * 0.52);
    final radius = s * 0.32;

    canvas.drawCircle(center, radius, paint);

    // 三条辐条
    for (var i = 0; i < 3; i++) {
      final angle = math.pi * 2 / 3 * i - math.pi / 2;
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(angle) * radius * 0.72,
          center.dy + math.sin(angle) * radius * 0.72,
        ),
        paint..strokeWidth = s * 0.06,
      );
    }
    paint.strokeWidth = s * 0.085;

    // 中心圆点
    canvas.drawCircle(center, s * 0.075, fill);

    // 顶部指针
    final pointer = Path()
      ..moveTo(s * 0.5, s * 0.1)
      ..lineTo(s * 0.42, s * 0.2)
      ..lineTo(s * 0.58, s * 0.2)
      ..close();
    canvas.drawPath(pointer, fill);
  }

  /// 定位签到：水滴 + 勾/叉
  void _drawPin(
    Canvas canvas,
    double s,
    Paint paint,
    Paint fill, {
    required bool checked,
  }) {
    final pin = Path()
      ..moveTo(s * 0.5, s * 0.86)
      ..cubicTo(
        s * 0.2,
        s * 0.6,
        s * 0.22,
        s * 0.16,
        s * 0.5,
        s * 0.16,
      )
      ..cubicTo(
        s * 0.78,
        s * 0.16,
        s * 0.8,
        s * 0.6,
        s * 0.5,
        s * 0.86,
      )
      ..close();
    canvas.drawPath(pin, paint);

    final c = Offset(s * 0.5, s * 0.42);
    canvas.drawCircle(c, s * 0.16, fill..color = color.withValues(alpha: 0.001));

    if (checked) {
      final check = Path()
        ..moveTo(s * 0.42, s * 0.42)
        ..lineTo(s * 0.48, s * 0.5)
        ..lineTo(s * 0.6, s * 0.34);
      canvas.drawPath(check, paint..strokeWidth = s * 0.08);
    } else {
      canvas.drawLine(
        Offset(s * 0.42, s * 0.34),
        Offset(s * 0.58, s * 0.5),
        paint..strokeWidth = s * 0.08,
      );
      canvas.drawLine(
        Offset(s * 0.58, s * 0.34),
        Offset(s * 0.42, s * 0.5),
        paint..strokeWidth = s * 0.08,
      );
    }
    paint.strokeWidth = s * 0.085;
  }

  /// 信息
  void _drawInfo(Canvas canvas, double s, Paint paint, Paint fill) {
    canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.34, paint);
    canvas.drawCircle(Offset(s * 0.5, s * 0.31), s * 0.055, fill);
    canvas.drawLine(
      Offset(s * 0.5, s * 0.45),
      Offset(s * 0.5, s * 0.68),
      paint..strokeWidth = s * 0.09,
    );
  }

  @override
  bool shouldRepaint(covariant _ClassroomIconPainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}

/// 把课堂事件映射到图标类型
ClassroomIconType iconTypeForEvent(String type, String? code) {
  switch (type) {
    case 'event':
      switch (code) {
        case 'LESSON_START':
          return ClassroomIconType.lessonStart;
        case 'LESSON_FINISH':
          return ClassroomIconType.lessonEnd;
        case 'SHOW_PRESENTATION':
        case 'START_PRESENTATION':
          return ClassroomIconType.presentationStart;
        case 'SHOW_FINISH':
          return ClassroomIconType.presentationEnd;
        default:
          return ClassroomIconType.info;
      }
    case 'problem':
      return ClassroomIconType.problem;
    case 'randompick':
      return ClassroomIconType.randomPick;
    case 'locationcheckin_start':
      return ClassroomIconType.checkIn;
    case 'locationcheckin_end':
      return ClassroomIconType.checkInEnd;
    default:
      return ClassroomIconType.info;
  }
}
