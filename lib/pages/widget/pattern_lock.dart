import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PatternLock extends StatefulWidget {
  const PatternLock({
    super.key,
    this.dimension = 3,
    this.relativePadding = 0.5,
    this.selectedColor = Colors.blue,
    this.notSelectedColor = Colors.grey,
    this.pointRadius = 30,
    this.successColor,
    this.errorColor,
    this.onInputComplete,
  });

  final int dimension;

  /// 点绘制半径相对 cell 内切圆半径的收缩比例（0~1）
  final double relativePadding;

  final Color selectedColor;
  final Color notSelectedColor;

  /// 点绘制半径上限
  final double pointRadius;

  final Color? successColor;

  final Color? errorColor;

  /// 抬手回调，参数为按选择顺序排列的点索引（1-based），
  /// 返回验证结果用于着色反馈，null 表示不反馈
  final Future<bool?> Function(List<int>)? onInputComplete;

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> {
  final List<int> _selected = <int>[];
  Offset? _current;
  int? _activePointer;
  Color? _resultColor;
  bool _resolving = false;
  Size _size = Size.zero;

  double get _cellSize => min(_size.width, _size.height) / widget.dimension;

  Offset get _gridOrigin {
    final side = _cellSize * widget.dimension;
    return Offset((_size.width - side) / 2, (_size.height - side) / 2);
  }

  double get _drawRadius =>
      min(widget.pointRadius, _cellSize / 2 * (1 - widget.relativePadding));

  /// 小于 cell / 2 保证相邻判定区不重叠
  double get _hitRadius => _cellSize * 0.48;

  Offset _pointCenter(int index) {
    final cell = _cellSize;
    final col = index % widget.dimension;
    final row = index ~/ widget.dimension;
    return _gridOrigin + Offset((col + 0.5) * cell, (row + 0.5) * cell);
  }

  int? _hitTest(Offset pos) {
    int? best;
    var bestDist = double.infinity;
    final count = widget.dimension * widget.dimension;
    for (var i = 0; i < count; i++) {
      final d = (pos - _pointCenter(i)).distance;
      if (d <= _hitRadius && d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _onPointerDown(Offset pos) {
    setState(() {
      _current = pos;
      final hit = _hitTest(pos);
      if (hit != null) _selected.add(hit);
    });
  }

  void _onPointerMove(Offset pos) {
    final prev = _current ?? pos;
    final dist = (pos - prev).distance;
    const step = 6.0;
    final n = (dist / step).ceil();
    final hits = <int>[];
    for (var i = 1; i <= n; i++) {
      final p = Offset.lerp(prev, pos, i / n)!;
      final hit = _hitTest(p);
      if (hit != null && !_selected.contains(hit) && !hits.contains(hit)) {
        hits.add(hit);
      }
    }
    if (hits.isNotEmpty || pos != _current) {
      setState(() {
        _selected.addAll(hits);
        _current = pos;
      });
    }
  }

  Future<void> _onPointerEnd(int pointer) async {
    if (pointer != _activePointer) return;
    _activePointer = null;
    final result = List<int>.of(_selected);
    setState(() => _current = null);
    if (result.isEmpty || widget.onInputComplete == null) {
      setState(() => _selected.clear());
      return;
    }

    _resolving = true;
    bool? ok;
    try {
      ok = await widget.onInputComplete!(result);
    } catch (_) {
      ok = null;
    }
    if (!mounted) return;
    _resolving = false;

    if (ok == null) {
      setState(() => _selected.clear());
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    setState(() => _resultColor = ok! ?
    (widget.successColor ?? scheme.tertiary) : (widget.errorColor ?? scheme.error));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _resultColor = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_activePointer != null || _resolving) return;
            _activePointer = e.pointer;
            _onPointerDown(e.localPosition);
          },
          onPointerMove: (e) {
            if (e.pointer != _activePointer) return;
            _onPointerMove(e.localPosition);
          },
          onPointerUp: (e) => _onPointerEnd(e.pointer),
          onPointerCancel: (e) => _onPointerEnd(e.pointer),
          child: CustomPaint(
            size: _size,
            painter: _PatternPainter(
              dimension: widget.dimension,
              cellSize: _cellSize,
              gridOrigin: _gridOrigin,
              drawRadius: _drawRadius,
              selectedColor: widget.selectedColor,
              notSelectedColor: widget.notSelectedColor,
              selected: List<int>.of(_selected),
              current: _current,
              resultColor: _resultColor,
            ),
          ),
        );
      },
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dimension,
    required this.cellSize,
    required this.gridOrigin,
    required this.drawRadius,
    required this.selectedColor,
    required this.notSelectedColor,
    required this.selected,
    required this.current,
    this.resultColor,
  });

  final int dimension;
  final double cellSize;
  final Offset gridOrigin;
  final double drawRadius;
  final Color selectedColor;
  final Color notSelectedColor;
  final List<int> selected;
  final Offset? current;

  /// 非 null 时整体着色
  final Color? resultColor;

  Offset _center(int index) {
    final col = index % dimension;
    final row = index ~/ dimension;
    return gridOrigin + Offset((col + 0.5) * cellSize, (row + 0.5) * cellSize);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final highlight = resultColor ?? selectedColor;
    final linePaint = Paint()
      ..color = highlight
      ..strokeWidth = drawRadius * 0.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(_center(selected[i]), _center(selected[i + 1]), linePaint);
    }
    if (current != null && selected.isNotEmpty) {
      canvas.drawLine(_center(selected.last), current!, linePaint);
    }

    final fillPaint = Paint();
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = drawRadius * 0.2
      ..color = highlight;

    final count = dimension * dimension;
    for (var i = 0; i < count; i++) {
      final center = _center(i);
      if (selected.contains(i)) {
        fillPaint.color = highlight;
        canvas.drawCircle(center, drawRadius, fillPaint);
        canvas.drawCircle(center, drawRadius * 1.35, ringPaint);
      } else {
        fillPaint.color = notSelectedColor;
        canvas.drawCircle(center, drawRadius, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.dimension != dimension ||
      old.cellSize != cellSize ||
      old.gridOrigin != gridOrigin ||
      old.drawRadius != drawRadius ||
      old.selectedColor != selectedColor ||
      old.notSelectedColor != notSelectedColor ||
      old.current != current ||
      old.resultColor != resultColor ||
      !listEquals(old.selected, selected);
}
