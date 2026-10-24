/// 雨课堂「题型码」→ 中文名称的统一映射。
///
/// 注意：这里的 key 是接口返回的原始题型码（0 单选 / 1 多选 / 2 填空 / 3 判断 /
/// 4 简答 / 16 判断），与 [ProblemType] 枚举的 1-based id 不是同一套编码，
/// 因此单独放在这里，供 quiz、questionnaire 等页面共用，避免各写一份。
const Map<int, String> _problemTypeNames = {
  0: '单选题',
  1: '多选题',
  2: '填空题',
  3: '判断题',
  4: '简答题',
  16: '判断题',
};

/// 根据题型码返回中文名称，未知题型返回「未知题型」。
String problemTypeName(int type) => _problemTypeNames[type] ?? '未知题型';

/// 判断题题型码（选项值为 1 表示「对」）。
const int judgementTypeId = 16;
