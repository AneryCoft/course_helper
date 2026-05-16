import 'package:course_helper/models/active.dart';
import 'package:course_helper/models/course.dart';
import 'package:course_helper/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model parsing', () {
    test('parses user from persisted json', () {
      final user = User.fromJson({
        'name': '张三',
        'avatar': 'https://example.com/avatar.png',
        'phone': '13800000000',
        'uid': '10001',
        'school': '测试大学',
        'platform': 'rainClassroom',
        'status': false,
      });

      expect(user.name, '张三');
      expect(user.uid, '10001');
      expect(user.isRainClassroom, isTrue);
      expect(user.status, isFalse);
    });

    test('parses active type and sign type', () {
      final active = Active.fromJson({
        'activeType': '2',
        'id': 123,
        'nameOne': '签到',
        'nameTwo': '进行中',
        'startTime': 1000,
        'url': '',
        'attendNum': 5,
        'status': 1,
      });

      active.signType = getSignTypeFromIndex(2);

      expect(active.activeType, ActiveType.signIn);
      expect(active.signType, SignType.qrCode);
      expect(active.status, isTrue);
    });

    test('keeps course settings when copying course', () {
      final course = Course(
        courseId: 'course-1',
        classId: 'class-1',
        image: '',
        name: '课程',
        teacher: '教师',
        state: true,
      );
      final settings = CourseSettings(
        location: CourseLocation(
          address: '教学楼',
          latitude: '30.000000',
          longitude: '120.000000',
        ),
        imageObjectIds: ['image-1'],
      );

      final copied = course.withSettings(settings);

      expect(copied.settings?.location?.address, '教学楼');
      expect(copied.settings?.imageObjectIds, ['image-1']);
    });
  });
}
