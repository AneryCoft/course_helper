enum ProblemType {
  single,
  multiple,
  polling, // 投票题
  fillBlank, // 填空题
  shortAnswer, // 主观题
  judgement;

  static ProblemType fromId(int id) {
    final index = id - 1;
    if (index < 0 || index >= ProblemType.values.length) {
      throw ArgumentError('Invalid problem type id: $id');
    }
    return ProblemType.values[index];
  }

  int get id => index;
  
  String get label {
    switch (this) {
      case single:
        return '单选题';
      case multiple:
        return '多选题';
      case judgement:
        return '判断题';
      case fillBlank:
        return '填空题';
      case shortAnswer:
        return '主观题';
      case polling:
        return '投票题';
    }
  }
}

class Presentation {
  final String title;
  final int width;
  final int height;
  final String version;
  final List<PresentationSlide> slides;

  Presentation({
    required this.title,
    required this.width,
    required this.height,
    required this.version,
    required this.slides,
  });

  factory Presentation.fromJson(Map<String, dynamic> json) {
    return Presentation(
      title: json['title'] ?? '',
      width: json['width'] ?? 720,
      height: json['height'] ?? 540,
      version: json['version'] ?? '1.0',
      slides: (json['slides'] as List?)
              ?.map((s) => PresentationSlide.fromJson(s))
              .toList() ??
          [],
    );
  }
}

class PresentationSlide {
  final String id;
  final int index;
  final String cover;
  final String coverAlt;
  final String thumbnail;
  final List<Shape> shapes;
  final String note;
  final Problem? problem;

  PresentationSlide({
    required this.id,
    required this.index,
    required this.cover,
    required this.coverAlt,
    required this.thumbnail,
    required this.shapes,
    required this.note,
    this.problem,
  });

  factory PresentationSlide.fromJson(Map<String, dynamic> json) {
    return PresentationSlide(
      id: json['id'] ?? '',
      index: json['index'] ?? 0,
      cover: json['cover'] ?? '',
      coverAlt: json['coverAlt'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
      shapes: (json['shapes'] as List?)
              ?.map((s) => Shape.fromJson(s))
              .toList() ??
          [],
      note: json['note'] ?? '',
      problem: json['problem'] != null ? Problem.fromJson(json['problem']) : null,
    );
  }
}

class Shape {
  final String? text;
  final Fill fill;
  final Line line;
  final double width;
  final double height;
  final double left;
  final double top;
  final double rotation;
  final int zOrderPosition;
  final int pptShapeId;
  final int pptShapeType;

  Shape({
    this.text,
    required this.fill,
    required this.line,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.rotation,
    required this.zOrderPosition,
    required this.pptShapeId,
    required this.pptShapeType,
  });

  factory Shape.fromJson(Map<String, dynamic> json) {
    return Shape(
      text: json['Text'],
      fill: Fill.fromJson(json['Fill'] ?? {}),
      line: Line.fromJson(json['Line'] ?? {}),
      width: (json['Width'] ?? 0).toDouble(),
      height: (json['Height'] ?? 0).toDouble(),
      left: (json['Left'] ?? 0).toDouble(),
      top: (json['Top'] ?? 0).toDouble(),
      rotation: (json['Rotation'] ?? 0).toDouble(),
      zOrderPosition: json['ZOrderPosition'] ?? 0,
      pptShapeId: json['PPTShapeId'] ?? 0,
      pptShapeType: json['PPTShapeType'] ?? 0,
    );
  }
}

class Fill {
  final String backColor;
  final double transparency;
  final bool visible;

  Fill({
    required this.backColor,
    required this.transparency,
    required this.visible,
  });

  factory Fill.fromJson(Map<String, dynamic> json) {
    return Fill(
      backColor: json['BackColor'] ?? '#FFFFFF',
      transparency: (json['Transparency'] ?? 0).toDouble(),
      visible: json['Visble'] ?? false,
    );
  }
}

class Line {
  final String dashStyle;
  final String backColor;
  final bool visible;
  final double weight;

  Line({
    required this.dashStyle,
    required this.backColor,
    required this.visible,
    required this.weight,
  });

  factory Line.fromJson(Map<String, dynamic> json) {
    return Line(
      dashStyle: json['DashStyle'] ?? 'msoLineSolid',
      backColor: json['BackColor'] ?? '#000000',
      visible: json['Visble'] ?? false,
      weight: (json['Weight'] ?? 0).toDouble(),
    );
  }
}

class Problem {
  final String problemId;
  final int problemType;
  final String body;
  final int score;
  final String remark;
  final List<dynamic> answers;
  final bool hasRemark;
  final List<ProblemOption>? options;
  final int? pollingCount;

  Problem({
    required this.problemId,
    required this.problemType,
    required this.body,
    required this.score,
    required this.remark,
    required this.answers,
    required this.hasRemark,
    this.options,
    this.pollingCount,
  });

  factory Problem.fromJson(Map<String, dynamic> json) {
    return Problem(
      problemId: json['problemId'] ?? '',
      problemType: json['problemType'] ?? 0,
      body: json['body'] ?? '',
      score: json['score'] ?? 0,
      remark: json['remark'] ?? '',
      answers: json['answers'] ?? [],
      hasRemark: json['hasRemark'] ?? false,
      options: (json['options'] as List?)?.map((o) => ProblemOption.fromJson(o)).toList(),
      pollingCount: json['pollingCount'],
    );
  }
}

class ProblemOption {
  final String key;
  final String value;

  ProblemOption({
    required this.key,
    required this.value,
  });

  factory ProblemOption.fromJson(Map<String, dynamic> json) {
    return ProblemOption(
      key: json['key'] ?? '',
      value: json['value'] ?? '',
    );
  }
}