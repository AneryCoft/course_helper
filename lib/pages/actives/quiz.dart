import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/api_service.dart';
import '../../../api/quiz.dart';
import '../../../api/image.dart';
import '../../../models/user.dart';
import '../../../models/active.dart';
import '../../../session/account.dart';
import '../widget/accounts_selector.dart';

class QuizPage extends StatefulWidget {
  final Active active;
  final String courseId;
  final String classId;
  
  const QuizPage({
    super.key, 
    required this.active,
    required this.courseId,
    required this.classId
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class CountdownDisplay extends StatelessWidget {
  final ValueNotifier<String> timeNotifier;
  final bool isManualEnd;
  
  const CountdownDisplay({
    super.key, 
    required this.timeNotifier, 
    required this.isManualEnd
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: timeNotifier,
      builder: (context, time, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: isManualEnd 
              ? Colors.orange.shade100 
              : Theme.of(context).colorScheme.primaryContainer,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(
                isManualEnd ? Icons.access_time : Icons.timer,
                color: isManualEnd 
                    ? Colors.orange 
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isManualEnd ? '手动结束' : '剩余：$time',
                style: TextStyle(
                  color: isManualEnd 
                      ? Colors.orange 
                      : Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuizPageState extends State<QuizPage> {
  // 页面状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  
  // 批量提交状态
  int _totalCount = 0;
  final List<String> _failedAccounts = [];
  
  // 测验数据
  List<dynamic> _quizList = [];
  Map<String, dynamic>? _activeData;
  
  // 倒计时相关
  Timer? _countdownTimer;
  final ValueNotifier<String> _remainingTimeNotifier = ValueNotifier('');
  bool _isManualEnd = false; // 手动结束标记
  
  // 输入控制器缓存
  final Map<String, TextEditingController> _controllers = {};
  
  // 账号选择
  List<User> _selectedAccounts = [];
  User? _currentUser;
  
  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  Future<void> _initialize() async {
    // 先请求HTML并检查活动状态
    try {
      final response = await ApiService.sendRequest(widget.active.url, responseType: ResponseType.plain);
      String htmlContent = response.data.toString();
      
      // 使用正则表达式匹配activeStatus
      RegExp activeStatusRegex = RegExp(r'activeStatus: (.+?),');
      Match? statusMatch = activeStatusRegex.firstMatch(htmlContent);
      
      if (statusMatch != null) {
        String status = statusMatch.group(1)!;

        if (status == 'undefined') {
          await _loadQuizDataFromHtml(htmlContent);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = '您已提交过本次测验';
          });
        }
      } else {
        // 没有找到activeStatus，正常加载
        await _loadQuizDataFromHtml(htmlContent);
      }
    } catch (e) {
      setState(() {
        _errorMessage = '检查活动状态失败: $e';
        _isLoading = false;
      });
    }
  }

  void _startCountdown() {
    // 解析活动结束时间
    final endTime = _activeData?['endTime'];
    final isManualEnd = _activeData?['endTime'] == null;
    
    setState(() {
      _isManualEnd = isManualEnd;
    });
    
    if (isManualEnd) {
      // 手动结束情况
      _remainingTimeNotifier.value = '手动结束';
      return;
    }
    
    if (endTime != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final remaining = endTime - now;
        
        if (remaining <= 0) {
          _remainingTimeNotifier.value = '0分钟';
          timer.cancel();
          return;
        }
        
        final minutes = (remaining / 60000).floor();
        final seconds = ((remaining % 60000) / 1000).floor();
        
        // 构造新时间字符串
        String newTime;
        if (minutes > 0) {
          newTime = '$minutes分$seconds秒';
        } else {
          newTime = '$seconds秒';
        }
        
        // 只在时间真正改变时更新ValueNotifier
        if (_remainingTimeNotifier.value != newTime) {
          _remainingTimeNotifier.value = newTime;
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _remainingTimeNotifier.dispose();
    // 清理所有输入控制器
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  Future<void> _loadQuizDataFromHtml(String htmlContent) async {
    try {
      // 提取 quizList 数据 - 使用更精确的正则表达式
      // 匹配 quizList = 开头，直到 ]; 结尾（数组结束）
      RegExp quizListRegex = RegExp(r'quizList\s*=\s*(\[.*?\]);', multiLine: true, dotAll: true);
      RegExp activeRegex = RegExp(r'active\s*=\s*(\{.*?\});', multiLine: true, dotAll: true);
        
      Match? quizListMatch = quizListRegex.firstMatch(htmlContent);
      Match? activeMatch = activeRegex.firstMatch(htmlContent);
        
      if (quizListMatch != null && activeMatch != null) {
        String quizListJson = quizListMatch.group(1)!;
        String activeJson = activeMatch.group(1)!;
        
        // 解析JSON数据
        List<dynamic> quizList = json.decode(quizListJson);
        Map<String, dynamic> activeData = json.decode(activeJson);
        
        setState(() {
          _quizList = quizList;
          _activeData = activeData;
          _isLoading = false;
          
          // 初始化每个题目的答题数据
          for (var quiz in _quizList) {
            if (quiz['personAnswer'] == null) {
              quiz['personAnswer'] = {};
            }
            
            // 根据题目类型初始化答题数据
            switch (quiz['type']) {
              case 0: // 单选题
              case 1: // 多选题
              case 3: // 判断题
              case 16: // 判断题
                quiz['personAnswer']['myoption'] = '';
                break;
              case 2: // 填空题
              case 9: // 分录题
              case 10: // 资料题
                if (quiz['personAnswer']['blankAnswer'] == null) {
                  quiz['personAnswer']['blankAnswer'] = [];
                  // 初始化填空题的空格
                  if (quiz['answer'] != null) {
                    for (int i = 0; i < quiz['answer'].length; i++) {
                      quiz['personAnswer']['blankAnswer'].add({'content': ''});
                    }
                  }
                }
                break;
              case 4: // 简答题
              case 5: // 名词解释
              case 6: // 论述题
              case 7: // 计算题
              case 18: // 口语题
                quiz['personAnswer']['content'] = '';
                if (quiz['personAnswer']['recs'] == null) {
                  quiz['personAnswer']['recs'] = [];
                }
                if (quiz['personAnswer']['imgs'] == null) {
                  quiz['personAnswer']['imgs'] = [];
                }
                break;
            }
          }
          
          // 启动倒计时
          if (_activeData != null) {
            _startCountdown();
          }
        });
      } else {
        setState(() {
          _errorMessage = '解析测验数据失败';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据出错: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadQuizData() async {
    try {
      final response = await ApiService.sendRequest(widget.active.url, responseType: ResponseType.plain);
      
      // 解析HTML中的JavaScript数据
      String htmlContent = response.data.toString();
        
        // 提取 quizList 数据
        RegExp quizListRegex = RegExp(r'quizList\s*=\s*(\[.*?\]);', multiLine: true, dotAll: true);
        RegExp activeRegex = RegExp(r'active\s*=\s*(\{.*?\});', multiLine: true, dotAll: true);
        
        Match? quizListMatch = quizListRegex.firstMatch(htmlContent);
        Match? activeMatch = activeRegex.firstMatch(htmlContent);
        
        if (quizListMatch != null && activeMatch != null) {
          String quizListJson = quizListMatch.group(1)!;
          String activeJson = activeMatch.group(1)!;
          
          // 解析JSON数据
          List<dynamic> quizList = json.decode(quizListJson);
          Map<String, dynamic> activeData = json.decode(activeJson);
          
          setState(() {
            _quizList = quizList;
            _activeData = activeData;
            _isLoading = false;
            
            // 初始化每个题目的答题数据
            for (var quiz in _quizList) {
              if (quiz['personAnswer'] == null) {
                quiz['personAnswer'] = {};
              }
              
              // 根据题目类型初始化答题数据
              switch (quiz['type']) {
                case 0: // 单选题
                case 1: // 多选题
                case 3: // 判断题
                case 16: // 判断题
                  quiz['personAnswer']['myoption'] = '';
                  break;
                case 2: // 填空题
                case 9: // 分录题
                case 10: // 资料题
                  if (quiz['personAnswer']['blankAnswer'] == null) {
                    quiz['personAnswer']['blankAnswer'] = [];
                    // 初始化填空题的空格
                    if (quiz['answer'] != null) {
                      for (int i = 0; i < quiz['answer'].length; i++) {
                        quiz['personAnswer']['blankAnswer'].add({'content': ''});
                      }
                    }
                  }
                  break;
                case 4: // 简答题
                case 5: // 名词解释
                case 6: // 论述题
                case 7: // 计算题
                case 18: // 口语题
                  quiz['personAnswer']['content'] = '';
                  if (quiz['personAnswer']['recs'] == null) {
                    quiz['personAnswer']['recs'] = [];
                  }
                  if (quiz['personAnswer']['imgs'] == null) {
                    quiz['personAnswer']['imgs'] = [];
                  }
                  break;
              }
            }
            
            // 启动倒计时
            if (_activeData != null) {
              _startCountdown();
            }
          });
        } else {
          setState(() {
            _errorMessage = '解析测验数据失败';
            _isLoading = false;
          });
        }
    } catch (e) {
      setState(() {
        _errorMessage = '加载数据出错: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAnswersForAllAccounts() async {
    if (_selectedAccounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择至少一个账号')),
        );
      }
      return;
    }
    
    // 先检查活动状态
    final status = await QuizApi.checkStatus(widget.classId, widget.active.id);
    if (status != null && !status){
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('活动已结束')),
        );
        return;
      }
    }
    
    setState(() {
      _isSubmitting = true;
      _totalCount = _selectedAccounts.length;
      _failedAccounts.clear();
    });

    final submitData = jsonEncode(_constructSubmitData());

    try {
      for (var account in _selectedAccounts) {
        AccountManager.setCurrentSessionTemp(account.uid);
        try {
          final result = await QuizApi.submitAnswer(
              widget.classId, widget.courseId, widget.active.id, submitData
          );
          
          if (result != null && result['result'] != 1) {
            _failedAccounts.add('${account.name}: ${result['errorMsg'] ?? '提交失败'}');
          }
        } catch (e) {
          _failedAccounts.add('${account.name}: 异常 - $e');
        } finally {
          setState(() {
          });
        }
      }
      
      // 恢复当前账号
      if (_currentUser != null) {
        AccountManager.setCurrentSessionTemp(_currentUser!.uid);
      }
      
      _showSubmitResult();
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<dynamic> _constructSubmitData() {
    // 构造要提交的数据格式
    return _quizList.map((quiz) {
      final quizData = Map<String, dynamic>.from(quiz);
      
      // 检查并自动填充未作答的题目
      _autoFillAnswers(quizData);

      return quizData;
    }).toList();
  }
  
  void _autoFillAnswers(Map<String, dynamic> quizData) {
    final quizType = quizData['type'];
    final answers = quizData['answer'] as List?;
    
    if (answers == null || answers.isEmpty) return;
    
    switch (quizType) {
      case 0: // 单选题
      case 3: // 判断题
      case 16: // 判断题
        if (quizData['personAnswer']['myoption'] == null || 
            quizData['personAnswer']['myoption'] == '') {
          // 寻找正确答案
          final correctOption = answers.firstWhere(
            (option) => option['isanswer'] == true,
            orElse: () => answers.first, // 如果找不到正确答案，选择第一个
          );
          quizData['personAnswer']['myoption'] = correctOption['name'];
        }
        break;
        
      case 1: // 多选题
        if (quizData['personAnswer']['myoption'] == null || 
            quizData['personAnswer']['myoption'] == '') {
          // 寻找所有正确答案
          final correctOptions = answers
              .where((option) => option['isanswer'] == true)
              .map((option) => option['name'] as String)
              .toList();

          quizData['personAnswer']['myoption'] = correctOptions.join('');
        }
        break;
        
      case 2: // 填空题
        final blankAnswers = quizData['personAnswer']['blankAnswer'] as List?;
        if (blankAnswers != null) {
          for (int i = 0; i < blankAnswers.length; i++) {
            final blank = blankAnswers[i];
            if (blank['content'] == null || blank['content'] == '') {
              // 使用对应位置的正确答案（提取纯文本，分号分隔取第一个）
              if (i < answers.length) {
                final correctAnswer = answers[i];
                final htmlContent = correctAnswer['content'] ?? '';
                final textContent = _extractTextFromHtml(htmlContent);
                blank['content'] = textContent.split(';').first.trim();
              }
            }
          }
        }
        break;
        
      case 4: // 简答题
        if (quizData['personAnswer']['content'] == null || 
            quizData['personAnswer']['content'] == '') {
          if (answers.isNotEmpty) {
            // 使用第一个答案
            final correctAnswer = answers[0];
            final htmlAnswer = correctAnswer['answer'] ?? '';
            // 如果有多个答案用分号分隔，只取第一个
            // 不分割其实也算分
            final textAnswer = _extractTextFromHtml(htmlAnswer);
            final firstAnswer = textAnswer.split(';').first.trim();
            quizData['personAnswer']['content'] = firstAnswer;
          }
        }
        break;
    }
  }

  void _showSubmitResult() {
    if (!mounted) return;

    final successCount = _totalCount - _failedAccounts.length;
    String message = '答案提交完成！\n成功: $successCount/$_totalCount';
    if (_failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${_failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == _totalCount ? '全部提交成功' : '部分失败',
          style: TextStyle(
            color: successCount == _totalCount 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.error,
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

  Widget _buildQuizItem(dynamic quiz, int index) {
    final quizType = quiz['type'];
    final isMust = quiz['ismust'] == 1;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题目标题
            Row(
              children: [
                Text(
                  '${index + 1}. ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isMust)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '必答',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${_getQuizTypeName(quizType)}] ',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SelectionArea(
                        child: Html(
                          data: quiz['content'] ?? '',
                          extensions: [
                            ImageExtension(
                              builder: (context) {
                                final imageUrl = CXImageApi.toNewImageUrl(context.attributes['src'] ?? '');
                                return Image.network(
                                  imageUrl,
                                  headers: HeadersManager.chaoxingHeaders,
                                  width: 80,
                                  alignment: Alignment.bottomCenter
                                );
                              }
                            )
                          ]
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // 题目选项或输入框
            _buildQuizContent(quiz, index),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizContent(dynamic quiz, int index) {
    final quizType = quiz['type'];
    
    switch (quizType) {
      case 0: // 单选题
      case 3: // 判断题
      case 16: // 判断题
        return _buildSingleChoiceOptions(quiz, index);
      
      case 1: // 多选题
        return _buildMultipleChoiceOptions(quiz, index);
      
      case 2: // 填空题
        return _buildBlankAnswerInputs(quiz, index);
      
      case 4: // 简答题
        return _buildShortAnswerInput(quiz, index);
      
      default:
        return const Text('暂不支持此题型');
    }
  }

  Widget _buildSingleChoiceOptions(dynamic quiz, int quizIndex) {
    final answers = quiz['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return const Text('无选项');
    }

    return RadioGroup<String>(
      groupValue: quiz['personAnswer']['myoption'],
      onChanged: (String? value) {
        setState(() {
          quiz['personAnswer']['myoption'] = value ?? '';
        });
      },
      child: Column(
        children: answers.map((option) {
          final optionLabel = _getOptionLabel(option, quiz['type']);
          final isAnswer = option['isanswer'] == true;
          final isSelected = quiz['personAnswer']['myoption'] == option['name'];

          return RadioListTile<String>(
            title: Html(
              data: option['content'] ?? '',
              extensions: [
                ImageExtension(
                  builder: (context) {
                    final imageUrl = CXImageApi.toNewImageUrl(context.attributes['src'] ?? '');
                    return Image.network(
                      imageUrl,
                      headers: HeadersManager.chaoxingHeaders,
                      width: 60,
                      alignment: Alignment.bottomCenter
                    );
                  }
                )
              ]
            ),
            secondary: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                optionLabel,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white 
                      : isAnswer
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            value: option['name'],
            activeColor: Theme.of(context).colorScheme.primary,
            controlAffinity: ListTileControlAffinity.trailing,
            toggleable: true,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMultipleChoiceOptions(dynamic quiz, int quizIndex) {
    final answers = quiz['answer'] as List?;
    if (answers == null || answers.isEmpty) {
      return const Text('无选项');
    }
    
    return Column(
      children: answers.map((option) {
        final optionLabel = _getOptionLabel(option, quiz['type']);
        final isAnswer = option['isanswer'] == true;
        final selectedOptions = (quiz['personAnswer']['myoption'] as String?)?.split('') ?? [];
        final isSelected = selectedOptions.contains(option['name']);
        
        return CheckboxListTile(
          title: Html(
            data: option['content'] ?? '',
            extensions: [
              ImageExtension(
                builder: (context) {
                  final imageUrl = CXImageApi.toNewImageUrl(context.attributes['src'] ?? '');
                  return Image.network(
                    imageUrl,
                    headers: HeadersManager.chaoxingHeaders,
                    width: 60,
                    alignment: Alignment.bottomCenter
                  );
                }
              )
            ]
          ),
          secondary: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              optionLabel,
              style: TextStyle(
                color: isSelected ?
                Colors.white : isAnswer ?
                Theme.of(context).colorScheme.primary : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          value: isSelected,
          onChanged: (value) {
            setState(() {
              if (value == true) {
                if (!selectedOptions.contains(option['name'])) {
                  selectedOptions.add(option['name']);
                }
              } else {
                selectedOptions.remove(option['name']);
              }
              // 按字母顺序排序后拼接
              selectedOptions.sort();
              quiz['personAnswer']['myoption'] = selectedOptions.join('');
            });
          },
          activeColor: Theme.of(context).colorScheme.primary,
        );
      }).toList(),
    );
  }

  /// 从HTML中提取纯文本
  String _extractTextFromHtml(String html) {
    try {
      String text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
      text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      return text;
    } catch (e) {
      return html;
    }
  }

  /// 从HTML中提取图片URL列表
  List<String> _extractImageUrls(String html) {
    final urls = <String>[];
    try {
      final regex = RegExp("<img[^>]+src=[\"']([^\"']+)[\"']");
      final matches = regex.allMatches(html);
      for (final match in matches) {
        if (match.groupCount >= 1) {
          final url = match.group(1);
          if (url != null && url.isNotEmpty) {
            urls.add(CXImageApi.toNewImageUrl(url));
          }
        }
      }
    } catch (e) {
      debugPrint('提取图片URL失败: $e');
    }
    return urls;
  }

  /// 放大图片对话框
  void _showImageDialog(String url, String heroTag) {
    showDialog(
      context: context,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black12,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Hero(
                tag: heroTag,
                child: Image.network(
                    url,
                    headers: HeadersManager.chaoxingHeaders,
                    fit: BoxFit.contain
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 为简答题选择并上传图片
  Future<void> _pickImages(dynamic quiz, int quizIndex) async {
    try {
      final ImagePicker picker = ImagePicker();

      final List<XFile> images = await picker.pickMultiImage(imageQuality: 80);

      if (images.isNotEmpty) {
        final uploadFutures = images.map((image) async {
          try {
            final file = File(image.path);
            final objectId = await CXImageApi.uploadImage(file, AccountManager.currentSessionId ?? '');
            if (objectId != null) {
              return {'image': image, 'objectId': objectId};
            }
            return null;
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
              if (result != null && result['objectId'] != null) {
                final xfile = result['image'] as XFile;
                final objectId = result['objectId'] as String;

                quiz['personAnswer']['recs'].add({
                  'name': xfile.name, // 这里应该是上传的名字 但是没有校验
                  'objectid': objectId,
                  'suffix': xfile.path.split('.').last,
                  'type': '1',
                  "preview": "",
                  "thumbnail": ""
                });
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

  /// 删除简答题的图片
  void _removeShortAnswerImage(dynamic quiz, int index) {
    setState(() {
      quiz['personAnswer']['recs'].removeAt(index);
    });
  }

  Widget _buildBlankAnswerInputs(dynamic quiz, int quizIndex) {
    final blankAnswers = quiz['personAnswer']['blankAnswer'] as List?;
    final correctAnswers = quiz['answer'] as List?;
    if (blankAnswers == null || blankAnswers.isEmpty) {
      return const Text('无填空');
    }
      
    return Column(
      children: blankAnswers.asMap().entries.map((entry) {
        final index = entry.key;
        final blank = entry.value;
        final correctAnswer = correctAnswers != null && index < correctAnswers.length 
            ? correctAnswers[index]['content'] ?? ''
            : '';
        
        // 提取纯文本并处理分号分隔
        final hintText = correctAnswer.isNotEmpty ?
        _extractTextFromHtml(correctAnswer).split(';').first.trim() : '请输入答案';
        // 提取图片
        final imageUrls = correctAnswer.isNotEmpty ? _extractImageUrls(correctAnswer) : <String>[];
        
        // 为每个输入框创建唯一的 key
        final controllerKey = 'blank_${quizIndex}_$index';
        final controller = _controllers.putIfAbsent(controllerKey, 
          () => TextEditingController(text: blank['content'] ?? ''));
          
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('第${index + 1}空：', style: const TextStyle(color: Colors.grey)),
              Stack(
                children: [
                  TextField(
                    key: ValueKey(controllerKey),
                    maxLines: imageUrls.isNotEmpty ? 2 : 1,
                    decoration: InputDecoration(
                      hintText: hintText,
                      border: const OutlineInputBorder(),
                      contentPadding: imageUrls.isNotEmpty ?
                      const EdgeInsets.fromLTRB(12, 12, 12, 60) : const EdgeInsets.all(12),
                    ),
                    controller: controller,
                    onChanged: (value) {
                      setState(() {
                        blank['content'] = value;
                      });
                    },
                  ),
                  if (imageUrls.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(maxHeight: 50),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: imageUrls.asMap().entries.map((imgEntry) {
                              final imgIndex = imgEntry.key;
                              final url = imgEntry.value;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () => _showImageDialog(url, 'blank_image_${quizIndex}_${index}_$imgIndex'),
                                  child: Hero(
                                    tag: 'blank_image_${quizIndex}_${index}_$imgIndex',
                                    child: Image.network(
                                      url,
                                      headers: HeadersManager.chaoxingHeaders,
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildShortAnswerInput(dynamic quiz, int quizIndex) {
    // 获取简答题的正确答案
    final correctAnswers = quiz['answer'] as List?;
    final correctAnswer = correctAnswers != null && correctAnswers.isNotEmpty
        ? correctAnswers[0]['answer'] ?? ''
        : '';
      
    // 为简答题创建唯一的 key
    final controllerKey = 'short_$quizIndex';
    // 获取或创建 controller
    final controller = _controllers.putIfAbsent(controllerKey,
      () => TextEditingController(text: quiz['personAnswer']['content'] ?? ''));
    
    // 分离HTML中的文本和图片
    final hintText = correctAnswer.isNotEmpty ? _extractTextFromHtml(correctAnswer) : '请输入答案';
    final imageUrls = correctAnswer.isNotEmpty ? _extractImageUrls(correctAnswer) : <String>[];
    
    // 获取已上传的图片列表
    final uploadedImages = quiz['personAnswer']['recs'] as List? ?? [];
      
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                height: 150,
                child: Stack(
                  children: [
                    TextField(
                      key: ValueKey(controllerKey),
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: hintText,
                        border: const OutlineInputBorder(),
                      ),
                      controller: controller,
                      onChanged: (value) {
                        setState(() {
                          quiz['personAnswer']['content'] = value;
                        });
                      },
                    ),
                    if (imageUrls.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(maxHeight: 60),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: imageUrls.asMap().entries.map((entry) {
                                final index = entry.key;
                                final url = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => _showImageDialog(url, 'quiz_image_${quizIndex}_$index'),
                                    child: Hero(
                                      tag: 'quiz_image_${quizIndex}_$index',
                                      child: Image.network(
                                        url,
                                        headers: HeadersManager.chaoxingHeaders,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 32),
              onPressed: () => _pickImages(quiz, quizIndex),
              tooltip: '添加图片',
            ),
          ],
        ),
        if (uploadedImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: uploadedImages.length,
              itemBuilder: (context, index) {
                final imageInfo = uploadedImages[index];
                final objectId = imageInfo['objectid'] as String?;
                if (objectId == null || objectId.isEmpty) {
                  return const SizedBox.shrink();
                }
                final imageUrl = CXImageApi.getImageUrl(objectId);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () => _showImageDialog(imageUrl, 'short_answer_image_${quizIndex}_$index'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Hero(
                            tag: 'short_answer_image_${quizIndex}_$index',
                            child: Image.network(
                              imageUrl,
                              headers: HeadersManager.chaoxingHeaders,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: () => _removeShortAnswerImage(quiz, index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  String _getQuizTypeName(int type) {
    const typeNames = {
      0: '单选题',
      1: '多选题',
      2: '填空题',
      3: '判断题',
      4: '简答题',
      16: '判断题'
    };
    return typeNames[type] ?? '未知题型';
  }

  String _getOptionLabel(dynamic option, int quizType) {
    if (quizType == 16) {
      final optionName = option['name'] ?? '';
      return optionName == '1' ? '对' : '错';
    }
    return option['name'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.active.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 倒计时显示区域
          if (_activeData != null)
            CountdownDisplay(
              timeNotifier: _remainingTimeNotifier,
              isManualEnd: _isManualEnd,
            ),
          
          // 主要内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadQuizData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                )
              : _quizList.isEmpty
                  ? const Center(child: Text('暂无题目'))
                  : Column(
                      children: [
                        // 题目列表
                        Expanded(
                          child: ListView.builder(
                            itemCount: _quizList.length,
                            itemBuilder: (context, index) {
                              return _buildQuizItem(_quizList[index], index);
                            },
                          ),
                        ),
                        
                        // 账号选择器
                        AccountsSelector(
                          onSelectionChanged: (selected) {
                            setState(() {
                              _selectedAccounts = selected;
                            });
                          },
                          initiallyExpanded: false,
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // 提交按钮
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _submitAnswersForAllAccounts,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: _isSubmitting
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Text('提交中...'),
                                    ],
                                  )
                                : const Text('提交', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}