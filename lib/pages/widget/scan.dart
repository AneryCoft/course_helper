import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

class ScanPage extends StatefulWidget {
  final Function(String)? onScanResult;
  
  const ScanPage({super.key, this.onScanResult});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with TickerProviderStateMixin {
  MobileScannerController? _controller;
  String? scanResult;
  StreamSubscription<Object?>? _subscription;
  
  final int animationTime = 2000;
  AnimationController? _animationController;
  bool isScan = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  @override
  void dispose() {
    // 先停止动画控制器
    if (_animationController != null) {
      _animationController?.stop();
      _animationController?.dispose();
      _animationController = null;
    }
    
    // 再安全地停止相机
    unawaited(_subscription?.cancel());
    _controller?.stop();
    _controller = null;
    
    isScan = false;
    super.dispose();
  }

  Future<void> _initializeScanner() async {
    if (!mounted) return;
    
    try {
      _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        formats: [BarcodeFormat.qrCode],
        autoZoom: true
      );
      
      await _controller!.start();
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        startScan();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void startScan() async {
    isScan = true;
    _initAnimation();
  }

  void _initAnimation() {
    _animationController ??= AnimationController(
      vsync: this,
      duration: Duration(milliseconds: animationTime),
    )..addListener(() => setState(() {}))
      ..addStatusListener((state) {
        if (!mounted) {
          return;
        }

        if (state == AnimationStatus.completed) {
          Future.delayed(Duration(seconds: 1), () {
            if (_animationController != null && _animationController!.status != AnimationStatus.dismissed) {
              _animationController?.reverse();
            }
          });
        } else if (state == AnimationStatus.dismissed) {
          Future.delayed(Duration(seconds: 1), () {
            if (_animationController != null && _animationController!.status != AnimationStatus.forward) {
              _animationController?.forward();
            }
          });
        }
      });

    _animationController?.forward();
  }

  void stop() {
    if (!isScan) return;

    isScan = false;
    _controller?.stop();
    
    if (_animationController != null) {
      _animationController?.stop();
      _animationController?.dispose();
      _animationController = null;
    }
  }


  void scanImage(String path) async {
    try {
      final barcodeCapture = await _controller?.analyzeImage(path);
      stop();
      if (mounted && barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        final code = barcodeCapture.barcodes.first.rawValue;
        if (code != null) {
          _handleScanResult(code);
        }
      }
    } catch (e) {
      debugPrint('Failed to analyze image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, constraints) {
        final qrScanSize = constraints.maxWidth * 0.85;
        final mediaQuery = MediaQuery.of(context);

        return Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (BarcodeCapture capture) {
                if (capture.barcodes.isNotEmpty) {
                  final code = capture.barcodes.first.rawValue;
                  debugPrint('条码内容：$code');
                  if (code != null) {
                    _handleScanResult(code);
                  }
                }
              },
            ),
            // 在初始化期间显示加载指示器
            if (_isInitializing)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            Positioned(
              left: (constraints.maxWidth - qrScanSize) / 2,
              top: (constraints.maxHeight - qrScanSize) * 0.333333,
              child: CustomPaint(
                painter: QrScanBoxPainter(
                  boxLineColor: Theme.of(context).colorScheme.primary,
                  animationValue: _animationController?.value ?? 0,
                  isForward: _animationController?.status == AnimationStatus.forward,
                ),
                child: SizedBox(width: qrScanSize, height: qrScanSize),
              ),
            ),
            Positioned(
              width: constraints.maxWidth,
              bottom: constraints.maxHeight == mediaQuery.size.height ? 12 + mediaQuery.padding.bottom : 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    onPressed: () async {
                      final XFile? image = await ImagePicker().pickImage(source: ImageSource.gallery);
                      if (image == null) return;
                      scanImage(image.path);
                    },
                    icon: const Icon(Icons.photo_library, color: Colors.white, size: 35),
                  ),
                  TextButton(
                    onPressed: () {
                      stop();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      '取消', 
                      style: TextStyle(color: Colors.white, fontSize: 18)
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



  void _handleScanResult(String data) async {
    if (!mounted) return;
    
    // 先停止扫描
    stop();
    
    if (!mounted) return;
    try {
      widget.onScanResult!(data);
      Navigator.of(context).pop(data);
    } catch (e) {
      debugPrint('Navigator $e');
    }
  }
}

// 自定义扫描框绘制器
class QrScanBoxPainter extends CustomPainter {
  final double animationValue;
  final bool isForward;
  final Color boxLineColor;

  QrScanBoxPainter({
    required this.animationValue, 
    required this.isForward, 
    required this.boxLineColor
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
    path.quadraticBezierTo(size.width, size.height, size.width - 12, size.height);
    path.lineTo(size.width - 50, size.height);
    // leftBottom
    path.moveTo(50, size.height);
    path.lineTo(12, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - 12);
    path.lineTo(0, size.height - 50);

    canvas.drawPath(path, borderPaint);

    canvas.clipRRect(BorderRadius.all(Radius.circular(12)).toRRect(Offset.zero & size));

    // 绘制扫描线
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
  bool shouldRepaint(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;

  @override
  bool shouldRebuildSemantics(QrScanBoxPainter oldDelegate) => animationValue != oldDelegate.animationValue;
}