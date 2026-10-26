import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/models/course.dart';

/// 用真实抓包数据验证课程解析逻辑。
///
/// 数据来源：changjiang.yuketang.cn 的 /v/course_meta/learning_list/ 响应。
///
/// HAR 文件不在仓库中，需通过环境变量提供；缺失时整组测试自动跳过：
/// ```
/// $env:HAR_PATH = "C:\path\to\capture.har"; flutter test test/course_parse_test.dart
/// ```
const _skipReason = '未找到 HAR 抓包文件（设置 HAR_PATH 环境变量后运行）';

void main() {
  late List<dynamic> rawData;

  final harPath = Platform.environment['HAR_PATH'] ??
      r'C:\Users\Administrator\Desktop\changjiang.yuketang.cn_2026_10_26_12_49_23.har';
  final hasHar = File(harPath).existsSync();

  setUpAll(() {
    if (!hasHar) return;
    final har = jsonDecode(File(harPath).readAsStringSync()) as Map<String, dynamic>;
    final entries = (har['log'] as Map)['entries'] as List;
    final content = (entries.first as Map)['response']['content'] as Map;

    var text = content['text'] as String;
    if (content['encoding'] == 'base64') {
      text = utf8.decode(base64Decode(text));
    }
    final body = jsonDecode(text) as Map<String, dynamic>;
    rawData = body['data'] as List;
  });

  test('解析全部 17 门课程', () {
    final courses = <Course>[];
    for (final item in rawData) {
      courses.add(Course.fromRCJson(Map<String, dynamic>.from(item as Map)));
    }

    expect(courses.length, 17);
  }, skip: hasHar ? null : _skipReason);

  test('字段解析正确', () {
    final first = Course.fromRCJson(
      Map<String, dynamic>.from(rawData.first as Map),
    );

    expect(first.courseId, '3425096');
    expect(first.classId, '26656449');
    expect(first.name, '高等数学（一）');
    expect(first.teacher, '高健');
    expect(first.image, contains('qn-sx.yuketang.cn'));
    expect(first.classroomName, '2026秋-高等数学（一）-0011（讲授）');
  }, skip: hasHar ? null : _skipReason);

  test('role 映射：6 为教师，5 为学生', () {
    final teachers = <Course>[];
    final students = <Course>[];

    for (final item in rawData) {
      final map = Map<String, dynamic>.from(item as Map);
      final course = Course.fromRCJson(map);
      (course.isTeacher ? teachers : students).add(course);
    }

    expect(teachers.length, 4);
    expect(students.length, 13);
    expect(teachers.every((c) => c.isTeacher), isTrue);
    expect(students.every((c) => !c.isTeacher), isTrue);
  }, skip: hasHar ? null : _skipReason);

  test('所有课程 id 均非空', () {
    for (final item in rawData) {
      final course = Course.fromRCJson(Map<String, dynamic>.from(item as Map));
      expect(course.courseId.isNotEmpty, isTrue, reason: course.name);
      expect(course.classId.isNotEmpty, isTrue, reason: course.name);
      expect(course.name.isNotEmpty, isTrue);
    }
  }, skip: hasHar ? null : _skipReason);

  test('classroom_top 映射为 pinned', () {
    for (final item in rawData) {
      final map = Map<String, dynamic>.from(item as Map);
      final course = Course.fromRCJson(map);
      expect(course.pinned, map['classroom_top'] == true);
    }
  }, skip: hasHar ? null : _skipReason);

  test('置顶课程排在前面的排序逻辑', () {
    final pinned = <Course>[];
    final normal = <Course>[];
    for (final item in rawData) {
      final course = Course.fromRCJson(Map<String, dynamic>.from(item as Map));
      (course.pinned ? pinned : normal).add(course);
    }
    final sorted = [...pinned, ...normal];

    expect(sorted.length, 17);
    // 本数据无置顶，顺序应与原始一致
    expect(sorted.first.name, '高等数学（一）');
  }, skip: hasHar ? null : _skipReason);

  test('没有 lesson_id 时表示未在上课', () {
    final courses = rawData
        .map((e) => Course.fromRCJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    // 课程列表接口不返回 lesson_id，因此全部应为 null
    expect(courses.every((c) => c.lessonId == null), isTrue);
  }, skip: hasHar ? null : _skipReason);
}
