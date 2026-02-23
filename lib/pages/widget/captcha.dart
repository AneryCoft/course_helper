import 'package:flutter/material.dart';
import '../../api/captcha.dart';

class CaptchaPage extends StatefulWidget {
  final String? referer;
  final bool isSlideCaptcha;
  const CaptchaPage({super.key, this.referer, this.isSlideCaptcha = false});

  @override
  CaptchaPageState createState() => CaptchaPageState();

  static Future<String?> showSlideCaptchaDialog(BuildContext context, {String? referer}) async {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CaptchaPage(
          referer: referer,
          isSlideCaptcha: true,
        );
      },
    );
  }
}

class CaptchaPageState extends State<CaptchaPage> {
  bool _isLoadingSlide = false;
  String? _token;
  String? _shadeImageUrl;
  String? _cutoutImageUrl;
  double _sliderPosition = 0.0;          // 实际渲染坐标系下的滑块位置
  bool _isDragging = false;
  bool _hasSubmitted = false;

  final CaptchaApi _captchaApi = CaptchaApi();

  // 固定设计尺寸（与服务器约定的一致）
  static final double backgroundWidth = 320.0;
  static final double backgroundHeight = 160.0;
  static final double cutoutWidth = 56.0;
  static final double cutoutHeight = 160.0;

  // 设计尺寸下的最大物理滑动距离
  static final double designMaxButtonPhysical = backgroundWidth - cutoutWidth; // 264.0
  static final double ratio = 280.0 / 264.0;  // 设计稿中滑块位置到缺口左边界的映射系数

  // 实际渲染尺寸（动态获取）
  double _actualBgWidth = backgroundWidth;
  double _actualCutoutWidth = cutoutWidth;
  double? _originalImageWidth;  // 从服务器获取的原始图片宽度（若返回）

  // GlobalKey 用于获取实际渲染尺寸
  final GlobalKey _bgImageKey = GlobalKey();
  final GlobalKey _cutoutImageKey = GlobalKey();

  // 实际最大物理滑动距离（基于实际渲染宽度）
  double get maxButtonPhysical => _actualBgWidth - _actualCutoutWidth;

  @override
  void initState() {
    super.initState();
    if (widget.isSlideCaptcha) {
      _loadSlideCaptcha();
    }
  }

  // 获取实际渲染尺寸（需在布局完成后调用）
  void _updateActualSizes() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 获取背景图实际宽度
      final bgContext = _bgImageKey.currentContext;
      if (bgContext != null) {
        final bgRenderBox = bgContext.findRenderObject() as RenderBox?;
        if (bgRenderBox != null && bgRenderBox.hasSize) {
          setState(() {
            _actualBgWidth = bgRenderBox.size.width;
          });
        }
      }
      // 获取缺口图实际宽度
      final cutoutContext = _cutoutImageKey.currentContext;
      if (cutoutContext != null) {
        final cutoutRenderBox = cutoutContext.findRenderObject() as RenderBox?;
        if (cutoutRenderBox != null && cutoutRenderBox.hasSize) {
          setState(() {
            _actualCutoutWidth = cutoutRenderBox.size.width;
          });
        }
      }
    });
  }

  Future<void> _loadSlideCaptcha() async {
    setState(() => _isLoadingSlide = true);

    try {
      Map<String, dynamic>? result = await _captchaApi.getCaptchaImages(widget.referer ?? '');

      if (result != null && result.containsKey('token')) {
        setState(() {
          _token = result['token'] as String;
          _shadeImageUrl = result['imageVerificationVo']['shadeImage'] as String;
          _cutoutImageUrl = result['imageVerificationVo']['cutoutImage'] as String;
          // 如果服务器返回了原始图片宽度，则记录
          if (result['imageVerificationVo'].containsKey('originalWidth')) {
            _originalImageWidth = (result['imageVerificationVo']['originalWidth'] as num).toDouble();
          }
          _isLoadingSlide = false;
          _sliderPosition = 0.0;
        });
        // 图片加载后获取实际尺寸
        _updateActualSizes();
      } else {
        _showError('获取验证码失败');
        setState(() => _isLoadingSlide = false);
      }
    } catch (e) {
      _showError('加载验证码时出错: $e');
      setState(() => _isLoadingSlide = false);
    }
  }

  // 根据实际滑块位置计算提交给服务器的缺口左边界（基于原始图片坐标系）
  double get cutoutLeft {
    // 1. 将实际滑块位置转换为设计尺寸下的滑块位置
    double designSliderPos = _sliderPosition * (backgroundWidth / _actualBgWidth);
    // 2. 按原公式计算设计尺寸下的缺口左边界
    double designCutoutLeft = designSliderPos * ratio - 8.0;
    // 3. 如果有原始图片宽度，转换为原始坐标系；否则直接返回设计尺寸坐标（假设服务器接受设计尺寸）
    if (_originalImageWidth != null && _originalImageWidth! > 0) {
      return designCutoutLeft * (_originalImageWidth! / backgroundWidth);
    }
    return designCutoutLeft;
  }

  Future<void> _submitSlideCaptcha() async {
    if (_hasSubmitted) return;

    if (_sliderPosition <= 0.1) { // 允许微小误差
      _showError('请拖动滑块完成验证');
      return;
    }

    if (_token == null || _token!.isEmpty) {
      _showError('验证码未加载完成，请稍后再试');
      return;
    }

    setState(() {
      _hasSubmitted = true;
    });

    try {
      String? validate = await _captchaApi.submitCaptcha(cutoutLeft, _token!, widget.referer ?? '');

      if (validate != null && validate.isNotEmpty) {
        if (mounted) {
          Navigator.pop(context, validate);
        }
      } else {
        _showError('验证失败，请重试');
        await _loadSlideCaptcha();
        setState(() {
          _sliderPosition = 0.0;
          _hasSubmitted = false;
        });
      }
    } catch (e) {
      _showError('提交验证时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('滑块验证'),
      contentPadding: EdgeInsets.zero,
      content: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          child: _buildSlideCaptchaDialogContent(),
        ),
      ),
    );
  }

  Widget _buildSlideCaptchaDialogContent() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请拖动滑块填充拼图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          _buildSlideCaptchaContainer(),
        ],
      ),
    );
  }

  Widget _buildSlideCaptchaContainer() {
    Color borderColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.grey.shade700
        : Colors.grey.shade300;

    return SizedBox(
      width: backgroundWidth,
      height: backgroundHeight + 60,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 背景图（添加 key 以获取实际尺寸）
          if (_shadeImageUrl != null)
            Image.network(
              _shadeImageUrl!,
              key: _bgImageKey,
              width: backgroundWidth,
              height: backgroundHeight,
              fit: BoxFit.fill,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: backgroundWidth,
                  height: backgroundHeight,
                  color: Colors.grey.shade200,
                  child: const Center(child: Text('加载中...')),
                );
              },
              errorBuilder: (context, error, stackTrace) => Container(
                width: backgroundWidth,
                height: backgroundHeight,
                color: Colors.grey.shade200,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, color: Colors.grey.shade600, size: 40),
                      const SizedBox(height: 8),
                      Text('图片加载失败', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ),
            ),

          // 缺口图（滑块）（添加 key 以获取实际尺寸）
          if (_cutoutImageUrl != null)
            Positioned(
              left: _sliderPosition,
              top: 0,
              child: Image.network(
                _cutoutImageUrl!,
                key: _cutoutImageKey,
                width: cutoutWidth,
                height: cutoutHeight,
                fit: BoxFit.fill,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: cutoutWidth,
                  height: cutoutHeight,
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade300, width: 1),
                  ),
                  child: Icon(Icons.error, color: Colors.red.shade600, size: 30),
                ),
              ),
            ),

          // 滑块轨道
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Container(
              width: backgroundWidth,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Stack(
                children: [
                  // 滑块按钮
                  Positioned(
                    left: _sliderPosition,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanStart: (details) => setState(() => _isDragging = true),
                      onPanUpdate: (details) {
                        double newPos = _sliderPosition + details.delta.dx;
                        newPos = newPos.clamp(0.0, maxButtonPhysical); // 使用实际最大距离
                        setState(() {
                          _sliderPosition = newPos;
                        });
                      },
                      onPanEnd: (details) async {
                        setState(() => _isDragging = false);
                        _sliderPosition = _sliderPosition.clamp(0.0, maxButtonPhysical);
                        await _submitSlideCaptcha();
                      },
                      child: Container(
                        width: cutoutWidth,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 加载蒙层
          if (_isLoadingSlide)
            Container(
              width: backgroundWidth,
              height: backgroundHeight + 60,
              color: Colors.black26,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 12),
                    const Text('正在加载验证码...', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }
}