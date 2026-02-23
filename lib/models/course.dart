class Course {
  final String courseId;
  final String classId;
  final String cpi;
  final String image;
  final String name;
  final String teacher;
  final bool state;

  final String? note;
  final String? schools;
  final String? beginDate;
  final String? endDate;


  Course({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.image,
    required this.name,
    required this.teacher,
    required this.schools,
    required this.note,
    required this.state,
    required this.beginDate,
    required this.endDate
  });

  /// channelList
  factory Course.fromJson(Map<String, dynamic> json) {
    dynamic content = json['content'];
    dynamic courseData = content['course']['data'][0];
    return Course(
      courseId: courseData['id'].toString(),
      classId: content['id'].toString(),
      cpi: content['cpi'].toString(),
      image: courseData['imageurl'] ?? '',
      name: courseData['name'] ?? '未知课程',
      teacher: courseData['teacherfactor'] ?? '未知教师',
      schools: courseData['schools'],
      note: content['name'],
      state: content['state'] == 0,
      beginDate: content['beginDate'],
      endDate: content['endDate']
    );
  }

  Map<String, String> toJson() {
    return {
      'courseId': courseId,
      'classId': classId,
      'cpi': cpi,
      'image': image,
      'name': name,
      'teacher': teacher,
      'schools': schools ?? '',
      'note': note ?? '',
      'state': state.toString(),
      'beginDate': beginDate ?? '',
      'endDate': endDate ?? ''
    };
  }
}