import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 富文本渲染器：同时支持 Markdown 与 LaTeX 数学公式
///
/// 用于渲染 AI 回复，覆盖：
/// - Markdown：`**粗体**`、`*斜体*`、`` `行内代码` ``、代码块、列表、引用、表格、标题、分隔线
/// - 数学：`$...$` 行内公式、`$$...$$` 块级公式
///
/// 使用 gpt_markdown 统一解析，能正确处理嵌套（如粗体里包含公式）
/// 与流式输出，避免手写正则遗漏边界情况。
class AiMarkdown extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final bool selectable;

  const AiMarkdown(
    this.data, {
    super.key,
    this.style,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = style ??
        TextStyle(
          fontSize: 14,
          height: 1.65,
          color: cs.onSurface,
        );

    final markdown = GptMarkdown(
      _normalize(data),
      style: base,
      followLinkColor: true,
      useDollarSignsForLatex: true,
      // 默认实现即内置公式渲染，这里显式调用以保留其排版能力
      inlineLatexBuilder: (details) => details.defaultSpan(),
      blockLatexBuilder: (details) => details.defaultWidget(),
    );

    return selectable ? SelectionArea(child: markdown) : markdown;
  }

  /// 规范化模型偶尔写出的非标准公式标记
  ///
  /// `\(...\)` → `$...$`，`\[...\]` → `$$...$$`
  static String _normalize(String raw) {
    var text = raw;

    text = text.replaceAllMapped(
      RegExp(r'\\\((.+?)\\\)', dotAll: true),
      (m) => '\$${m.group(1)}\$',
    );
    text = text.replaceAllMapped(
      RegExp(r'\\\[(.+?)\\\]', dotAll: true),
      (m) => '\$\$${m.group(1)}\$\$',
    );

    return text;
  }
}
