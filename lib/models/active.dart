import 'package:flutter/material.dart';

enum ActiveType {
  signIn(2, '签到'),
  answer(4, '抢答'),
  topicDiscuss(5, '主题讨论'),
  pick(11, '选人'),
  questionnaire(14, '问卷'),
  live(17, '直播'),
  // work(19, '作业'),
  evaluation(23, '评分'),
  groupTask(35, '分组任务'),
  pptClass(40, 'PPT课堂'),
  quiz(42, '随堂练习'),
  vote(43, '投票'),
  notice(45, '通知'),
  feedback(46, '学生反馈'),
  timer(47, '计时器'),
  whiteboard(49, '白板'),
  syncCourse(51, '同步课堂'),
  scheduledSignIn(54, '定时签到'),
  cxMeeting(56, '超星课堂'),
  draw(59, '抽签'),
  tencentMeeting(64, '腾讯会议'),
  interactivePractice(68, '互动练习'),
  signOut(74, '签退'),
  aiEvaluate(77, 'AI实践');

  final int value;
  final String label;

  const ActiveType(this.value, this.label);

  static ActiveType? fromValue(int value) {
    try {
      return ActiveType.values.firstWhere((e) => e.value == value);
    } catch (_) {
      return null;
    }
  }
}

enum SignType {
  normal,
  qrCode,
  pattern,
  location,
  code
}

const Map<int, SignType> signTypeIndexMap = {
  0: SignType.normal,
  2: SignType.qrCode,
  3: SignType.pattern,
  4: SignType.location,
  5: SignType.code
};

SignType getSignTypeFromIndex(int index) {
  return signTypeIndexMap[index] ?? SignType.normal;
}


class Active {
  final int type;
  final String id;
  final String name;
  late String description;
  final int startTime;
  final String url;
  final bool status;
  final Map<String, dynamic> extras;
  final ActiveType activeType;
  late SignType? signType;

  Active({
    required this.type,
    required this.id,
    required this.name,
    required this.description,
    required this.startTime,
    required this.url,
    required this.status,
    required this.extras,
    this.signType
  }) : activeType = ActiveType.fromValue(type) ?? ActiveType.signIn;

  factory Active.fromJson(Map<String, dynamic> json) {
    int activeType = json['activeType'] is int ?
    json['activeType'] : int.tryParse(json['activeType']?.toString() ?? '0') ?? 0;
    // 接口不稳定
    return Active(
      type: activeType,
      id: json['id'].toString(),
      name: json['nameOne'] ?? '',
      description: json['nameTwo'] ?? '',
      startTime: json['startTime'] ?? 0,
      url: json['url'] ?? '',
      status: json['status'] == 1,
      extras: json['extraInfo'] ?? {}
    );
  }

  IconData getIcon() {
    const Map<ActiveType, IconData> iconMap = {
      // ActiveType.work: Icons.assignment,
      ActiveType.quiz: Icons.edit_note,
      ActiveType.groupTask: Icons.group,
      ActiveType.topicDiscuss: Icons.comment,
      ActiveType.answer: Icons.back_hand,
      ActiveType.pick: Icons.people,
      ActiveType.questionnaire: Icons.question_answer,
      ActiveType.live: Icons.live_tv,
      ActiveType.evaluation: Icons.star,
      ActiveType.vote: Icons.poll,
      ActiveType.notice: Icons.notifications,
      ActiveType.feedback: Icons.feedback,
      ActiveType.timer: Icons.timer,
      ActiveType.whiteboard: Icons.draw,
      ActiveType.syncCourse: Icons.sync,
      ActiveType.cxMeeting: Icons.class_,
      ActiveType.draw: Icons.casino,
      ActiveType.tencentMeeting: Icons.video_call,
      ActiveType.interactivePractice: Icons.touch_app,
      ActiveType.aiEvaluate: Icons.auto_awesome,
      ActiveType.pptClass: Icons.slideshow,
    };

    if (activeType == ActiveType.signIn || 
        activeType == ActiveType.signOut || 
        activeType == ActiveType.scheduledSignIn) {
      
      const Map<SignType, IconData> signIconMap = {
        SignType.normal: Icons.check_circle_outline,
        SignType.pattern: Icons.pattern,
        SignType.location: Icons.location_on,
        SignType.qrCode: Icons.qr_code,
        SignType.code: Icons.pin,
      };
      
      return signIconMap[signType] ?? Icons.check_circle_outline;
    }

    return iconMap[activeType] ?? Icons.help_outline;
  }
}
