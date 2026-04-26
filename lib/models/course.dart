class Course {
  final String courseId;
  final String classId;
  final String? cpi;
  final String image;
  final String name;
  final String teacher;
  final bool state;

  final String? note;
  String? schools;
  final String? beginDate;
  final String? endDate;

  final String? lessonId;
  
  CourseSettings? settings;


  Course({
    required this.courseId,
    required this.classId,
    this.cpi,
    required this.image,
    required this.name,
    required this.teacher,
    this.schools,
    this.note,
    required this.state,
    this.beginDate,
    this.endDate,
    this.lessonId,
    this.settings,
  });

  factory Course.fromCXJson(Map<String, dynamic> json) {
    final content = json['content'];
    final courseData = content['course']['data'][0];
    
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

  factory Course.fromRCJson(Map<String, dynamic> json) {
    return Course(
      courseId: json['course_id']?.toString() ?? '',
      classId: json['classroom_id']?.toString() ?? '',
      image: json['teacher']?['avatar'] ?? '',
      name: json['course_name'] ?? '未知课程',
      teacher: json['teacher']?['name'] ?? '未知教师',
      note: json['classroom_name'],
      state: true,
      lessonId : json['lesson_id']
    );
  }

  Map<String, String> toJson() => {
    'courseId': courseId,
    'classId': classId,
    'cpi': cpi ?? '',
    'image': image,
    'name': name,
    'teacher': teacher,
    'schools': schools ?? '',
    'note': note ?? '',
    'state': state.toString(),
    'beginDate': beginDate ?? '',
    'endDate': endDate ?? '',
  };

  Course withSettings(CourseSettings? settings) {
    return Course(
      courseId: courseId,
      classId: classId,
      cpi: cpi,
      image: image,
      name: name,
      teacher: teacher,
      schools: schools,
      note: note,
      state: state,
      beginDate: beginDate,
      endDate: endDate,
      lessonId: lessonId,
      settings: settings,
    );
  }
}

class CourseLocation {
  final String? classroom;
  final String address;
  final String latitude;
  final String longitude;

  CourseLocation({
    this.classroom,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory CourseLocation.fromJson(Map<String, dynamic> json) {
    return CourseLocation(
      classroom: json['classroom'],
      address: json['address'],
      latitude: json['latitude'],
      longitude: json['longitude']
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'classroom': classroom,
      'address': address,
      'latitude': latitude,
      'longitude': longitude
    };
  }
}

class CourseSettings {
  final CourseLocation? location;
  final List<String>? imageObjectIds;

  CourseSettings({
    this.location,
    this.imageObjectIds,
  });

  factory CourseSettings.fromJson(Map<String, dynamic> json) {
    return CourseSettings(
      location: json['location'] != null
          ? CourseLocation.fromJson(json['location'])
          : null,
      imageObjectIds: json['imageObjectIds'] != null
          ? List<String>.from(json['imageObjectIds'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location': location?.toJson(),
      'imageObjectIds': imageObjectIds,
    };
  }

  CourseSettings copyWith({
    CourseLocation? location,
    List<String>? imageObjectIds,
  }) {
    return CourseSettings(
      location: location ?? this.location,
      imageObjectIds: imageObjectIds ?? this.imageObjectIds
    );
  }
}