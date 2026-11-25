import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

import '../../api/image.dart';
import '../../models/course.dart';
import '../../setting/course_setting.dart';
import '../widget/map.dart';
import '../widget/image_thumbnail.dart';


class CourseSettingsPage extends StatefulWidget {
  final String courseId;

  const CourseSettingsPage({
    super.key,
    required this.courseId,
  });

  @override
  State<CourseSettingsPage> createState() => _CourseSettingsPageState();
}

class _CourseSettingsPageState extends State<CourseSettingsPage> {
  late TextEditingController _classroomController;
  late TextEditingController _addressController;
  late TextEditingController _latitudeController;
  late TextEditingController _longitudeController;
  List<String> _imageObjectIds = [];
  final Map<String, String> _localImagePaths = {};
  bool _isLoading = false;
  String? _addressError;
  String? _latitudeError;
  String? _longitudeError;

  @override
  void initState() {
    super.initState();
    _classroomController = TextEditingController();
    _addressController = TextEditingController();
    _latitudeController = TextEditingController();
    _longitudeController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await CourseSetting.getSettings(widget.courseId);
    if (mounted) {
      setState(() {
        _classroomController.text = settings?.location?.classroom ?? '';
        _addressController.text = settings?.location?.address ?? '';
        _latitudeController.text = settings?.location?.latitude ?? '';
        _longitudeController.text = settings?.location?.longitude ?? '';
        _imageObjectIds = settings?.imageObjectIds ?? [];
      });
    }
  }

  @override
  void dispose() {
    _classroomController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      List<XFile> pickedFiles;
      
      if (source == ImageSource.gallery) {
        pickedFiles = await picker.pickMultiImage();
      } else {
        final pickedFile = await picker.pickImage(source: source);
        if (pickedFile == null) return;
        pickedFiles = [pickedFile];
      }
      
      if (pickedFiles.isEmpty) return;

      final uploadFutures = pickedFiles.map((pickedFile) async {
        final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        setState(() {
          _imageObjectIds.add(tempId);
          _localImagePaths[tempId] = pickedFile.path;
        });

        try {
          final api = CXImageApi();
          final objectId = await api.uploadImage(File(pickedFile.path));

          if (objectId != null) {
            setState(() {
              final index = _imageObjectIds.indexOf(tempId);
              if (index != -1) {
                _imageObjectIds[index] = objectId;
                _localImagePaths.remove(tempId);
                _localImagePaths[objectId] = pickedFile.path;
              }
            });
            return true;
          } else {
            setState(() {
              _imageObjectIds.remove(tempId);
              _localImagePaths.remove(tempId);
            });
            return false;
          }
        } catch (e) {
          setState(() {
            _imageObjectIds.remove(tempId);
            _localImagePaths.remove(tempId);
          });
          return false;
        }
      }).toList();

      final results = await Future.wait(uploadFutures);
      final successCount = results.where((r) => r).length;
      final failCount = results.length - successCount;

      if (mounted) {
        if (failCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功上传 $successCount 张图片')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('上传完成：成功 $successCount 张，失败 $failCount 张')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片错误：$e')),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      final objectId = _imageObjectIds[index];
      _imageObjectIds.removeAt(index);
      _localImagePaths.remove(objectId);
    });
  }

  void _showMapPicker() {
    MapPoint? selectedCoordinate;
    String? selectedAddress;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('选择位置'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          body: Column(
            children: [
              Expanded(
                child: LocationMapWidget(
                  showLocationButton: true,
                  showCurrentLocationInfo: true,
                  onLocationSelectedWithAddress: (coordinate, address) {
                    selectedCoordinate = coordinate;
                    selectedAddress = address;
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _latitudeController.text = selectedCoordinate!.latitude.toStringAsFixed(6);
                          _longitudeController.text = selectedCoordinate!.longitude.toStringAsFixed(6);
                          _addressController.text = selectedAddress?.isEmpty ?? true
                              ? '未知位置'
                              : selectedAddress!;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('确认选择'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    final latText = _latitudeController.text.trim();
    final lonText = _longitudeController.text.trim();
    final addressText = _addressController.text.trim();

    final hasAddress = addressText.isNotEmpty;
    final hasLat = latText.isNotEmpty;
    final hasLon = lonText.isNotEmpty;
    
    String? addressError;
    String? latitudeError;
    String? longitudeError;
    
    if (hasAddress && (!hasLat || !hasLon)) {
      latitudeError = !hasLat ? '请填写纬度' : null;
      longitudeError = !hasLon ? '请填写经度' : null;
    } else if (!hasAddress && (hasLat || hasLon)) {
      addressError = '请填写地址';
    }
    
    if (addressError != null || latitudeError != null || longitudeError != null) {
      setState(() {
        _addressError = addressError;
        _latitudeError = latitudeError;
        _longitudeError = longitudeError;
      });
      return;
    }

    setState(() {
      _addressError = null;
      _latitudeError = null;
      _longitudeError = null;
      _isLoading = true;
    });

    try {
      final classroomText = _classroomController.text.trim();

      CourseLocation? location;
      if (hasAddress && hasLat && hasLon) {
        final latitude = double.tryParse(latText);
        final longitude = double.tryParse(lonText);
        if (latitude != null && longitude != null) {
          location = CourseLocation(
            classroom: classroomText.isEmpty ? null : classroomText,
            address: addressText,
            latitude: latitude.toStringAsFixed(6),
            longitude: longitude.toStringAsFixed(6),
          );
        } else {
          setState(() {
            _latitudeError = '格式不正确';
            _longitudeError = '格式不正确';
          });
          return;
        }
      }

      final settings = CourseSettings(
        location: location,
        imageObjectIds: _imageObjectIds.isEmpty ? null : _imageObjectIds,
      );

      await CourseSetting.saveSettings(widget.courseId, settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程设置'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '位置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _classroomController,
                    decoration: const InputDecoration(
                      labelText: '教室(可选)',
                      hintText: '1教-3211',
                      prefixIcon: Icon(Icons.meeting_room),
                      border: OutlineInputBorder()
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: '地址',
                      hintText: '北京市海淀区上地七街1号北京市海淀区上地七街1号',
                      prefixIcon: const Icon(Icons.place),
                      border: const OutlineInputBorder(),
                      errorText: _addressError
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latitudeController,
                          decoration: InputDecoration(
                            labelText: '纬度',
                            hintText: '40.040905',
                            prefixIcon: const Icon(Icons.north),
                            border: const OutlineInputBorder(),
                            errorText: _latitudeError
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _longitudeController,
                          decoration: InputDecoration(
                            labelText: '经度',
                            hintText: '116.318506',
                            prefixIcon: const Icon(Icons.east),
                            border: const OutlineInputBorder(),
                            errorText: _longitudeError
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton.filled(
                        onPressed: _showMapPicker,
                        icon: const Icon(Icons.map),
                        tooltip: '选择位置'
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '图片',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (_imageObjectIds.isNotEmpty) ...[
                            SizedBox(
                              height: 80,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _imageObjectIds.length,
                                itemBuilder: (context, index) {
                                  final objectId = _imageObjectIds[index];
                                  final localPath = _localImagePaths[objectId];
                                  final isUploading = objectId.startsWith('temp_');
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ImageThumbnail(
                                      file: localPath != null ? File(localPath) : null,
                                      objectId: objectId,
                                      fit: BoxFit.contain,
                                      overlay: isUploading
                                          ? Container(
                                              color: Colors.black.withValues(alpha: 0.3),
                                              child: const Center(
                                                child: CircularProgressIndicator(
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              ),
                                            )
                                          : null,
                                      onDelete: () => _removeImage(index),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _pickAndUploadImage(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('拍照'),
                              ),
                              ElevatedButton.icon(
                                onPressed: () => _pickAndUploadImage(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('相册'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text(
                        '保存设置',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
