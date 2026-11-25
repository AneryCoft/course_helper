part of 'presentation.dart';

mixin _PptViewMixin on _PresentationPageStateBase {
  /// 非全屏模式下的 PPT 展示区
  Widget _buildSlideViewer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          _buildSlidePager(),
          ..._buildOverlayControls(),
        ],
      ),
    );
  }

  /// 单张幻灯片图片 普通模式与全屏模式共用
  Widget _buildSlideImage(Map<String, dynamic> slide) {
    final cover = slide['coverAlt'] as String?;
    if (cover == null) {
      return const Center(
        child: Text('暂无 PPT', style: TextStyle(color: Colors.grey)),
      );
    }
    return Center(
      child: Image.network(
        cover,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.error_outline, size: 48, color: Colors.grey),
          );
        },
      ),
    );
  }

  /// 全屏模式下的 PPT 展示区
  Widget _buildFullScreenPPT() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            children: [
              Positioned.fill(child: _buildSlidePager()),
              ..._buildOverlayControls(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlidePager() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _slides.length,
        onPageChanged: (index) {
          setState(() {
            _currentSlideIndex = index;
            _currentProblem = _slides[index]['problem'];
          });
        },
        itemBuilder: (context, index) => _buildSlideImage(_slides[index]),
      ),
    );
  }

  List<Widget> _buildOverlayControls() {
    if (!_isControlsVisible) return const [];
    return [
      Positioned(
        left: 16,
        top: 16,
        child: _buildPageIndicator(),
      ),
      Positioned(
        right: 12,
        top: 16,
        child: _buildDownloadButton(),
      ),
      Positioned(
        right: 12,
        bottom: 12,
        child: _buildFullscreenButton(),
      ),
    ];
  }

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _currentSlideIndex == _currentLessonSlideIndex
          ? RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: '当前 ',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: '${_currentSlideIndex + 1}/$_totalCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Text(
              '${_currentSlideIndex + 1}/$_totalCount',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildDownloadButton() {
    return Builder(
      builder: (context) {
        return _buildOverlayIconButton(
          icon: Icons.download,
          onPressed: _isDownloading ? null : () => _showDownloadMenu(context),
          tooltip: '下载',
          progress: _downloadProgress,
        );
      },
    );
  }

  Future<void> _toggleFullScreen() async {
    if (_isFullScreen) {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (mounted) {
      setState(() {
        _isFullScreen = !_isFullScreen;
      });
      // 全屏切换会改变 PageView 视口宽度，而 PageController 按像素保存页码，
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        if ((_pageController.page?.round() ?? 0) != _currentSlideIndex) {
          _pageController.jumpToPage(_currentSlideIndex);
        }
      });
    }
  }

  Widget _buildFullscreenButton() {
    return _buildOverlayIconButton(
      icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
      onPressed: _toggleFullScreen,
      tooltip: _isFullScreen ? '退出全屏' : '全屏',
    );
  }

  Widget _buildOverlayIconButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    double? progress,
  }) {
    return SizedBox(
      width: 24,
      height: 24,
      child: progress != null
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            )
          : IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              icon: Icon(icon, color: Colors.white, size: 24, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
              tooltip: tooltip,
            ),
    );
  }

  Widget _buildProblemPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
          bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isProblemExpanded = !_isProblemExpanded;
              });
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getProblemTypeLabel(_currentProblem!.problemType),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_currentProblem!.problemType == 3 && _currentProblem!.pollingCount != null && _currentProblem!.pollingCount! > 1)
                  Text(
                    '（最多${_currentProblem!.pollingCount}项）',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(width: 8),
                if (_currentProblem!.score > 0)
                  Text(
                    '(${(_currentProblem!.score / 100).toStringAsFixed(0)}分)',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                const Spacer(),
                if (_currentProblem != null && _unlockedProblemIds.contains(_currentProblem!.problemId) && _countdownSeconds != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_countdownSeconds! ~/ 60}:${(_countdownSeconds! % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                Icon(
                  _isProblemExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (_isProblemExpanded) ...[
            const SizedBox(height: 12),
            Text(
              _currentProblem!.body,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            _buildAnswerOptions(),
            if ((_currentProblem != null && _unlockedProblemIds.contains(_currentProblem!.problemId)) ||
                (_timelineProblemId != null && _unlockedProblemIds.contains(_timelineProblemId!))) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () async {await _submitAnswer();},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text(
                      '提交',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  )
                ]
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _submitAnswer() async {
    // 优先使用 _currentProblem，如果为空则使用 _timelineProblemId
    final problemId = _currentProblem?.problemId ?? _timelineProblemId;
    if (problemId == null) return;

    final problemType = _currentProblem?.problemType ?? 0;
    final problemDt = _currentProblem?.dt;

    // 检查是否有答案或图片
    if (_answer == null && _textAnswer == null && _uploadedImageUrls.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择或填写答案')),
        );
      }
      return;
    }

    // 判断是否超时（倒计时结束）
    final isTimeout = _countdownSeconds != null && _countdownSeconds! <= 0;

    // 为所有用户提交答案（带已上传的图片 URL）
    await _submitForAllAccounts(problemId, problemType, _uploadedImageUrls, isTimeout, problemDt);
  }

  Future<void> _submitForAllAccounts(String problemId, int problemType, List<String>? imageUrls, bool isTimeout, int? problemDt) async {
    final allAccounts = AccountManager.allAccounts;

    if (allAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的账号')),
        );
      }
      return;
    }

    int successCount = 0;
    final List<String> failedAccounts = [];

    final results = await ApiService.sendForEachUser(
      allAccounts,
      (user) async {
        final api = RCCourseApi(user);
        return await api.answer(
          problemId,
          problemType,
          retry: isTimeout,
          time: isTimeout ? problemDt : null,
          options: _answer,
          content: _textAnswer,
          imageUrls: imageUrls
        );
      },
    );

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final user = allAccounts[i];

      if (result != null && result['code'] == 0) {
        successCount++;
      } else {
        failedAccounts.add('${user.name}: ${result?["msg"] ?? "提交失败"}');
      }
    }

    _showSubmitResult(successCount, allAccounts.length, failedAccounts);

    // 提交成功后禁用按钮并清空图片
    setState(() {
      _countdownSeconds = 0;
      _selectedImages.clear();
      _uploadedImageUrls.clear();
    });
  }

  void _showSubmitResult(int successCount, int totalCount, List<String> failedAccounts) {
    if (!mounted) return;

    String message = '答案提交完成！\n成功：$successCount/$totalCount';
    if (failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == totalCount ? '全部提交成功' : '部分失败',
          style: TextStyle(
            color: successCount == totalCount ?
            Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();

    switch (_currentProblem!.problemType) {
      case 1: // 单选题 // 判断题在PPT是单选题
      case 3: // 投票题
        return _buildChoiceOptions();
      case 2: // 多选题
        return _buildMultipleChoiceOptions();
      case 4: // 填空题
        return _buildFillBlankInputs();
      case 5: // 主观题
        return _buildShortAnswerInputs();
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _pickImages() async {
    try {
      final ImagePicker picker = ImagePicker();

      final remainingCount = _PresentationPageStateBase._maxImageCount - _selectedImages.length;

      final List<XFile> images = await picker.pickMultiImage(
          limit: remainingCount,
          imageQuality: 80
      );

      if (images.isNotEmpty) {
        // 并行上传所有图片
        final uploadFutures = images.map((image) async {
          try {
            final file = File(image.path);
            final imageUrl = await RCImageApi.uploadImage(file);
            return {'image': image, 'url': imageUrl};
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('图片上传失败：${image.path}')),
              );
            }
            return null;
          }
        }).toList();

        // 等待所有上传完成
        final results = await Future.wait(uploadFutures);

        // 更新状态
        if (mounted) {
          setState(() {
            for (final result in results) {
              if (result != null && result['url'] != null) {
                _selectedImages.add(result['image'] as XFile);
                _uploadedImageUrls.add(result['url'] as String);
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择图片失败：$e')),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _uploadedImageUrls.removeAt(index);
    });
  }

  Widget _buildShortAnswerInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: '请输入答案',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                onChanged: (value) {
                  _textAnswer = value;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 32),
              onPressed: _pickImages,
              tooltip: '添加图片（最多 9 张）'
            ),
          ],
        ),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ImageThumbnail(
                    file: File(_selectedImages[index].path),
                    onDelete: () => _removeImage(index),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFillBlankInputs() {
    if (_currentProblem == null) return const SizedBox.shrink();

    final blanks = _currentProblem!.blanks;

    if (blanks.isEmpty) {
      return TextField(
        decoration: const InputDecoration(
          hintText: '请输入答案',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          _answer = [value];
        },
      );
    }

    // 多个填空，显示多个输入框
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(blanks.length, (index) {
        final blank = blanks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            decoration: InputDecoration(
              labelText: '填空${blank.num}',
              hintText: '请输入第${blank.num}个空的答案',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              // 存储所有答案
              final answers = List<String>.from(_answer ?? []);
              while (answers.length <= index) {
                answers.add('');
              }
              answers[index] = value;
              _answer = answers;
            },
          ),
        );
      }),
    );
  }

  Widget _buildChoiceOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();

    final options = _currentProblem!.options;
    if (options == null || options.isEmpty) {
      return const SizedBox.shrink();
    }

    return RadioGroup<String>(
      groupValue: _answer?.firstOrNull,
      onChanged: (value) {
        setState(() {
          _answer = value != null ? [value] : null;
        });
      },
      child: Column(
        children: options.map((option) {
          return Material(
            type: MaterialType.transparency,
            child: RadioListTile<String>(
              value: option.key,
              title: Text('${option.key}. ${option.value}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              activeColor: Theme.of(context).colorScheme.primary,
              controlAffinity: ListTileControlAffinity.trailing,
              toggleable: true,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMultipleChoiceOptions() {
    if (_currentProblem == null) return const SizedBox.shrink();

    final options = _currentProblem!.options;
    if (options == null || options.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: options.map((option) {
        final key = option.key;
        final isSelected = (_answer ?? []).contains(key);
        return Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: isSelected,
            title: Text('$key. ${option.value}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            activeColor: Theme.of(context).colorScheme.primary,
            controlAffinity: ListTileControlAffinity.trailing,
            onChanged: (value) {
              setState(() {
                final selectedKeys = _answer?.toSet() ?? <String>{};
                if (value == true) {
                  selectedKeys.add(key);
                } else {
                  selectedKeys.remove(key);
                }
                _answer = selectedKeys.toList();
              });
            },
          ),
        );
      }).toList(),
    );
  }

  String get _pptTitle =>
      _currentPresentationTitle?.isNotEmpty == true
          ? _currentPresentationTitle!
          : widget.title;

  double? get _downloadProgress =>
      _isDownloading && _downloadTotal > 0
          ? _downloadedCount / _downloadTotal
          : null;

  Future<void> _showDownloadMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay)
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(
          value: 'current',
          child: Text('下载当前页'),
        ),
        PopupMenuItem<String>(
          value: 'all',
          child: Text('下载所有页'),
        ),
      ],
    );

    if (result == 'current') {
      await _downloadCurrentPage();
    } else if (result == 'all') {
      await _downloadAllPages();
    }
  }

  Future<void> _downloadCurrentPage() async {
    String? cover;
    if (_slides.isNotEmpty && _currentSlideIndex < _slides.length) {
      cover = _slides[_currentSlideIndex]['coverAlt'] as String?;
    }
    if (cover == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可下载的页面')),
        );
      }
      return;
    }

    try {
      await _saveSlide(cover, title: '$_pptTitle-${_currentSlideIndex + 1}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _downloadAllPages() async {
    if (_isDownloading) return;

    final covers = _slides
        .map((slide) => slide['coverAlt'] as String?)
        .whereType<String>()
        .toList();

    if (covers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可下载的页面')),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadedCount = 0;
      _downloadTotal = covers.length;
    });

    int success = 0;
    final relativePath = 'Pictures/$_pptTitle';
    for (int i = 0; i < covers.length; i++) {
      try {
        await _saveSlide(
          covers[i],
          title: '${i + 1}',
          relativePath: relativePath,
        );
        success++;
      } catch (e) {
        logger.e('保存第 ${i + 1} 页失败：$e');
      }
      if (mounted) {
        setState(() {
          _downloadedCount = i + 1;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $success/${covers.length} 页')),
      );
    }
  }

  Future<void> _saveSlide(
    String imageUrl, {
    required String title,
    String? relativePath,
  }) async {
    // 从缓存中获取图片文件
    final file = await DefaultCacheManager().getSingleFile(imageUrl);
    final bytes = await file.readAsBytes();

    await PhotoManager.editor.saveImage(
      bytes,
      filename: '$title.jpg',
      title: title,
      relativePath: relativePath,
    );
  }
}
