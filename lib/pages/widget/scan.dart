import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  final Function(String)? onScanResult;

  const ScanPage({super.key, this.onScanResult});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int animationTime = 2000;

  MobileScannerController? _controller;
  late final AnimationController _animationController;

  bool isScan = false;
  bool _isInitializing = true;
  bool _handled = false;
  bool _torchOn = false;

  double _baseZoom = 0.0;
  double _currentZoom = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: animationTime),
    )..addStatusListener(_onAnimationStatus);

    _controller = MobileScannerController(
      autoStart: false,
      cameraResolution: const Size(1920, 1080),
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500,
      formats: [BarcodeFormat.qrCode],
      autoZoom: true
    );

    _initializeScanner();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _animationController.dispose();
    _controller?.dispose();
    _controller = null;

    isScan = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;

    try {
      switch (state) {
        case AppLifecycleState.resumed:
          controller.start();
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          controller.stop();
      }
    } catch (e) {
      debugPrint('Lifecycle handling error: $e');
    }
  }

  Future<void> _initializeScanner() async {
    if (!mounted) return;

    try {
      await _controller?.start();
      if (!mounted) return;

      await _resetZoom();
      if (!mounted) return;

      setState(() => _isInitializing = false);
      startScan();
    } catch (e) {
      debugPrint('initializeScanner error: $e');
      if (!mounted) return;
      setState(() => _isInitializing = false);
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (!mounted) return;

    if (status == AnimationStatus.completed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        if (_animationController.status != AnimationStatus.dismissed) {
          _animationController.reverse();
        }
      });
    } else if (status == AnimationStatus.dismissed) {
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        if (_animationController.status != AnimationStatus.forward) {
          _animationController.forward();
        }
      });
    }
  }

  Future<void> _resetZoom() async {
    final controller = _controller;
    if (controller == null) return;

    _baseZoom = 0.0;
    _currentZoom = 0.0;
    try {
      await controller.resetZoomScale();
    } catch (e) {
      debugPrint('resetZoomScale error: $e');
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final controller = _controller;
    if (controller == null) return;

    final target = (_baseZoom + (details.scale - 1.0)).clamp(0.0, 1.0);
    if ((target - _currentZoom).abs() < 0.005) return;

    _currentZoom = target;
    controller.setZoomScale(target).catchError((Object e) {
      debugPrint('setZoomScale error: $e');
    });
  }

  Future<void> toggleTorch() async {
    try {
      await _controller?.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } catch (e) {
      debugPrint('toggleTorch error: $e');
    }
  }

  void startScan() {
    isScan = true;
    _handled = false;
    _animationController.forward();
  }

  void stop() {
    if (!isScan) return;

    isScan = false;
    _controller?.stop();
    _animationController.stop();
    _animationController.reset();
  }

  Future<void> scanImage(String path) async {
    try {
      final barcodeCapture = await _controller?.analyzeImage(path);
      stop();
      if (!mounted) return;

      final barcodes = barcodeCapture?.barcodes;
      final code = (barcodes != null && barcodes.isNotEmpty)
          ? barcodes.first.rawValue
          : null;

      if (code != null) {
        _handleScanResult(code);
        return;
      }
      await _controller?.start();
      if (!mounted) return;
      startScan();
    } catch (e) {
      debugPrint('Failed to analyze image: $e');
      if (!mounted) return;
      try {
        await _controller?.start();
        if (!mounted) return;
        startScan();
      } catch (err) {
        debugPrint('Failed to restart scanner: $err');
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;

    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    _handled = true;
    _handleScanResult(code);
  }

  void _handleScanResult(String data) async {
    if (!mounted) return;

    stop();

    if (!mounted) return;
    try {
      widget.onScanResult?.call(data);
      Navigator.of(context).pop(data);
    } catch (e) {
      debugPrint('Navigator error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final qrScanSize = constraints.maxWidth * 0.7;

        final scanWindow = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
          ),
          width: qrScanSize,
          height: qrScanSize,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: MobileScanner(
                  controller: _controller,
                  scanWindow: scanWindow,
                  fit: BoxFit.contain,
                  tapToFocus: true,
                  onDetect: _onDetect,
                  placeholderBuilder: (context) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '相机启动失败：${error.errorCode}',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  overlayBuilder: (context, overlayConstraints) {
                    return Center(
                      child: SizedBox(
                        width: scanWindow.width,
                        height: scanWindow.height,
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return CustomPaint(
                              painter: QrScanBoxPainter(
                                boxLineColor:
                                Theme.of(context).colorScheme.primary,
                                animationValue: _animationController.value,
                                isForward: _animationController.status ==
                                    AnimationStatus.forward,
                              ),
                              child: child,
                            );
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            if (_isInitializing)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            Positioned(
              left: 8,
              top: mediaQuery.padding.top + 8,
              child: IconButton(
                onPressed: () {
                  stop();
                  Navigator.of(context).pop();
                },
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: constraints.maxHeight == mediaQuery.size.height
                  ? 12 + mediaQuery.padding.bottom
                  : 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () async {
                      final XFile? image = await ImagePicker()
                          .pickImage(source: ImageSource.gallery);
                      if (image == null) return;
                      scanImage(image.path);
                    },
                    icon: const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 35,
                    ),
                  ),
                  IconButton(
                    onPressed: toggleTorch,
                    icon: Icon(
                      _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                      color: _torchOn ? Colors.yellow : Colors.white,
                      size: 35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class QrScanBoxPainter extends CustomPainter {
  final double animationValue;
  final bool isForward;
  final Color boxLineColor;

  QrScanBoxPainter({
    required this.animationValue,
    required this.isForward,
    required this.boxLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final borderRadius = BorderRadius.all(Radius.circular(12)).toRRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    canvas.drawRRect(
      borderRadius,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    // leftTop
    path.moveTo(0, 50);
    path.lineTo(0, 12);
    path.quadraticBezierTo(0, 0, 12, 0);
    path.lineTo(50, 0);
    // rightTop
    path.moveTo(size.width - 50, 0);
    path.lineTo(size.width - 12, 0);
    path.quadraticBezierTo(size.width, 0, size.width, 12);
    path.lineTo(size.width, 50);
    // rightBottom
    path.moveTo(size.width, size.height - 50);
    path.lineTo(size.width, size.height - 12);
    path.quadraticBezierTo(
        size.width, size.height, size.width - 12, size.height);
    path.lineTo(size.width - 50, size.height);
    // leftBottom
    path.moveTo(50, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, size.height - 50);

    canvas.drawPath(path, borderPaint);

    canvas.clipRRect(
      BorderRadius.all(Radius.circular(12)).toRRect(Offset.zero & size),
    );

    final linePaint = Paint()
      ..color = boxLineColor
      ..strokeWidth = 2.0;
    final lineY = size.height * animationValue;
    canvas.drawLine(
      Offset(0, lineY),
      Offset(size.width, lineY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(QrScanBoxPainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;

  @override
  bool shouldRebuildSemantics(QrScanBoxPainter oldDelegate) =>
      animationValue != oldDelegate.animationValue;
}